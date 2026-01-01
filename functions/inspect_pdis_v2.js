const admin = require('firebase-admin');
const fs = require('fs');

function usage() {
  console.error('Usage: node inspect_pdis_v2.js --key /path/to/serviceAccount.json [--limit N]');
  process.exit(2);
}

const argv = process.argv.slice(2);
let keyPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
let limit = 5;
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--key') {
    keyPath = argv[i+1];
    i++;
  } else if (argv[i] === '--limit') {
    limit = parseInt(argv[i+1], 10);
    i++;
  }
}
if (!keyPath) usage();

if (!fs.existsSync(keyPath)) {
  console.error('Service account key not found at', keyPath);
  process.exit(2);
}

admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
const db = admin.firestore();

(async () => {
  try {
    console.log('Reading up to', limit, 'docs from pdis_v2...');
    const snapshot = await db.collection('pdis_v2').limit(limit).get();
    console.log('Total docs returned by query:', snapshot.size);
    let i = 0;
    for (const doc of snapshot.docs) {
      i++;
      console.log('--- DOC', i, 'id=', doc.id);
      const data = doc.data();
      console.log(JSON.stringify(data, null, 2));
      console.log('Field keys:', Object.keys(data));
    }

    // Also print total count (may be slower if collection large) using aggregation query if available
    try {
      // If count() aggregation supported in the environment, use it
      const countSnap = await db.collection('pdis_v2').count().get();
      console.log('Estimated count via aggregation:', countSnap.data().count);
    } catch (e) {
      console.log('Count aggregation not available or failed:', e.message || e);
    }

    process.exit(0);
  } catch (e) {
    console.error('Error reading pdis_v2:', e);
    process.exit(2);
  }
})();
