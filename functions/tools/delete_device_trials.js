/*
Node helper to delete documents from `device_trials` collection.

Usage (from repository root):

# Install deps (if necessary)
cd functions
npm install

# Delete ALL documents in device_trials (use with extreme caution!)
node tools/delete_device_trials.js --all

# Delete by deviceIdHash
node tools/delete_device_trials.js --deviceId <deviceHash>

# Delete by userId
node tools/delete_device_trials.js --userId <uid>

# Delete documents with firstUsedAt before a date (ISO format)
node tools/delete_device_trials.js --before 2025-12-01T00:00:00Z

Notes:
- The script uses the Firebase Admin SDK. Ensure you have set GOOGLE_APPLICATION_CREDENTIALS
  to a service account JSON with proper permissions, or run this inside an environment already
  authenticated with gcloud that has access to the project.
- For quick local testing prefer using the Firebase Emulator Suite and point the Admin SDK
  at the emulator by setting FIRESTORE_EMULATOR_HOST=localhost:8080 and initializing admin with
  projectId matching your emulator config.
*/

const admin = require('firebase-admin');
const { program } = require('commander');

program
  .option('--all', 'Delete all documents in device_trials')
  .option('--deviceId <id>', 'Delete a specific device trial by deviceIdHash')
  .option('--userId <uid>', 'Delete device_trials documents for a specific userId')
  .option('--before <iso>', 'Delete documents with firstUsedAt before the given ISO date')
  .option('--project <projectId>', 'Optional: set project id to initialize (overrides env)')
  .parse(process.argv);

const opts = program.opts();

if (!opts.all && !opts.deviceId && !opts.userId && !opts.before) {
  console.error('One of --all, --deviceId, --userId or --before must be provided');
  process.exit(1);
}

// Initialize admin SDK
if (!admin.apps.length) {
  // If user provided --project, set it
  if (opts.project) process.env.GCLOUD_PROJECT = opts.project;
  admin.initializeApp();
}

const db = admin.firestore();

async function deleteBatch(query) {
  const snapshot = await query.get();
  if (snapshot.empty) return 0;
  const batchSize = snapshot.size;
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return batchSize;
}

async function run() {
  console.log('Starting device_trials cleanup with options:', opts);
  try {
    if (opts.all) {
      // WARNING: delete whole collection
      console.log('Deleting all documents under device_trials (this may be slow)');
      let total = 0;
      while (true) {
        const q = db.collection('device_trials').limit(500);
        const deleted = await deleteBatch(q);
        total += deleted;
        console.log(`Deleted batch of ${deleted} (total ${total})`);
        if (deleted < 500) break;
      }
      console.log(`Finished deleting ${total} documents from device_trials`);
      return;
    }

    if (opts.deviceId) {
      const docRef = db.collection('device_trials').doc(opts.deviceId);
      const snap = await docRef.get();
      if (!snap.exists) {
        console.log('No document found for deviceId:', opts.deviceId);
        return;
      }
      await docRef.delete();
      console.log('Deleted document device_trials/' + opts.deviceId);
      return;
    }

    if (opts.userId) {
      console.log('Deleting device_trials for userId:', opts.userId);
      let total = 0;
      while (true) {
        const q = db.collection('device_trials').where('userId', '==', opts.userId).limit(500);
        const deleted = await deleteBatch(q);
        total += deleted;
        console.log(`Deleted batch of ${deleted} (total ${total})`);
        if (deleted < 500) break;
      }
      console.log(`Finished deleting ${total} documents for userId ${opts.userId}`);
      return;
    }

    if (opts.before) {
      const beforeDate = new Date(opts.before);
      if (isNaN(beforeDate.getTime())) {
        console.error('Invalid --before date format. Use ISO date, e.g. 2025-12-01T00:00:00Z');
        process.exit(1);
      }
      console.log('Deleting device_trials with firstUsedAt before:', beforeDate.toISOString());
      let total = 0;
      while (true) {
        const q = db.collection('device_trials').where('firstUsedAt', '<', admin.firestore.Timestamp.fromDate(beforeDate)).limit(500);
        const deleted = await deleteBatch(q);
        total += deleted;
        console.log(`Deleted batch of ${deleted} (total ${total})`);
        if (deleted < 500) break;
      }
      console.log(`Finished deleting ${total} documents older than ${beforeDate.toISOString()}`);
      return;
    }
  } catch (err) {
    console.error('Error during deletion:', err);
    process.exit(2);
  }
}

run();
