const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function usageAndExit() {
  console.log('Usage: node backup_and_delete_pdis_v2.js [--key /path/to/service-account.json]');
  process.exit(1);
}

// Simple arg parsing for --key
let keyPath = null;
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--key') {
    keyPath = args[i + 1];
    i++;
  } else {
    usageAndExit();
  }
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
const COLLECTION = 'pdis_v2';

async function fetchAllDocs() {
  const all = [];
  let last = null;
  const pageSize = 500;
  while (true) {
    let q = firestore.collection(COLLECTION).orderBy('__name__').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    snap.docs.forEach(d => {
      all.push({ id: d.id, data: d.data() });
    });
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }
  return all;
}

async function backupToFile(docs) {
  const backupsDir = path.join(__dirname, 'backups');
  if (!fs.existsSync(backupsDir)) fs.mkdirSync(backupsDir, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(backupsDir, `pdis_v2_backup_${ts}.json`);
  fs.writeFileSync(filePath, JSON.stringify(docs, null, 2), 'utf8');
  return filePath;
}

async function deleteAllDocs(docs) {
  const batchSize = 500;
  let batch = firestore.batch();
  let counter = 0;
  for (let i = 0; i < docs.length; i++) {
    const ref = firestore.collection(COLLECTION).doc(docs[i].id);
    batch.delete(ref);
    counter++;
    if (counter >= batchSize) {
      await batch.commit();
      console.log(`Committed delete batch of ${counter} documents...`);
      batch = firestore.batch();
      counter = 0;
    }
  }
  if (counter > 0) {
    await batch.commit();
    console.log(`Committed final delete batch of ${counter} documents.`);
  }
}

(async () => {
  try {
    console.log(`Starting backup of collection '${COLLECTION}'...`);
    const docs = await fetchAllDocs();
    console.log(`Found ${docs.length} documents in '${COLLECTION}'.`);

    if (docs.length === 0) {
      console.log('No documents to backup/delete. Exiting.');
      process.exit(0);
    }

    const backupFile = await backupToFile(docs);
    console.log('Backup written to', backupFile);

    // Confirm with user before deleting (but user requested direct). Still show summary.
    console.log('Proceeding to delete all documents from', COLLECTION);

    await deleteAllDocs(docs);
    console.log(`All documents deleted from collection '${COLLECTION}'.`);
    process.exit(0);
  } catch (err) {
    console.error('Error during backup/delete:', err && err.message ? err.message : err);
    process.exit(1);
  }
})();
