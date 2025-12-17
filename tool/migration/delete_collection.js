/**
 * delete_collection.js
 *
 * Deletes documents from a collection in small batches using Firebase Admin SDK.
 * Use with caution. The script requires a service account JSON or ADC.
 *
 * Usage:
 *  node delete_collection.js --serviceAccount ../tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --collection pdis --batchSize 500 --dryRun
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

async function main() {
  const serviceAccount = argv.serviceAccount;
  const collection = argv.collection || 'pdis';
  const batchSize = parseInt(argv.batchSize || '500', 10);
  const dryRun = !!argv.dryRun;

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

  console.log(`Deleting documents from collection: ${collection} (batchSize=${batchSize})`);
  let totalDeleted = 0;

  while (true) {
    const snapshot = await db.collection(collection).limit(batchSize).get();
    if (snapshot.empty) break;

    console.log(`Found ${snapshot.size} documents to delete (sample id: ${snapshot.docs[0].id})`);
    if (dryRun) {
      // just show ids and exit
      snapshot.docs.forEach(d => console.log('[DRYRUN] would delete', d.id));
      totalDeleted += snapshot.size;
      break;
    }

    const batch = db.batch();
    snapshot.docs.forEach(d => batch.delete(d.ref));
    await batch.commit();
    totalDeleted += snapshot.size;
    console.log(`Deleted ${totalDeleted} documents so far...`);
    // small delay to avoid hitting Firestore quota aggressively
    await new Promise(r => setTimeout(r, 200));
  }

  console.log('Done. Total deleted:', totalDeleted);
}

main().catch(err => { console.error(err); process.exit(1); });
