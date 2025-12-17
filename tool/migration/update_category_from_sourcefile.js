/**
 * update_category_from_sourcefile.js
 *
 * Update the `category` field of documents in a collection using the
 * document's `source_file` field (filename without extension). Useful to
 * fix categories after an import.
 *
 * Usage (dry-run default):
 *   node update_category_from_sourcefile.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --collection pdis
 * To apply changes:
 *   node update_category_from_sourcefile.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --collection pdis --apply
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

function normalizeCategory(cat) {
  if (!cat) return 'otros';
  const c = cat.toString().toLowerCase().trim();
  if (c === '') return 'otros';
  if (/icon-?\d+/.test(c) || c.startsWith('icon-')) return 'otros';
  return c.replace(/[^a-z0-9]+/g, '_');
}

async function main() {
  const serviceAccount = argv.serviceAccount;
  const collection = argv.collection || 'pdis';
  const apply = !!argv.apply; // if true, perform writes
  const batchSize = parseInt(argv.batchSize || '500', 10);

  if (serviceAccount) {
    const saPath = path.resolve(__dirname, serviceAccount);
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
  console.log(`Update categories from source_file for collection=${collection} (apply=${apply})`);

  let last = null;
  let processed = 0;
  let changed = 0;

  while (true) {
    let q = db.collection(collection).limit(batchSize).orderBy(admin.firestore.FieldPath.documentId());
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      processed += 1;
      const data = doc.data();
      const oldCategory = data.category || '';
      const sourceFile = data.source_file || '';
      const sourceBase = path.basename(sourceFile, path.extname(sourceFile));
      const newCategory = normalizeCategory(sourceBase || 'otros');
      if (newCategory !== oldCategory) {
        changed += 1;
        if (apply) {
          batch.set(doc.ref, { category: newCategory }, { merge: true });
          console.log(`[UPDATE] ${doc.id}: '${oldCategory}' -> '${newCategory}'`);
        } else {
          console.log(`[DRYRUN] would update ${doc.id}: '${oldCategory}' -> '${newCategory}'`);
        }
      }
    }

    if (apply) {
      await batch.commit();
    }

    last = snap.docs[snap.docs.length - 1];
  }

  console.log('Done. Processed:', processed, 'Would change or changed:', changed);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
