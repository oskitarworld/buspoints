const fs = require('fs');
const path = require('path');
const xml2js = require('xml2js');
const admin = require('firebase-admin');

function usage() {
  console.error('Usage: node import_assets_pdis_to_pdi_categoris.js --key /path/to/serviceAccount.json [--force]');
  process.exit(2);
}

const argv = process.argv.slice(2);
let keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
let force = false;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--key') {
    keyPath = argv[i+1];
    i++;
  } else if (argv[i] === '--force') {
    force = true;
  }
}
if (!keyPath) usage();
if (!fs.existsSync(keyPath)) {
  console.error('Service account key not found at', keyPath);
  process.exit(2);
}

admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const firestore = admin.firestore();

const assetsDir = path.join(__dirname, '..', 'assets', 'pdis');
if (!fs.existsSync(assetsDir)) {
  console.error('assets/pdis directory not found');
  process.exit(2);
}

function slugify(input) {
  if (!input) return '';
  let s = input.toString().toLowerCase();
  s = s.replace(/[^a-z0-9\s\-_]/g, '_');
  s = s.replace(/[\s\-_]+/g, '_');
  s = s.replace(/^_+|_+$/g, '');
  return s;
}

function extractCoordinate(coordText) {
  if (!coordText) return null;
  const parts = coordText.trim().split(/\s+/)[0].split(',');
  if (parts.length < 2) return null;
  const lon = parseFloat(parts[0]);
  const lat = parseFloat(parts[1]);
  if (Number.isNaN(lat) || Number.isNaN(lon)) return null;
  return { latitude: lat, longitude: lon };
}

async function parseKmlFile(filePath) {
  const raw = fs.readFileSync(filePath, 'utf8');
  const parser = new xml2js.Parser();
  const result = await parser.parseStringPromise(raw);
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
  return placemarks;
}

(async () => {
  try {
    const files = fs.readdirSync(assetsDir).filter(f => f.toLowerCase().endsWith('.kml'));
    if (!files.length) {
      console.log('No KML files found in assets/pdis');
      process.exit(0);
    }

    console.log('Found KML files:', files);

    const batchSize = 500;
    let batch = firestore.batch();
    let batchCount = 0;
    let total = 0;

    for (const file of files) {
      const categoryRaw = path.basename(file, path.extname(file));
      const category = slugify(categoryRaw);
      const fullPath = path.join(assetsDir, file);
      console.log(`Processing ${file} -> category '${category}'`);
      const placemarks = await parseKmlFile(fullPath);
      console.log(`  Found ${placemarks.length} placemarks in ${file}`);

      for (const pm of placemarks) {
        const name = (pm.name && pm.name[0]) || null;
        const description = (pm.description && pm.description[0]) || null;

        let coords = null;
        let geometryRaw = null;

        if (pm.Point && pm.Point[0] && pm.Point[0].coordinates) {
          geometryRaw = pm.Point[0].coordinates[0];
          coords = extractCoordinate(geometryRaw);
        } else if (pm.MultiGeometry && pm.MultiGeometry[0]) {
          const mg = pm.MultiGeometry[0];
          if (mg.Point && mg.Point[0] && mg.Point[0].coordinates) {
            geometryRaw = mg.Point[0].coordinates[0];
            coords = extractCoordinate(geometryRaw);
          }
        } else if (pm.Polygon && pm.Polygon[0]) {
          geometryRaw = JSON.stringify(pm.Polygon[0]);
        } else {
          const pmStr = JSON.stringify(pm);
          const match = pmStr.match(/coordinates\":\[(?:\\?\"?)([^\"]+)(?:\\?\"?)/);
          if (match) coords = extractCoordinate(match[1]);
        }

        const doc = {
          name: name,
          description: description,
          category: category,
          source_file: file,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        if (coords) {
          doc.latitude = coords.latitude;
          doc.longitude = coords.longitude;
          doc.location = new admin.firestore.GeoPoint(coords.latitude, coords.longitude);
          doc._coords = coords;
        }
        if (geometryRaw) doc._geometry = geometryRaw;

        // ExtendedData
        if (pm.ExtendedData && pm.ExtendedData[0] && pm.ExtendedData[0].Data) {
          try {
            const data = pm.ExtendedData[0].Data;
            for (const d of data) {
              const key = (d.$ && d.$.name) || null;
              const value = (d.value && d.value[0]) || null;
              if (key) doc[key] = value;
            }
          } catch (e) {
            // ignore
          }
        }

        // Deterministic ID: slug(name)_category
        const slugName = slugify(name || 'unnamed');
        const id = `${slugName}_${category}`;
        const ref = firestore.collection('pdi_categoris').doc(id);

        if (!force) {
          // set only if doc does not exist
          batchCount++;
          batch.set(ref, doc, { merge: false });
        } else {
          batchCount++;
          batch.set(ref, doc, { merge: true });
        }

        total++;

        if (batchCount >= batchSize) {
          await batch.commit();
          console.log(`Committed ${batchCount} documents (total so far: ${total}).`);
          batch = firestore.batch();
          batchCount = 0;
        }
      }
    }

    if (batchCount > 0) {
      await batch.commit();
      console.log(`Committed final ${batchCount} documents (total: ${total}).`);
    }

    console.log(`Import finished. Wrote/updated ${total} documents to 'pdi_categoris'.`);
    process.exit(0);
  } catch (e) {
    console.error('Error during import:', e && e.message ? e.message : e);
    process.exit(2);
  }
})();
