// list_categories.js
// Usage:
// node list_categories.js --serviceAccount ../buspoint-...json --limitSamples 3

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function parseArgs() {
  const argv = require('minimist')(process.argv.slice(2));
  return {
    serviceAccount: argv.serviceAccount || argv.s || null,
    limitSamples: parseInt(argv.limitSamples || argv.l || '3', 10),
    collection: argv.collection || 'pdis'
  };
}

function normalizeCategory(cat) {
  if (!cat) return 'UNKNOWN';
  // simple normalizer: lowercase, trim, spaces/hyphens -> underscore, remove accents
  const noAccents = cat.normalize('NFD').replace(/\p{Diacritic}/gu, '');
  return noAccents
    .toLowerCase()
    .trim()
    .replace(/[\s\-]+/g, '_')
    .replace(/[^\w_]/g, '');
}

async function main() {
  const args = parseArgs();
  if (!args.serviceAccount) {
    console.error('Missing --serviceAccount path');
    process.exit(1);
  }

  const saPath = path.resolve(process.cwd(), args.serviceAccount);
  if (!fs.existsSync(saPath)) {
    console.error('Service account file not found at', saPath);
    process.exit(2);
  }

  const serviceAccount = require(saPath);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  const db = admin.firestore();

  console.log('Listing categories in collection:', args.collection);

  const counts = new Map();
  const samples = new Map();

  const snap = await db.collection(args.collection).get();
  console.log('Total docs in', args.collection, '=>', snap.size);

  for (const doc of snap.docs) {
    const data = doc.data();
    const rawCat = data.category || data.type || data.source_file || 'UNKNOWN';
    const cat = normalizeCategory(String(rawCat));
    counts.set(cat, (counts.get(cat) || 0) + 1);
    if (!samples.has(cat)) samples.set(cat, []);
    if (samples.get(cat).length < args.limitSamples) {
      const hasGeo = !!(
        (data.latitude !== undefined && data.longitude !== undefined) ||
        (data.position && (data.position.lat || data.position.lng)) ||
        (data.geometry && data.geometry.coordinates && Array.isArray(data.geometry.coordinates) && data.geometry.coordinates.length >= 2) ||
        (data.location && (data.location.latitude || data.location.longitude)) ||
        (data.geo && data.geo.latitude && data.geo.longitude)
      );
      samples.get(cat).push({
        id: doc.id,
        categoryRaw: rawCat,
        normalized: cat,
        hasGeometryCoordinates: !!(data.geometry && Array.isArray(data.geometry.coordinates)),
        hasGeo,
        sampleCoords: (data.geometry && Array.isArray(data.geometry.coordinates)) ? data.geometry.coordinates : null,
      });
    }
  }

  // Sort categories by count desc
  const sorted = Array.from(counts.entries()).sort((a, b) => b[1] - a[1]);
  console.log('\nCategories found (normalized -> count):');
  for (const [cat, cnt] of sorted) {
    console.log(`${cat} -> ${cnt}`);
    const s = samples.get(cat) || [];
    for (const sm of s) {
      console.log('  sample:', JSON.stringify(sm));
    }
  }

  process.exit(0);
}

main().catch(e => {
  console.error('Error:', e);
  process.exit(99);
});
