const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function usageAndExit() {
  console.log('Usage: node rename_pdis_to_pdis_v2.js [--key /path/to/key.json] [--delete-old] [--force]');
  console.log('  --delete-old   : after copying, delete original docs from `pdis`');
  console.log('  --force        : required to actually delete when --delete-old is passed');
  process.exit(1);
}

// parse args
const args = process.argv.slice(2);
let keyPath = null;
let deleteOld = false;
let force = false;
for (let i = 0; i < args.length; i++) {
  const a = args[i];
  if (a === '--key') { keyPath = args[++i]; }
  else if (a === '--delete-old') { deleteOld = true; }
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
  console.error('Failed to initialize firebase-admin:', e && e.message ? e.message : e);
  process.exit(1);
}

const firestore = admin.firestore();
const SRC = 'pdis';
const DST = 'pdis_v2';

async function fetchAllDocs(collectionName) {
  const all = [];
  let last = null;
  const pageSize = 500;
  while (true) {
    let q = firestore.collection(collectionName).orderBy('__name__').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    snap.docs.forEach(d => all.push({ id: d.id, data: d.data() }));
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return all;
}

function backupToFile(prefix, docs) {
  const backupsDir = path.join(__dirname, 'backups');
  if (!fs.existsSync(backupsDir)) fs.mkdirSync(backupsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(backupsDir, `${prefix}_backup_${ts}.json`);
  fs.writeFileSync(filePath, JSON.stringify(docs, null, 2), 'utf8');
  return filePath;
}

async function copyDocs(docs) {
  const batchSize = 500;
  let batch = firestore.batch();
  let cnt = 0;
  for (let i = 0; i < docs.length; i++) {
    const doc = docs[i];
    const ref = firestore.collection(DST).doc(doc.id);
    batch.set(ref, doc.data);
    cnt++;
    if (cnt >= batchSize) {
      await batch.commit();
      console.log(`Committed copy batch of ${cnt} documents...`);
      batch = firestore.batch();
      cnt = 0;
    }
  }
  if (cnt > 0) {
    await batch.commit();
    console.log(`Committed final copy batch of ${cnt} documents.`);
  }
}

async function deleteDocs(docs) {
  if (!force) {
    console.error('Delete requested but --force not provided. Aborting delete.');
    return;
  }
  const batchSize = 500;
  let batch = firestore.batch();
  let cnt = 0;
  for (let i = 0; i < docs.length; i++) {
    const ref = firestore.collection(SRC).doc(docs[i].id);
    batch.delete(ref);
    cnt++;
    if (cnt >= batchSize) {
      await batch.commit();
      console.log(`Committed delete batch of ${cnt} documents...`);
      batch = firestore.batch();
      cnt = 0;
    }
  }
  if (cnt > 0) {
    await batch.commit();
    console.log(`Committed final delete batch of ${cnt} documents.`);
  }
}

(async () => {
  try {
    console.log(`Reading all documents from '${SRC}'...`);
    const docs = await fetchAllDocs(SRC);
    console.log(`Found ${docs.length} documents in '${SRC}'.`);

    if (docs.length === 0) {
      console.log('Nothing to do. Exiting.');
      process.exit(0);
    }

    console.log('Writing backup of source collection...');
    const backupFile = backupToFile(SRC, docs);
    console.log('Backup saved to', backupFile);

    console.log(`Copying documents to '${DST}'...`);
    await copyDocs(docs);
    console.log(`All documents copied to '${DST}'.`);

    if (deleteOld) {
      console.log('Deleting original documents from source collection...');
      await deleteDocs(docs);
      console.log('Original documents deleted. Rename complete.');
    } else {
      console.log('Original documents retained. To delete originals pass --delete-old --force');
    }

    process.exit(0);
  } catch (err) {
    console.error('Error during rename:', err && err.message ? err.message : err);
    process.exit(1);
  }
})();
