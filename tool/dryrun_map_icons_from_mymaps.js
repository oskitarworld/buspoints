/*
Dry-run mapper: fetch KML from a Google My Maps edit URL (or KML URL), extract styles -> href, list storage icons under prefix, attempt basename mapping, and produce CSV proposals.
Usage:
  node tool/dryrun_map_icons_from_mymaps.js --serviceAccount=tool/sa.json --editUrl="https://www.google.com/maps/d/u/0/edit?mid=..." --bucket=buspoint-49ea0.firebasestorage.app --prefix=pdis_icons/ --out=tool/dryrun_icon_map.csv --sample=10

Notes:
- Will not modify Firestore. Produces a CSV with: placemarkName,placemarkLat,placemarkLon,styleId,origHref,proposedType,proposedValue,matchedDocId
- proposedType: storage_signed_url | storage_path | remote_href | none
*/

const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));
const fetch = globalThis.fetch || require('node-fetch');
const { XMLParser } = require('fast-xml-parser');
const admin = require('firebase-admin');

const saPath = argv.serviceAccount || argv.s || 'tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json';
const editUrl = argv.editUrl || argv.kmlUrl || argv.url;
const bucketName = argv.bucket || argv.b || 'buspoint-49ea0.firebasestorage.app';
const prefix = argv.prefix || 'pdis_icons/';
const outCsv = argv.out || 'tool/dryrun_icon_map.csv';
const sample = parseInt(argv.sample || argv.n || '10', 10);

if (!editUrl) {
  console.error('Missing --editUrl with My Maps edit URL or KML URL');
  process.exit(1);
}
if (!fs.existsSync(saPath)) {
  console.error('Service account not found:', saPath);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(saPath))) });
const firestore = admin.firestore();
const storage = admin.storage().bucket(argv.bucket || argv.b || 'buspoint-49ea0.firebasestorage.app');

function buildKmlExportUrl(edit) {
  try {
    const u = new URL(edit);
    const mid = u.searchParams.get('mid');
    if (mid) {
      return `https://www.google.com/maps/d/kml?mid=${mid}&forcekml=1`;
    }
    return edit; // maybe already kml url
  } catch (e) {
    return edit;
  }
}

function normalizeName(s) {
  return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
}

(async () => {
  try {
    const kmlUrl = buildKmlExportUrl(editUrl);
    console.log('Fetching KML from', kmlUrl);
    const res = await fetch(kmlUrl);
    if (!res.ok) throw new Error('Failed to fetch KML: ' + res.status);
    const kmlText = await res.text();

    const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@_' });
    const j = parser.parse(kmlText);
    // KML structure: kml.Document.Style and .Placemark ... but namespaces may wrap
    const doc = (j.kml && j.kml.Document) ? j.kml.Document : (j.Document ? j.Document : (j.gm && j.gm.Document ? j.gm.Document : j));

    const styles = {};
    const styleNodes = doc.Style ? (Array.isArray(doc.Style) ? doc.Style : [doc.Style]) : [];
    // also some KMLs have StyleMap, and nested in Document->Style
    if (styleNodes.length === 0 && doc.StyleMap) {
      // ignore for now
    }

    // Collect Styles from anywhere in the parsed tree
    function collectStyles(node) {
      if (!node || typeof node !== 'object') return;
      for (const k of Object.keys(node)) {
        if (k === 'Style') {
          const arr = Array.isArray(node[k]) ? node[k] : [node[k]];
          for (const s of arr) {
            const id = s['@_id'] || s['@_id'] || s['@_id'];
            let href = null;
            if (s.Icon && s.Icon.href) href = s.Icon.href;
            styles[id] = href;
          }
        } else if (k === 'StyleMap') {
          const arr = Array.isArray(node[k]) ? node[k] : [node[k]];
          for (const sm of arr) {
            const id = sm['@_id'];
            // StyleMap pairs may reference styleUrls
            // skip detailed mapping for now
          }
        } else if (typeof node[k] === 'object') {
          collectStyles(node[k]);
        }
      }
    }
    collectStyles(j);

    // Extract placemarks
    const placemarks = [];
    function collectPlacemarks(node) {
      if (!node || typeof node !== 'object') return;
      for (const k of Object.keys(node)) {
        if (k === 'Placemark') {
          const arr = Array.isArray(node[k]) ? node[k] : [node[k]];
          for (const p of arr) {
            const name = p.name || '';
            const styleUrl = p.styleUrl || null;
            // coordinates can be inside Point->coordinates
            let lat = null, lon = null;
            if (p.Point && p.Point.coordinates) {
              const coords = String(p.Point.coordinates).trim();
              const parts = coords.split(',');
              lon = parseFloat(parts[0]); lat = parseFloat(parts[1]);
            }
            // Some placemarks have MultiGeometry or other shapes; skip for now
            placemarks.push({ name, styleUrl, lat, lon, raw: p });
          }
        } else if (typeof node[k] === 'object') {
          collectPlacemarks(node[k]);
        }
      }
    }
    collectPlacemarks(j);

    console.log('Found styles keys:', Object.keys(styles).length, 'and placemarks:', placemarks.length);

    // List storage files under prefix
    console.log('Listing storage files under prefix', prefix);
    const [files] = await storage.getFiles({ prefix });
    const storageByBasename = {};
    for (const f of files) {
      const name = f.name; // e.g. pdis_icons/icon-1.png
      const basename = path.basename(name).toLowerCase();
      storageByBasename[basename] = f;
    }
    console.log('Found', Object.keys(storageByBasename).length, 'files in storage prefix');

    // Helper to get signed URL for a storage file (long expiry)
    async function signedUrlForFile(file) {
      try {
        const expires = new Date('2035-03-01').toISOString();
        const [url] = await file.getSignedUrl({ action: 'read', expires });
        return url;
      } catch (e) {
        return null;
      }
    }

    // Build proposals per placemark
    const rows = [];
    for (const p of placemarks) {
      const styleRef = p.styleUrl ? String(p.styleUrl).replace(/^#/, '') : null;
      const origHref = (styleRef && styles[styleRef]) ? styles[styleRef] : null;
      let proposedType = 'none';
      let proposedValue = '';
      if (origHref) {
        const basename = path.basename(origHref).toLowerCase();
        const normalized = basename.replace(/[^a-z0-9_.-]+/g, '');
        // try exact match
        const f = storageByBasename[basename] || storageByBasename[normalized];
        if (f) {
          // get signed url (sync later)
          proposedType = 'storage_signed_url';
          proposedValue = f.name; // placeholder, replace with signed url later
          rows.push({ name: p.name, lat: p.lat, lon: p.lon, styleId: styleRef, origHref, proposedType, proposedValue, storageFile: f.name });
          continue;
        } else {
          // no local file matched, propose remote href
          proposedType = 'remote_href';
          proposedValue = origHref;
          rows.push({ name: p.name, lat: p.lat, lon: p.lon, styleId: styleRef, origHref, proposedType, proposedValue });
          continue;
        }
      } else {
        rows.push({ name: p.name, lat: p.lat, lon: p.lon, styleId: styleRef, origHref: null, proposedType: 'none', proposedValue: '' });
      }
    }

    // For rows with storageFile, replace with signed url
    for (const r of rows) {
      if (r.storageFile) {
        const file = storage.file(r.storageFile);
        const url = await signedUrlForFile(file);
        if (url) {
          r.proposedValue = url;
        } else {
          r.proposedType = 'storage_path';
          r.proposedValue = 'gs://' + bucketName + '/' + r.storageFile;
        }
      }
    }

    // Try to match to Firestore docId by name + coords
    for (const r of rows) {
      let matchedId = '';
      try {
        if (r.name) {
          const q = firestore.collection('Pdis_full').where('name', '==', r.name).limit(5);
          const snap = await q.get();
          if (!snap.empty) {
            // choose nearest by coords if coords available
            let best = null; let bestDist = Infinity;
            snap.forEach(doc => {
              const d = doc.data();
              const lat = d.latitude || d.lat || null;
              const lon = d.longitude || d.long || d.lng || null;
              if (lat && lon && r.lat && r.lon) {
                const dist = Math.hypot(lat - r.lat, lon - r.lon);
                if (dist < bestDist) { bestDist = dist; best = doc; }
              } else if (!best) {
                best = doc;
              }
            });
            if (best) matchedId = best.id;
          }
        }
      } catch (e) {
        // ignore
      }
      r.matchedDocId = matchedId;
    }

    // Write CSV
    const header = ['placemarkName','placemarkLat','placemarkLon','styleId','origHref','proposedType','proposedValue','matchedDocId'];
    const lines = [header.join(',')];
    for (const r of rows) {
      const cols = [
        '"' + (r.name||'') + '"',
        r.lat || '',
        r.lon || '',
        r.styleId || '',
        '"' + (r.origHref||'') + '"',
        r.proposedType || '',
        '"' + (r.proposedValue||'') + '"',
        r.matchedDocId || ''
      ];
      lines.push(cols.join(','));
    }
    fs.writeFileSync(outCsv, lines.join('\n'), 'utf8');
    console.log('Wrote dry-run CSV to', outCsv);
    console.log('Sample rows:');
    const sampleRows = rows.slice(0, sample);
    sampleRows.forEach((r,i) => {
      console.log(`${i+1}. name="${r.name}" lat=${r.lat} lon=${r.lon} styleId=${r.styleId} proposed=${r.proposedType} matchedDoc=${r.matchedDocId}`);
      console.log('   origHref=', r.origHref);
      console.log('   proposedValue=', r.proposedValue);
    });
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(2);
  }
})();
