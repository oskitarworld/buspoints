#!/usr/bin/env node
/**
 * check_category_count.js
 *
 * Quick script to check how many documents exist in `pdis` and `user_pois`
 * for a given category key, and print a few sample documents (id, category,
 * coordinates) so you can verify the fields the app expects.
 *
 * Usage:
 * node check_category_count.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --category carga_y_descarga
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');
const argv = require('minimist')(process.argv.slice(2));

function normalizeCategory(cat) {
  if (!cat) return 'otros';
  const c = cat.toString().toLowerCase().trim();
  if (c === '') return 'otros';
  return c.replace(/[^a-z0-9]+/g, '_');
}

async function sampleDocs(collectionRef, normalizedCategory, limit = 5) {
  const q = collectionRef.where('category', '==', normalizedCategory).limit(limit);
  const snap = await q.get();
  const out = [];
  snap.forEach(d => {
    const data = d.data();
    // Try to extract lat/lng from common shapes
    let lat = null, lng = null;
    if (data.latitude != null && data.longitude != null) {
      lat = data.latitude; lng = data.longitude;
    } else if (data.position && typeof data.position === 'object') {
      lat = data.position.lat || data.position.latitude;
      lng = data.position.lng || data.position.longitude;
    } else if (data.geopoint) {
      const gp = data.geopoint;
      if (gp.latitude != null && gp.longitude != null) { lat = gp.latitude; lng = gp.longitude; }
    } else if (data.geo && data.geo.geopoint) {
      const gp = data.geo.geopoint;
      if (gp.latitude != null && gp.longitude != null) { lat = gp.latitude; lng = gp.longitude; }
    }
    out.push({ id: d.id, category: data.category, lat, lng, raw: data });
  });
  return out;
}

async function main() {
  const serviceAccount = argv.serviceAccount;
  const category = argv.category || argv.c;
  if (!serviceAccount) {
    console.error('Missing --serviceAccount path');
    process.exit(1);
  }
  if (!category) {
    console.error('Missing --category e.g. carga_y_descarga');
    process.exit(1);
  }

  const saPath = path.resolve(__dirname, serviceAccount);
  if (!fs.existsSync(saPath)) {
    console.error('Service account file not found:', saPath);
    process.exit(1);
  }

  admin.initializeApp({ credential: admin.credential.cert(require(saPath)) });
  const db = admin.firestore();

  const normalized = normalizeCategory(category);
  console.log('Looking for category:', category, 'normalized:', normalized);

  // pdis
  const pdisRef = db.collection('pdis');
  const pdisSnap = await pdisRef.where('category', '==', normalized).get();
  console.log('pdis count =>', pdisSnap.size);
  const pdisSamples = await sampleDocs(pdisRef, normalized, 5);
  console.log('pdis samples:');
  pdisSamples.forEach(d => console.log(JSON.stringify(d, null, 2)));

  // user_pois (approved)
  const userRef = db.collection('user_pois');
  const userSnap = await userRef.where('status', '==', 'approved').where('category', '==', normalized).get();
  console.log('user_pois (approved) count =>', userSnap.size);
  const userSamples = await sampleDocs(userRef, normalized, 5);
  console.log('user_pois samples:');
  userSamples.forEach(d => console.log(JSON.stringify(d, null, 2)));

  console.log('Done. If counts are 0, check Firestore console to inspect documents and their `category` and coordinate fields.');
  process.exit(0);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
