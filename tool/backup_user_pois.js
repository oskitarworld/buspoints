// Backup and delete script for `user_pois` collection
// Usage: node tool/backup_user_pois.js

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

// Path to the service account JSON included in the repo (tool/)
const SERVICE_ACCOUNT_PATH = path.resolve(__dirname, 'buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json');
const OUTPUT_PATH = path.resolve(__dirname, 'user_pois_backup.json');
const COLLECTION = 'user_pois';

async function main() {
  if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
    console.error('Service account JSON not found at', SERVICE_ACCOUNT_PATH);
    process.exit(1);
  }

  const serviceAccount = require(SERVICE_ACCOUNT_PATH);

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });

  const db = admin.firestore();

  console.log(`Backing up all documents from collection: ${COLLECTION}`);

  // Read all documents (paginated if needed)
  const allDocs = [];
  let snapshot = await db.collection(COLLECTION).get();
  snapshot.forEach(doc => {
    allDocs.push({ id: doc.id, data: doc.data() });
  });

  console.log(`Found ${allDocs.length} documents in ${COLLECTION}.`);

  // Write full backup to JSON
  fs.writeFileSync(OUTPUT_PATH, JSON.stringify(allDocs, null, 2), 'utf8');
  console.log(`Wrote backup to ${OUTPUT_PATH}`);

  // Show up to 3 example documents
  console.log('Example documents (up to 3):');
  allDocs.slice(0, 3).forEach((d, i) => {
    console.log(`--- doc ${i+1} id=${d.id}`);
    console.log(JSON.stringify(d.data, null, 2));
  });

  // Confirm and proceed to delete
  console.log('Proceeding to delete documents from collection:', COLLECTION);

  // Delete in batches of 500
  let deletedCount = 0;
  while (true) {
    const batch = db.batch();
    const querySnapshot = await db.collection(COLLECTION).limit(500).get();
    if (querySnapshot.empty) break;

    querySnapshot.docs.forEach(d => batch.delete(d.ref));
    await batch.commit();
    deletedCount += querySnapshot.docs.length;
    console.log(`Deleted batch of ${querySnapshot.docs.length}. Total deleted: ${deletedCount}`);
  }

  console.log(`Finished deletion. Total deleted: ${deletedCount}`);
  process.exit(0);
}

main().catch(err => {
  console.error('Error during backup/delete:', err);
  process.exit(2);
});
