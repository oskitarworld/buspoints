/**
 * migrate_pdis_from_kml.js
 *
 * Reads KML files from ../assets/pdis/ (or a configured path) and uploads
 * normalized POI documents into collection `pdis_v2` in Firestore.
 *
 * Usage:
 *   node migrate_pdis_from_kml.js --serviceAccount ../tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --kmlDir ../assets/pdis --dryRun
 *
 * Flags:
 *  --serviceAccount  Path to service account JSON (required unless using ADC)
 *  --kmlDir         Directory containing .kml files (defaults ../assets/pdis)
 *  --dryRun         If present, do not write to Firestore; just print what would be done
 *  --batchSize      Number of docs to write per batch (default 500)
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const xml2js = require('xml2js');
const argv = require('minimist')(process.argv.slice(2));

function slugify(s) {
  if (!s) return '';
  return s
    .toString()
    .normalize('NFKD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function normalizeCategory(cat) {
  if (!cat) return 'otros';
  const c = cat.toString().toLowerCase().trim();
  if (c === '') return 'otros';
  // Map icon-like or unknown categories to 'otros'
  if (/icon-?\d+/.test(c) || c.startsWith('icon-')) return 'otros';
  // Replace spaces/hyphens with underscore
  return c.replace(/[^a-z0-9]+/g, '_');
}

async function main() {
  const serviceAccount = argv.serviceAccount;
  const kmlDir = argv.kmlDir || path.resolve(__dirname, '..', 'assets', 'pdis');
  const dryRun = !!argv.dryRun;
  const batchSize = parseInt(argv.batchSize || '500', 10);

  if (serviceAccount) {
    const saPath = path.resolve(__dirname, serviceAccount);
    if (!fs.existsSync(saPath)) {
      console.error('Service account file not found:', saPath);
      process.exit(1);
    }
    admin.initializeApp({
      credential: admin.credential.cert(require(saPath))
    });
  } else {
    console.log('No --serviceAccount provided, using Application Default Credentials.');
    admin.initializeApp();
  }

  const db = admin.firestore();

  if (!fs.existsSync(kmlDir)) {
    console.error('KML directory not found:', kmlDir);
    process.exit(1);
  }

  const files = fs.readdirSync(kmlDir).filter(f => f.toLowerCase().endsWith('.kml'));
  console.log('Found KML files:', files);

  const parser = new xml2js.Parser();

  const docsToWrite = [];

  for (const file of files) {
    const full = path.join(kmlDir, file);
    const content = fs.readFileSync(full, 'utf8');
    let parsed;
    try {
      parsed = await parser.parseStringPromise(content);
    } catch (err) {
      console.error('Failed to parse', file, err);
      continue;
    }

    // KML structure varies; try to find Placemark elements via xml2js first
    let placemarks = [];
    try {
      const doc = (parsed.kml && parsed.kml.Document) ? parsed.kml.Document[0] : (parsed.kml || parsed.kml);
      if (doc) {
        const docPlacemarks = (doc.Placemark || []);
        for (const pm of docPlacemarks) placemarks.push(pm);
        // Some KMLs embed Folders
        const folders = doc.Folder || [];
        for (const folder of folders) {
          const fps = folder.Placemark || [];
          for (const pm of fps) placemarks.push(pm);
        }
      }
    } catch (err) {
      console.warn('Unexpected KML structure in', file, err);
    }

    // Fallback: if xml2js didn't find placemarks (namespaces or unexpected structure),
    // parse the file textually to quickly extract <Placemark> blocks. This is a
    // pragmatic fallback to handle KML files with namespaces that confuse xml2js.
    if (!placemarks || placemarks.length === 0) {
      const raw = content;
      const pmMatches = raw.match(/<Placemark[\s\S]*?<\/Placemark>/gi);
      if (pmMatches && pmMatches.length > 0) {
        placemarks = pmMatches.map(block => ({ _raw: block }));
      }
    }

    for (const pm of placemarks) {
      let name = '';
      let description = '';
      let coords = null;
      if (pm._raw) {
        // Extract with regex from raw Placemark block
        const raw = pm._raw;
        const nameMatch = raw.match(/<name>([\s\S]*?)<\/name>/i);
        if (nameMatch) name = nameMatch[1].replace(/<!\[CDATA\[|\]\]>/g, '').trim();
        const descMatch = raw.match(/<description>([\s\S]*?)<\/description>/i);
        if (descMatch) description = descMatch[1].replace(/<!\[CDATA\[|\]\]>/g, '').trim();
        const coordMatch = raw.match(/<coordinates>([\s\S]*?)<\/coordinates>/i);
        if (coordMatch) {
          const parts = coordMatch[1].trim().split(',');
          coords = { longitude: parseFloat(parts[0]), latitude: parseFloat(parts[1]) };
        }
      } else {
        // xml2js parsed object
        name = (pm.name && pm.name[0]) || '';
        description = (pm.description && pm.description[0]) || '';
        try {
          const geo = pm.Point && pm.Point[0] && pm.Point[0].coordinates && pm.Point[0].coordinates[0];
          if (geo) {
            // coordinates format: lon,lat[,alt]
            const parts = geo.trim().split(',');
            coords = { longitude: parseFloat(parts[0]), latitude: parseFloat(parts[1]) };
          }
        } catch (err) {
          // ignore
        }
      }

      // For this quick reimport we force the category to 'pdi' (new category name)
        // Attempt to extract category from ExtendedData or description (kept for reference)
        let category = '';
      if (pm.ExtendedData && pm.ExtendedData[0] && pm.ExtendedData[0].Data) {
        const data = pm.ExtendedData[0].Data;
        for (const d of data) {
          if (d.$ && d.$.name && d.$.name.toLowerCase().includes('category')) {
            category = (d.value && d.value[0]) || '';
            break;
          }
        }
      }
      // fallback: try to extract category from description with a simple heuristic
      if (!category && description) {
        const m = description.match(/category[:=]\s*([a-z0-9\- _]+)/i);
        if (m) category = m[1];
      }

  // Derive category from the source file name (e.g. 'parada_de_bus.kml' -> 'parada_de_bus')
  const sourceBase = path.basename(file, path.extname(file));
  const normalizedCategory = normalizeCategory(sourceBase || 'otros');
  // Keep slug based on the POI name (slug equals the name), as requested
  const slug = slugify(name || '');

      const doc = {
        name: name,
        description: description,
        slug: slug,
        category: normalizedCategory,
        geometry: coords ? { type: 'Point', coordinates: [coords.longitude, coords.latitude] } : null,
        source_file: file,
        migrated_at: admin.firestore.FieldValue.serverTimestamp()
      };

      docsToWrite.push(doc);
    }
  }

  console.log('Total docs to write:', docsToWrite.length);
  if (docsToWrite.length === 0) process.exit(0);

  if (dryRun) {
    console.log('Dry run - sample documents:');
    console.log(JSON.stringify(docsToWrite.slice(0, 10), null, 2));
    process.exit(0);
  }

  // Batch write to pdis_v2
  let written = 0;
  for (let i = 0; i < docsToWrite.length; i += batchSize) {
    const batch = db.batch();
    const slice = docsToWrite.slice(i, i + batchSize);
    for (const d of slice) {
      // Write into legacy collection 'pdis' as requested
      const ref = db.collection('pdis').doc(d.slug || undefined);
      batch.set(ref, d, { merge: true });
    }
    try {
      await batch.commit();
      written += slice.length;
      console.log(`Wrote batch ${i}..${i + slice.length - 1}`);
    } catch (err) {
      console.error('Failed to write batch', err);
      process.exit(1);
    }
  }

  console.log('Done. Wrote', written, 'documents to pdis');
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
