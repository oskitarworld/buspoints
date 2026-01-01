const admin = require('firebase-admin');
const fs = require('fs');

function usage() {
  console.error('Usage: node populate_latlng_pdis_v2.js --key /path/to/serviceAccount.json [--dry-run]');
  process.exit(2);
}

const argv = process.argv.slice(2);
let keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
let dryRun = true;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--key') {
    keyPath = argv[i+1];
    i++;
  } else if (argv[i] === '--dry-run') {
    dryRun = true;
  } else if (argv[i] === '--apply') {
    dryRun = false;
  }
}
if (!keyPath) usage();
if (!fs.existsSync(keyPath)) {
  console.error('Service account key not found at', keyPath);
  process.exit(2);
}

admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();

function extractLatLng(data) {
  // Try multiple formats similar to the client normalizer
  if (!data || typeof data !== 'object') return null;

  // direct latitude/longitude
  if (typeof data.latitude === 'number' && typeof data.longitude === 'number') return { latitude: data.latitude, longitude: data.longitude };
  if (typeof data.lat === 'number' && typeof data.lng === 'number') return { latitude: data.lat, longitude: data.lng };

  // _coords
  if (data._coords && typeof data._coords === 'object') {
    const c = data._coords;
    if (typeof c.latitude === 'number' && typeof c.longitude === 'number') return { latitude: c.latitude, longitude: c.longitude };
  }

  // location maps
  if (data.location && typeof data.location === 'object') {
    const loc = data.location;
    const rawLat = loc.latitude ?? loc._latitude ?? loc.lat ?? loc._lat;
    const rawLng = loc.longitude ?? loc._longitude ?? loc.lng ?? loc._lng;
    if (typeof rawLat === 'number' && typeof rawLng === 'number') return { latitude: rawLat, longitude: rawLng };
  }

  // geopoint stored as map
  if (data.geopoint && typeof data.geopoint === 'object') {
    const gp = data.geopoint;
    const rawLat = gp.latitude ?? gp.lat;
    const rawLng = gp.longitude ?? gp.lng;
    if (typeof rawLat === 'number' && typeof rawLng === 'number') return { latitude: rawLat, longitude: rawLng };
  }

  // geometry: GeoJSON [lng, lat]
  if (data.geometry && typeof data.geometry === 'object' && Array.isArray(data.geometry.coordinates)) {
    const coords = data.geometry.coordinates;
    const rawLng = coords[0];
    const rawLat = coords[1];
    if (typeof rawLat === 'number' && typeof rawLng === 'number') return { latitude: rawLat, longitude: rawLng };
  }

  // _geometry string like "\n 3.146968,42.362287,0\n"
  if (typeof data._geometry === 'string') {
    const m = data._geometry.match(/([0-9+\-\.]+)\s*,\s*([0-9+\-\.]+)/);
    if (m) {
      const lng = parseFloat(m[1]);
      const lat = parseFloat(m[2]);
      if (!isNaN(lat) && !isNaN(lng)) return { latitude: lat, longitude: lng };
    }
  }

  return null;
}

(async () => {
  try {
    console.log('Scanning pdis_v2 to extract lat/lng... dryRun=', dryRun);
    const col = db.collection('pdis_v2');
    const snapshot = await col.get();
    console.log('Total docs to inspect:', snapshot.size);
    const toWrite = [];
    for (const doc of snapshot.docs) {
      const data = doc.data();
      const coords = extractLatLng(data);
      if (coords) {
        const haveLat = typeof data.latitude === 'number' && typeof data.longitude === 'number';
        if (!haveLat) {
          toWrite.push({ id: doc.id, ...coords });
        }
      }
    }
    console.log('Docs missing top-level lat/lng found:', toWrite.length);
    if (dryRun) {
      console.log('Dry-run mode: not applying changes. Use --apply to write updates.');
      process.exit(0);
    }

    // Apply updates in batches
    const BATCH = 500;
    for (let i = 0; i < toWrite.length; i += BATCH) {
      const batch = db.batch();
      const slice = toWrite.slice(i, i + BATCH);
      slice.forEach((entry) => {
        const ref = col.doc(entry.id);
        batch.update(ref, { latitude: entry.latitude, longitude: entry.longitude });
      });
      console.log('Committing batch', i / BATCH + 1, 'size', slice.length);
      await batch.commit();
    }
    console.log('Done updating', toWrite.length, 'documents.');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(2);
  }
})();
