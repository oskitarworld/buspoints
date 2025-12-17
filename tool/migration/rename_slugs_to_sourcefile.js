/**
 * rename_slugs_to_sourcefile.js
 *
 * Rename document IDs (slugs) in a Firestore collection so that the new ID
 * is derived from the document's `source_file` field (filename without extension).
 *
 * Usage (dry-run default):
 *   node rename_slugs_to_sourcefile.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --collection pdis
 * To apply changes (destructive):
 *   node rename_slugs_to_sourcefile.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --collection pdis --apply
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));
const crypto = require('crypto');

function slugify(s) {
  if (!s) return '';
  return s
    .toString()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

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
  const apply = !!argv.apply; // if true, perform changes; otherwise dry-run
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

  console.log(`Renaming slugs in collection: ${collection} (dryRun=${!apply})`);

  let last = null;
  let processed = 0;
  let renamed = 0;
  let collisions = 0;

  while (true) {
    let q = db.collection(collection).orderBy(admin.firestore.FieldPath.documentId()).limit(batchSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      processed += 1;
      const data = doc.data();
      const oldId = doc.id;

      const sourceFile = data.source_file || '';
      const sourceBase = path.basename(sourceFile, path.extname(sourceFile));
      const normalized = normalizeCategory(sourceBase || 'otros');
      let newId = slugify(sourceBase || normalized || '');

      if (!newId) {
        console.log(`[SKIP] doc ${oldId} has empty derived newId (source_file='${sourceFile}')`);
        continue;
      }

      if (newId === oldId) {
        // nothing to do
        continue;
      }

      // Check for existing doc with newId
      const existing = await db.collection(collection).doc(newId).get();
      if (existing.exists) {
        // collision: append short hash of oldId
        const shortHash = crypto.createHash('sha1').update(oldId).digest('hex').slice(0, 8);
        const resolved = `${newId}_${shortHash}`;
        console.log(`[COLLISION] ${oldId} -> ${newId} (exists) -> using ${resolved}`);
        newId = resolved;
        collisions += 1;
      }

      if (apply) {
        // write new doc then delete old
        try {
          await db.collection(collection).doc(newId).set(data, { merge: true });
          await db.collection(collection).doc(oldId).delete();
          renamed += 1;
          console.log(`[RENAMED] ${oldId} -> ${newId}`);
        } catch (err) {
          console.error('[ERROR] failed to rename', oldId, '->', newId, err);
        }
      } else {
        console.log(`[DRYRUN] would rename ${oldId} -> ${newId}`);
      }
    }

    last = snap.docs[snap.docs.length - 1];
  }

  console.log('Done. Processed:', processed, 'Renamed:', renamed, 'Collisions:', collisions);
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
