const admin = require('firebase-admin');

async function main() {
  try {
    const email = process.argv[2];
    if (!email) {
      console.error('Usage: node trigger_user_by_email.js <email>');
      process.exit(2);
    }
    const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'buspoint-49ea0';
    admin.initializeApp({ projectId: project });
    const db = admin.firestore();

    const q = await db.collection('users').where('email','==',email).limit(1).get();
    if (q.empty) {
      console.error('No user found with email:', email);
      process.exit(3);
    }
    const doc = q.docs[0];
    const uid = doc.id;
    console.log('Found user', uid, doc.data());

    console.log('Setting status -> pending');
    await doc.ref.update({ status: 'pending' });
    await new Promise(r => setTimeout(r, 1500));
    console.log('Setting status -> approved');
    await doc.ref.update({ status: 'approved' });
    await new Promise(r => setTimeout(r, 4000));
    const after = await doc.ref.get();
    console.log('After update, user data:', after.data());
    process.exit(0);
  } catch (e) {
    console.error('Error:', e && e.stack ? e.stack : e);
    process.exit(1);
  }
}

main();
