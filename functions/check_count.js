const admin = require('firebase-admin');

try {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
} catch (e) {
  console.error('Failed to initialize firebase-admin. Make sure GOOGLE_APPLICATION_CREDENTIALS is set and points to a valid service account JSON.');
  console.error(e && e.message ? e.message : e);
  process.exit(1);
}

const db = admin.firestore();

(async () => {
  try {
    const snap = await db.collection('pdis').get();
    console.log('pdis count =', snap.size);
    if (snap.size > 0) {
      const doc = snap.docs[0];
      console.log('first doc id:', doc.id);
      console.log('first doc data (preview):', JSON.stringify(doc.data(), null, 2));
    }
    process.exit(0);
  } catch (err) {
    console.error('Error reading pdis collection:', err && err.message ? err.message : err);
    process.exit(1);
  }
})();
