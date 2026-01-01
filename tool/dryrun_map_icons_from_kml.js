/*
Dry-run mapper from a local KML file: extract styles -> href, list storage icons under prefix, attempt basename mapping, and produce CSV proposals.
Usage:
  node tool/dryrun_map_icons_from_kml.js --serviceAccount=tool/sa.json --kml=assets/pdifull_icon/pdifull_icon.kml --bucket=buspoint-49ea0.firebasestorage.app --prefix=pdis_icons/ --out=tool/dryrun_icon_map_local.csv --sample=10

Will not modify Firestore. Produces CSV with: placemarkName,placemarkLat,placemarkLon,styleId,origHref,proposedType,proposedValue,matchedDocId
*/

const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));
const { XMLParser } = require('fast-xml-parser');
const admin = require('firebase-admin');

const saPath = argv.serviceAccount || argv.s || 'tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json';
const kmlPath = argv.kml || argv.file;
const bucketName = argv.bucket || argv.b || 'buspoint-49ea0.firebasestorage.app';
const prefix = argv.prefix || 'pdis_icons/';
const outCsv = argv.out || 'tool/dryrun_icon_map_local.csv';
const sample = parseInt(argv.sample || argv.n || '10', 10);

if (!kmlPath) { console.error('Missing --kml local file path'); process.exit(1); }
if (!fs.existsSync(kmlPath)) { console.error('KML file not found:', kmlPath); process.exit(1); }
if (!fs.existsSync(saPath)) { console.error('Service account not found:', saPath); process.exit(1); }

admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(saPath))) });
const firestore = admin.firestore();
const storage = admin.storage().bucket(bucketName);

function normalizeName(s) { return String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, ''); }

(async () => {
  try {
    console.log('Reading KML from', kmlPath);
    const kmlText = fs.readFileSync(kmlPath, 'utf8');
    const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: '@_' });
    const j = parser.parse(kmlText);

    function collectStyles(node, out) {
      if (!node || typeof node !== 'object') return;
      for (const k of Object.keys(node)) {
        if (k === 'Style') {
          const arr = Array.isArray(node[k]) ? node[k] : [node[k]];
          for (const s of arr) {
            const id = s['@_id'] || s['@_id'] || s['id'] || s['@id'];
            let href = null;
            if (s.Icon && s.Icon.href) href = s.Icon.href;
            out[id] = href;
          }
        } else if (typeof node[k] === 'object') collectStyles(node[k], out);
      }
    }

    const styles = {};
    collectStyles(j, styles);

    const placemarks = [];
    function collectPlacemarks(node) {
      if (!node || typeof node !== 'object') return;
      for (const k of Object.keys(node)) {
        if (k === 'Placemark') {
          const arr = Array.isArray(node[k]) ? node[k] : [node[k]];
          for (const p of arr) {
            const name = p.name || '';
            const styleUrl = p.styleUrl || p.StyleUrl || null;
            let lat = null, lon = null;
            if (p.Point && p.Point.coordinates) {
              const coords = String(p.Point.coordinates).trim();
              const parts = coords.split(','); lon = parseFloat(parts[0]); lat = parseFloat(parts[1]);
            }
            placemarks.push({ name, styleUrl, lat, lon, raw: p });
          }
        } else if (typeof node[k] === 'object') collectPlacemarks(node[k]);
      }
    }
    collectPlacemarks(j);

    console.log('Found styles:', Object.keys(styles).length, 'placemarks:', placemarks.length);

    console.log('Listing storage files under prefix', prefix);
    const [files] = await storage.getFiles({ prefix });
    const storageByBasename = {};
    for (const f of files) storageByBasename[path.basename(f.name).toLowerCase()] = f;
    console.log('Found', Object.keys(storageByBasename).length, 'files in storage prefix');

    async function signedUrlForFile(file) {
      try { const expires = new Date('2035-03-01').toISOString(); const [url] = await file.getSignedUrl({ action: 'read', expires }); return url; }
      catch (e) { return null; }
    }

    const rows = [];
    for (const p of placemarks) {
      const styleRef = p.styleUrl ? String(p.styleUrl).replace(/^#/, '') : null;
      const origHref = (styleRef && styles[styleRef]) ? styles[styleRef] : null;
      let proposedType = 'none'; let proposedValue = '';
      if (origHref) {
        const basename = path.basename(origHref).toLowerCase();
        const normalized = basename.replace(/[^a-z0-9_.-]+/g, '');
        const f = storageByBasename[basename] || storageByBasename[normalized];
        if (f) { proposedType = 'storage_signed_url'; proposedValue = f.name; rows.push({ name: p.name, lat: p.lat, lon: p.lon, styleId: styleRef, origHref, proposedType, proposedValue, storageFile: f.name }); continue; }
        else { proposedType = 'remote_href'; proposedValue = origHref; rows.push({ name: p.name, lat: p.lat, lon: p.lon, styleId: styleRef, origHref, proposedType, proposedValue }); continue; }
      } else { rows.push({ name: p.name, lat: p.lat, lon: p.lon, styleId: styleRef, origHref: null, proposedType: 'none', proposedValue: '' }); }
    }

    for (const r of rows) {
      if (r.storageFile) {
        const file = storage.file(r.storageFile);
        const url = await signedUrlForFile(file);
        if (url) r.proposedValue = url; else { r.proposedType = 'storage_path'; r.proposedValue = 'gs://' + bucketName + '/' + r.storageFile; }
      }
    }

    for (const r of rows) {
      let matchedId = '';
      try {
        if (r.name) {
          const q = firestore.collection('Pdis_full').where('name', '==', r.name).limit(5);
          const snap = await q.get();
          if (!snap.empty) {
            let best = null; let bestDist = Infinity;
            snap.forEach(doc => {
              const d = doc.data(); const lat = d.latitude || d.lat || null; const lon = d.longitude || d.long || d.lng || null;
              if (lat && lon && r.lat && r.lon) { const dist = Math.hypot(lat - r.lat, lon - r.lon); if (dist < bestDist) { bestDist = dist; best = doc; } }
              else if (!best) best = doc;
            }); if (best) matchedId = best.id;
          }
        }
      } catch (e) {}
      r.matchedDocId = matchedId;
    }

    const header = ['placemarkName','placemarkLat','placemarkLon','styleId','origHref','proposedType','proposedValue','matchedDocId'];
    const lines = [header.join(',')];
    for (const r of rows) {
      const cols = ['"' + (r.name||'') + '"', r.lat || '', r.lon || '', r.styleId || '', '"' + (r.origHref||'') + '"', r.proposedType || '', '"' + (r.proposedValue||'') + '"', r.matchedDocId || ''];
      lines.push(cols.join(','));
    }
    fs.writeFileSync(outCsv, lines.join('\n'), 'utf8');
    console.log('Wrote dry-run CSV to', outCsv);
    const sampleRows = rows.slice(0, sample);
    sampleRows.forEach((r,i) => {
      console.log(`${i+1}. name="${r.name}" lat=${r.lat} lon=${r.lon} styleId=${r.styleId} proposed=${r.proposedType} matchedDoc=${r.matchedDocId}`);
      console.log('   origHref=', r.origHref);
      console.log('   proposedValue=', r.proposedValue);
    });
    process.exit(0);
  } catch (e) { console.error('Error:', e); process.exit(2); }
})();
