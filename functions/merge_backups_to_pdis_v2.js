const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const crypto = require('crypto');

function usageAndExit() {
  console.log('Usage: node merge_backups_to_pdis_v2.js --key /path/to/key.json [--b1 path] [--b2 path] [--target collection] [--force]');
  process.exit(1);
}

const args = process.argv.slice(2);
let keyPath = null;
let b1 = null;
let b2 = null;
let target = 'pdis_v2';
let force = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--key') { keyPath = args[++i]; }
  else if (a === '--b1') { b1 = args[++i]; }
  else if (a === '--b2') { b2 = args[++i]; }
  else if (a === '--target') { target = args[++i]; }
  else if (a === '--force') { force = true; }
  else usageAndExit();
}

try {
  if (keyPath) {
    if (!fs.existsSync(keyPath)) {
      console.error('Service account file not found at', keyPath);
      process.exit(1);
    }
    admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  } else {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }
} catch (e) {
  console.error('Failed to init firebase-admin:', e && e.message ? e.message : e);
  process.exit(1);
}

const firestore = admin.firestore();

// sensible defaults (the backups created by earlier steps)
const backupsDir = path.join(__dirname, 'backups');
if (!b1) b1 = path.join(backupsDir, 'pdis_v2_backup_2025-12-25T11-56-21-616Z.json');
if (!b2) b2 = path.join(backupsDir, 'pdis_backup_2025-12-25T11-56-55-658Z.json');

function normalizeName(n) {
  if (!n) return '';
  return n.toString().trim().toLowerCase();
}

function extractCoords(data) {
  if (!data) return null;
  // Prefer _coords if present
  if (data._coords) {
    const c = data._coords;
    let lat = c.latitude !== undefined ? c.latitude : c.lat;
    let lon = c.longitude !== undefined ? c.longitude : c.lng !== undefined ? c.lng : c.longitude;
    // sometimes backup saved with keys swapped
    if (lat !== undefined && lon !== undefined) {
      // ensure plausible lat/lon
      if (Math.abs(lat) <= 90 && Math.abs(lon) <= 180) return { latitude: lat, longitude: lon };
      // swapped?
      if (Math.abs(lon) <= 90 && Math.abs(lat) <= 180) return { latitude: lon, longitude: lat };
    }
  }
  if (data.location && data.location._latitude !== undefined && data.location._longitude !== undefined) {
    return { latitude: data.location._latitude, longitude: data.location._longitude };
  }
  // fallback: try to parse _geometry text like "\n -9.072093,39.596742,0\n"
  if (data._geometry && typeof data._geometry === 'string') {
    const match = data._geometry.match(/(-?\d+\.\d+),\s*(-?\d+\.\d+)/);
    if (match) {
      const lon = parseFloat(match[1]);
      const lat = parseFloat(match[2]);
      if (!Number.isNaN(lat) && !Number.isNaN(lon)) return { latitude: lat, longitude: lon };
    }
  }
  return null;
}

function makeKey(data) {
  const coords = extractCoords(data);
  const name = normalizeName(data && data.name ? data.name : data && data.title ? data.title : '');
  if (coords) {
    // round to 6 decimals
    const lat = Number(coords.latitude).toFixed(6);
    const lon = Number(coords.longitude).toFixed(6);
    return `${lat}|${lon}|${name}`;
  }
  // fallback to normalized name only
  return `no-coords|${name}`;
}

function makeIdFromKey(key) {
  return crypto.createHash('sha1').update(key).digest('hex').slice(0, 20);
}

function readJson(p) {
  if (!fs.existsSync(p)) {
    console.error('Backup file not found:', p);
    process.exit(1);
  }
  const raw = fs.readFileSync(p, 'utf8');
  return JSON.parse(raw);
}

(async () => {
  console.log('Reading backups:');
  console.log('  b1=', b1);
  console.log('  b2=', b2);
  const arr1 = readJson(b1);
  const arr2 = readJson(b2);
  console.log(`Loaded ${arr1.length} entries from b1 and ${arr2.length} entries from b2`);

  // Merge with dedupe: process arr1 first (prefer its entries), then arr2
  const map = new Map();
  function addEntry(entry, source) {
    const key = makeKey(entry.data);
    if (!map.has(key)) {
      map.set(key, { entry, source });
    } else {
      // already present: keep existing (from earlier source)
    }
  }

  arr1.forEach(e => addEntry(e, 'b1'));
  arr2.forEach(e => addEntry(e, 'b2'));

  console.log('After dedupe, total unique entries:', map.size);

  // Prepare docs to write
  const docs = [];
  for (const [key, val] of map.entries()) {
    const id = makeIdFromKey(key);
    // Use the original data object; ensure location is a GeoPoint if possible
    const data = val.entry.data;
    docs.push({ id, data });
  }

  // Dry-run unless --force
  if (!force) {
    console.log('Dry-run: would write', docs.length, 'documents to collection', target);
    console.log('Run again with --force to apply changes.');
    process.exit(0);
  }

  // Backup current target collection just in case
  console.log('Backing up current target collection before write...');
  const cur = [];
  let last = null;
  const pageSize = 500;
  while (true) {
    let q = firestore.collection(target).orderBy('__name__').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    snap.docs.forEach(d => cur.push({ id: d.id, data: d.data() }));
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const outFile = path.join(backupsDir, `${target}_premerge_backup_${ts}.json`);
  fs.writeFileSync(outFile, JSON.stringify(cur, null, 2), 'utf8');
  console.log('Wrote current target backup to', outFile);

  // Write merged docs in batches
  console.log('Writing merged documents to collection', target);
  const batchSize = 500;
  let batch = firestore.batch();
  let cnt = 0;
  let written = 0;
  for (let i = 0; i < docs.length; i++) {
    const doc = docs[i];
    const ref = firestore.collection(target).doc(doc.id);
    batch.set(ref, doc.data);
    cnt++;
    if (cnt >= batchSize) {
      await batch.commit();
      written += cnt;
      console.log(`Committed batch of ${cnt} documents (total written: ${written})`);
      batch = firestore.batch();
      cnt = 0;
    }
  }
  if (cnt > 0) {
    await batch.commit();
    written += cnt;
    console.log(`Committed final batch of ${cnt} documents (total written: ${written})`);
  }

  // Save merged JSON for audit
  const mergedFile = path.join(backupsDir, `${target}_merged_${ts}.json`);
  fs.writeFileSync(mergedFile, JSON.stringify(docs, null, 2), 'utf8');
  console.log('Merged JSON saved to', mergedFile);

  console.log('Merge complete. Wrote', written, 'documents to', target);
  process.exit(0);
})();
