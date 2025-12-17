/**
 * export_collision_docs.js
 *
 * Exports all documents referenced in tool/migration/pdis_v2_collisions.json
 * to tool/migration/pdis_v2_candidates_backup.json for safe backup before dedupe.
 *
 * Usage:
 *  node export_collision_docs.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

async function main() {
  const serviceAccount = argv.serviceAccount;
  const saPath = serviceAccount ? path.resolve(__dirname, serviceAccount) : null;
  const collisionsPath = path.resolve(__dirname, 'pdis_v2_collisions.json');

  if (!fs.existsSync(collisionsPath)) {
    console.error('Missing collisions file:', collisionsPath);
    process.exit(1);
  }

  const collisions = JSON.parse(fs.readFileSync(collisionsPath, 'utf8'));
  const slugs = (collisions.topSlugCollisions || []).map(c => c.slug);
  if (!slugs.length) {
    console.log('No slug collisions found in report to export.');
    process.exit(0);
  }

  if (serviceAccount) {
    if (!fs.existsSync(saPath)) {
      console.error('Service account file not found:', saPath);
      process.exit(1);
    }
    admin.initializeApp({ credential: admin.credential.cert(require(saPath)) });
  } else {
    console.log('No --serviceAccount provided, using Application Default Credentials.');
    admin.initializeApp();
  }

  const db = admin.firestore();
  const coll = db.collection('pdis_v2');

  const out = [];

  for (const slug of slugs) {
    console.log('Querying slug:', slug);
    const snap = await coll.where('slug', '==', slug).get();
    snap.forEach(d => {
      out.push({ id: d.id, data: d.data() });
    });
  }

  const outPath = path.resolve(__dirname, 'pdis_v2_candidates_backup.json');
  fs.writeFileSync(outPath, JSON.stringify({ exportedAt: new Date().toISOString(), count: out.length, docs: out }, null, 2));
  console.log('Export complete. Wrote', out.length, 'documents to', outPath);
}

main().catch(err => { console.error(err); process.exit(1); });
