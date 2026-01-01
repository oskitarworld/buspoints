/*
Import KMZ (assets/pdifull_icon/buspointfull.KMZ) into Firestore collection Pdis_full.
- Extracts doc.kml
- Parses <Placemark> entries, extracting name, description, coordinates, styleUrl/icon href
- Maps icon filename to uploaded Storage file under prefix (e.g. pdis_icons/icon-17.png)
- Generates signed URL for each matched icon and writes iconPath
- Inserts documents into Firestore in batches

Usage:
  node tool/import_kmz_to_firestore.js --serviceAccount=tool/sa.json --kmz=assets/pdifull_icon/buspointfull.KMZ --bucket=buspoint-49ea0.firebasestorage.app --prefix=pdis_icons/ [--apply]

By default runs in dry-run mode; pass --apply to perform writes.
*/

const AdmZip = require('adm-zip');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

const saPath = argv.serviceAccount || argv.s;
const kmzPath = argv.kmz || argv.k;
const bucketName = argv.bucket;
const prefix = argv.prefix || 'pdis_icons/';
const apply = argv.apply || false;

if (!saPath || !kmzPath || !bucketName) {
  console.log('Usage: node tool/import_kmz_to_firestore.js --serviceAccount=tool/sa.json --kmz=assets/pdifull_icon/buspointfull.KMZ --bucket=buspoint-49ea0.firebasestorage.app --prefix=pdis_icons/ [--apply]');
  process.exit(1);
}
if (!fs.existsSync(saPath)) { console.error('Service account not found:', saPath); process.exit(2); }
if (!fs.existsSync(kmzPath)) { console.error('KMZ file not found:', kmzPath); process.exit(2); }

const sa = require(path.resolve(saPath));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const firestore = admin.firestore();
const bucket = admin.storage().bucket(bucketName);
const { XMLParser } = require('fast-xml-parser');

function stripCdata(s) {
  if (!s) return s;
  return s.replace(/^<!\[CDATA\[/, '').replace(/\]\]>$/, '').trim();
}

function extractPlacemarkBlocks(kmlText) {
  const blocks = [];
  const re = /<Placemark[\s\S]*?<\/Placemark>/gi;
  let m;
  while ((m = re.exec(kmlText))) {
    blocks.push(m[0]);
  }
  return blocks;
}

function extractTagValue(block, tag) {
  // match optional namespace prefix: <ns:name> and </ns:name>
  const re = new RegExp('<(?:[a-zA-Z0-9_:-]*:)?' + tag + '[^>]*>([\s\S]*?)<\/(?:[a-zA-Z0-9_:-]*:)?' + tag + '>', 'i');
  const m = re.exec(block);
  if (!m) return null;
  return stripCdata(m[1] || '');
}

function extractCoordinates(block) {
  // try <coordinates>...</coordinates> (namespaced or not)
  const coordsRe = /<(?:[a-zA-Z0-9_:-]*:)?coordinates[^>]*>([\s\S]*?)<\/(?:[a-zA-Z0-9_:-]*:)?coordinates>/i;
  let m = coordsRe.exec(block);
  let raw = m ? m[1] : null;
  // try gx:coord (sometimes used)
  if (!raw) {
    const gxRe = /<(?:[a-zA-Z0-9_:-]*:)?gx:coord[^>]*>([\s\S]*?)<\/(?:[a-zA-Z0-9_:-]*:)?gx:coord>/i;
    m = gxRe.exec(block);
    raw = m ? m[1] : null;
  }
  if (!raw) return null;
  // coordinates often 'lon,lat[,alt]'
  const first = raw.split('\n')[0].trim();
  const parts = first.split(/[\s,]+/).filter(Boolean);
  if (parts.length < 2) return null;
  const lon = parseFloat(parts[0]);
  const lat = parseFloat(parts[1]);
  if (isNaN(lat) || isNaN(lon)) return null;
  return { lat, lon };
}

function extractIconFilename(block) {
  // try <styleUrl>#icon-17 or <href>images/icon-17.png
  const style = extractTagValue(block, 'styleUrl');
  if (style) {
    // strip leading # if present
    const s = style.replace(/^#/, '');
    // if it's like icon-17 or icon-17.png
    const name = path.basename(s);
    if (name) return name;
  }
  // try Icon->href
  const hrefRe = /<Icon[\s\S]*?<href>([\s\S]*?)<\/href>[\s\S]*?<\/Icon>/i;
  const m = hrefRe.exec(block);
  if (m && m[1]) {
    const href = stripCdata(m[1]);
    return path.basename(href);
  }
  return null;
}

(async () => {
  try {
    console.log('Reading KMZ:', kmzPath);
    const zip = new AdmZip(kmzPath);
    const entries = zip.getEntries();
    const kmlEntry = entries.find(e => e.entryName.toLowerCase().endsWith('.kml') || /doc\.kml$/i.test(e.entryName));
    if (!kmlEntry) {
      console.error('No KML (doc.kml) found inside KMZ.');
      process.exit(2);
    }
    const kmlText = kmlEntry.getData().toString('utf8');

    // Use fast-xml-parser to reliably parse KML and extract Placemark objects and Styles
    const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@_', textNodeName: '#text', removeNSPrefix: true });
    let placemarkObjs = [];
    let styleIconMap = {}; // styleId -> icon href (may be remote url)

    function collectPlacemarks(node, out) {
      if (!node || typeof node !== 'object') return;
      if (node.Placemark) {
        const arr = Array.isArray(node.Placemark) ? node.Placemark : [node.Placemark];
        out.push(...arr);
      }
      for (const k of Object.keys(node)) {
        if (k === 'Placemark') continue;
        const child = node[k];
        if (Array.isArray(child)) {
          for (const c of child) collectPlacemarks(c, out);
        } else if (typeof child === 'object') {
          collectPlacemarks(child, out);
        }
      }
    }

    function buildStyleMap(root) {
      const styles = [];
      if (!root) return {};
      // Document may hold Style or StyleMap entries
      const doc = root.Document || root;
      if (!doc) return {};
      if (doc.Style) styles.push(...(Array.isArray(doc.Style) ? doc.Style : [doc.Style]));
      if (doc.StyleMap) styles.push(...(Array.isArray(doc.StyleMap) ? doc.StyleMap : [doc.StyleMap]));
      const map = {};
      for (const s of styles) {
        const id = s['@_id'] || s['@_name'] || null;
        if (!id) continue;
        // Look for Icon href inside Style -> Icon -> href
        try {
          if (s.Icon && s.Icon.href) map[id] = (typeof s.Icon.href === 'string') ? stripCdata(s.Icon.href) : (s.Icon.href['#text'] || null);
        } catch (e) {}
      }
      return map;
    }

    function getText(node) {
      if (!node) return '';
      if (typeof node === 'string') return stripCdata(node);
      if (typeof node === 'object' && node['#text']) return stripCdata(node['#text']);
      return '';
    }

    function coordsFromPlacemark(pm) {
      if (!pm) return null;
      const pick = (c) => {
        if (!c) return null;
        if (typeof c === 'string') return c;
        if (c['#text']) return c['#text'];
        return null;
      };
      let coordStr = null;
      if (pm.Point) coordStr = pick(pm.Point.coordinates || pm.Point.coordinate);
      if (!coordStr && pm.MultiGeometry && pm.MultiGeometry.Point) {
        const p = Array.isArray(pm.MultiGeometry.Point) ? pm.MultiGeometry.Point[0] : pm.MultiGeometry.Point;
        coordStr = pick(p.coordinates || p.coordinate);
      }
      if (!coordStr && pm.LineString) coordStr = pick(pm.LineString.coordinates || pm.LineString.coordinate);
      if (!coordStr) return null;
      const first = coordStr.split(/\s+/).find(Boolean);
      if (!first) return null;
      const parts = first.split(/[, ]+/).filter(Boolean);
      if (parts.length < 2) return null;
      const lon = parseFloat(parts[0]);
      const lat = parseFloat(parts[1]);
      if (isNaN(lat) || isNaN(lon)) return null;
      return { lat, lon };
    }

    // parse local KML
    try {
      const localObj = parser.parse(kmlText);
      const root = localObj.kml || localObj;
      styleIconMap = buildStyleMap(root.Document || root);
      collectPlacemarks(root.Document || root, placemarkObjs);
      console.log('Found placemarks in local KML (parsed):', placemarkObjs.length);
    } catch (e) {
      console.warn('Failed to parse local KML with XML parser:', e.message || e);
    }

    // If nothing found, try to follow NetworkLink/Link hrefs (remote KML/KMZ)
    if (placemarkObjs.length === 0) {
      const hrefRe = /<href>([\s\S]*?)<\/href>/i;
      const hrefMatch = hrefRe.exec(kmlText);
      if (hrefMatch && hrefMatch[1]) {
        const href = stripCdata(hrefMatch[1]);
        console.log('Following remote href:', href);
        try {
          const res = await fetch(href);
          if (!res.ok) throw new Error('Fetch failed: ' + res.status);
          const contentType = (res.headers.get('content-type') || '').toLowerCase();
          if (contentType.includes('kmz') || contentType.includes('zip') || href.toLowerCase().endsWith('.kmz')) {
            const buf = Buffer.from(await res.arrayBuffer());
            const remoteZip = new AdmZip(buf);
            const remoteEntries = remoteZip.getEntries();
            const remoteKmlEntry = remoteEntries.find(e => e.entryName.toLowerCase().endsWith('.kml') || /doc\.kml$/i.test(e.entryName));
            if (remoteKmlEntry) {
              const rkml = remoteKmlEntry.getData().toString('utf8');
              try {
                const remoteObj = parser.parse(rkml);
                const root = remoteObj.kml || remoteObj;
                styleIconMap = { ...styleIconMap, ...buildStyleMap(root.Document || root) };
                collectPlacemarks(root.Document || root, placemarkObjs);
                console.log('Found placemarks in remote KMZ (parsed):', placemarkObjs.length);
              } catch (e) {
                console.warn('Failed parsing KML inside remote KMZ:', e.message || e);
              }
            } else {
              console.warn('No KML inside remote KMZ');
            }
          } else {
            const remoteText = await res.text();
            try {
              const remoteObj = parser.parse(remoteText);
              const root = remoteObj.kml || remoteObj;
              styleIconMap = { ...styleIconMap, ...buildStyleMap(root.Document || root) };
              collectPlacemarks(root.Document || root, placemarkObjs);
              console.log('Found placemarks in remote KML (parsed):', placemarkObjs.length);
            } catch (e) {
              console.warn('Failed to parse remote KML with XML parser:', e.message || e);
            }
          }
        } catch (e) {
          console.warn('Failed to fetch remote href:', href, e.message || e);
        }
      }
    }

    // Pre-cache signed URLs for files in prefix
    console.log('Listing files in storage prefix', prefix);
    const [files] = await bucket.getFiles({ prefix: prefix });
    const fileMap = {};
    for (const f of files) {
      const name = path.basename(f.name);
      // generate signed URL
      try {
        const [url] = await f.getSignedUrl({ action: 'read', expires: '2035-03-01' });
        fileMap[name] = url;
      } catch (e) {
        console.warn('Could not get signed URL for', f.name, e.message || e);
      }
    }
    console.log('Cached signed URLs for', Object.keys(fileMap).length, 'files');

    const docsToWrite = [];
    for (const pm of placemarkObjs) {
      const name = getText(pm.name) || '';
      const description = getText(pm.description) || '';
      const coords = coordsFromPlacemark(pm);
      if (!coords) {
        console.warn('Skipping placemark without coords (name:', name || '[no name]', ')');
        continue;
      }

      // Resolve icon: prefer uploaded file (fileMap) if filename matches; else fall back to style icon URL from KML
      let iconUrl = null;
      // styleUrl may be string like '#icon-1532-0288D1' or object
      const rawStyle = getText(pm.styleUrl) || getText(pm['styleUrl']) || '';
      const styleId = rawStyle.replace(/^#/, '');
      const styleIcon = styleIconMap[styleId] || null;
      if (styleIcon) {
        // try to match basename to uploaded files
        const bn = path.basename(styleIcon);
        if (bn && fileMap[bn]) iconUrl = fileMap[bn];
        else iconUrl = styleIcon; // remote URL
      }

      // If no style icon resolved, try to find Icon inside pm directly
      if (!iconUrl) {
        // pm.Icon?.href
        try {
          const href = pm.Icon && (typeof pm.Icon === 'string' ? pm.Icon : (pm.Icon.href || pm.Icon['#text']));
          if (href) {
            const bn = path.basename(getText(href));
            if (bn && fileMap[bn]) iconUrl = fileMap[bn];
            else iconUrl = getText(href);
          }
        } catch (e) {}
      }

      const category = styleId || '';

      const doc = {
        name: name,
        description: description,
        latitude: coords.lat,
        longitude: coords.lon,
        category: category,
        iconPath: iconUrl,
        original_kmz: path.basename(kmzPath),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: 'approved'
      };
      docsToWrite.push(doc);
    }

    console.log('Prepared', docsToWrite.length, 'documents for insertion into Pdis_full');
    if (!apply) {
      console.log('Dry-run mode; not writing to Firestore.');
      console.log('Sample doc:', docsToWrite.slice(0,3));
      process.exit(0);
    }

    console.log('Writing to Firestore collection Pdis_full in batches...');
    const batchSize = 400;
    for (let i = 0; i < docsToWrite.length; i += batchSize) {
      const batch = firestore.batch();
      const slice = docsToWrite.slice(i, i + batchSize);
      for (const d of slice) {
        const ref = firestore.collection('Pdis_full').doc();
        batch.set(ref, d);
      }
      await batch.commit();
      console.log('Committed batch', Math.floor(i / batchSize) + 1, 'size', slice.length);
    }

    console.log('Import completed. Inserted', docsToWrite.length, 'documents into Pdis_full');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(3);
  }
})();
