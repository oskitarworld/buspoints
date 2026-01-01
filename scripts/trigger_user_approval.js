const admin = require('firebase-admin');

async function main() {
  try {
    const uid = process.argv[2];
    if (!uid) {
      console.error('Usage: node trigger_user_approval.js <uid>');
      process.exit(2);
    }
    const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'buspoint-49ea0';
    admin.initializeApp({ projectId: project });
    const db = admin.firestore();
    const ref = db.collection('users').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
      console.error('User doc not found:', uid);
      process.exit(3);
    }
    console.log('Current user data:', snap.data());
    console.log('Setting status -> pending');
    await ref.update({ status: 'pending' });
    // small delay to ensure onUpdate triggers differ
    await new Promise(r => setTimeout(r, 1500));
    console.log('Setting status -> approved');
    await ref.update({ status: 'approved' });
    // wait a bit for functions to run
    await new Promise(r => setTimeout(r, 4000));
    const after = await ref.get();
    console.log('After update, user data:', after.data());
    process.exit(0);
  } catch (e) {
    console.error('Error:', e && e.stack ? e.stack : e);
    process.exit(1);
  }
}

main();
