const fs = require('fs');
const path = require('path');
const xml2js = require('xml2js');
const admin = require('firebase-admin');

// Init Firebase Admin using application default credentials.
// Make sure GOOGLE_APPLICATION_CREDENTIALS is set to a service account JSON before running.
try {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
} catch (e) {
  console.error('Failed to initialize firebase-admin. Make sure GOOGLE_APPLICATION_CREDENTIALS is set and points to a valid service account JSON.');
  console.error(e.message || e);
  process.exit(1);
}

const firestore = admin.firestore();

// Path to the KML file (relative to functions/)
const kmlPath = path.join(__dirname, '..', 'assets', 'pdifull_icon', 'pdi_full.kml');

if (!fs.existsSync(kmlPath)) {
  console.error('KML file not found at:', kmlPath);
  process.exit(1);
}

const raw = fs.readFileSync(kmlPath, 'utf8');

const parser = new xml2js.Parser();

function extractCoordinate(coordText) {
  // KML coords are lon,lat[,alt]
  if (!coordText) return null;
  const parts = coordText.trim().split(/\s+/)[0].split(',');
  if (parts.length < 2) return null;
  const lon = parseFloat(parts[0]);
  const lat = parseFloat(parts[1]);
  if (Number.isNaN(lat) || Number.isNaN(lon)) return null;
  return { latitude: lat, longitude: lon };
}

parser.parseStringPromise(raw).then(async (result) => {
  // Try to find all Placemark elements in the document
  const placemarks = [];

  function walk(obj) {
    if (!obj || typeof obj !== 'object') return;
    for (const key of Object.keys(obj)) {
      if (key === 'Placemark') {
        const items = obj[key];
        if (Array.isArray(items)) placemarks.push(...items);
      } else {
        const child = obj[key];
        if (Array.isArray(child)) {
          for (const c of child) walk(c);
        } else {
          walk(child);
        }
      }
    }
  }

  walk(result);

  if (!placemarks.length) {
    console.log('No Placemark elements found in KML. Nothing to import.');
    process.exit(0);
  }

  console.log(`Found ${placemarks.length} placemarks. Starting import to collection 'pdis'...`);

  const batchSize = 500;
  let batch = firestore.batch();
  let batchCount = 0;
  let total = 0;

  for (const pm of placemarks) {
    const name = (pm.name && pm.name[0]) || null;
    const description = (pm.description && pm.description[0]) || null;

    // Try common geometry types
    let coords = null;
    let geometryRaw = null;

    if (pm.Point && pm.Point[0] && pm.Point[0].coordinates) {
      geometryRaw = pm.Point[0].coordinates[0];
      coords = extractCoordinate(geometryRaw);
    } else if (pm.MultiGeometry && pm.MultiGeometry[0]) {
      // try to find a Point inside
      const mg = pm.MultiGeometry[0];
      if (mg.Point && mg.Point[0] && mg.Point[0].coordinates) {
        geometryRaw = mg.Point[0].coordinates[0];
        coords = extractCoordinate(geometryRaw);
      }
    } else if (pm.Polygon && pm.Polygon[0]) {
      // store polygon raw text
      geometryRaw = JSON.stringify(pm.Polygon[0]);
    } else {
      // fallback: search inside for coordinates fields
      const pmStr = JSON.stringify(pm);
      const match = pmStr.match(/coordinates\":\[(?:\\?\"?)([^\"]+)(?:\\?\"?)/);
      if (match) {
        coords = extractCoordinate(match[1]);
      }
    }

    const doc = {
      name: name,
      description: description,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (coords) {
      doc.location = new admin.firestore.GeoPoint(coords.latitude, coords.longitude);
      doc._coords = coords; // keep numeric copy for reference
    }
    if (geometryRaw) doc._geometry = geometryRaw;

    // Add any ExtendedData simple key/values
    if (pm.ExtendedData && pm.ExtendedData[0] && pm.ExtendedData[0].Data) {
      try {
        const data = pm.ExtendedData[0].Data;
        for (const d of data) {
          const key = (d.$ && d.$.name) || null;
          const value = (d.value && d.value[0]) || null;
          if (key) doc[key] = value;
        }
      } catch (e) {
        // ignore extended data parse errors
      }
    }

    // write doc with auto ID
    const ref = firestore.collection('pdis').doc();
    batch.set(ref, doc);
    batchCount++;
    total++;

    if (batchCount >= batchSize) {
      await batch.commit();
      console.log(`Committed ${batchCount} documents (total so far: ${total}).`);
      batch = firestore.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
    console.log(`Committed final ${batchCount} documents (total: ${total}).`);
  }

  console.log(`Import finished. Total documents written: ${total}`);
  process.exit(0);

}).catch((err) => {
  console.error('Failed to parse KML:', err && err.message ? err.message : err);
  process.exit(1);
});
