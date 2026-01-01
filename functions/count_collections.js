const admin = require('firebase-admin');

try {
  admin.initializeApp({ credential: admin.credential.applicationDefault() });
} catch (e) {
  console.error('Failed to init firebase-admin:', e && e.message ? e.message : e);
  process.exit(1);
}

const db = admin.firestore();

async function count(name, queryFunc) {
  try {
    const snap = queryFunc ? await queryFunc() : await db.collection(name).get();
    console.log(`${name} count = ${snap.size}`);
  } catch (e) {
    console.error(`Error counting ${name}:`, e && e.message ? e.message : e);
  }
}

(async () => {
  await count('pdis', null);
  await count('pdis_v2', null);
  await count('pois', null);
  await count('Pdis_full', null);
  // user_pois approved
  await count('user_pois (approved)', () => db.collection('user_pois').where('status', '==', 'approved').get());
  // total users' mirror reviews
  try {
    const users = await db.collection('users').get();
    let totalUserReviews = 0;
    for (const u of users.docs) {
      const rev = await db.collection('users').doc(u.id).collection('reviews').where('status', '==', 'approved').get();
      totalUserReviews += rev.size;
    }
    console.log('approved reviews under users/*/reviews =', totalUserReviews);
  } catch (e) {
    console.error('Error counting user reviews:', e && e.message ? e.message : e);
  }
  process.exit(0);
})();
