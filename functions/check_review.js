/*
 Quick local helper: check whether a review with a given pdiId exists and where
 it is stored (collection group 'reviews' or 'review' or under pdis_v2/<id>/reviews).
 Usage:
   node ./functions/check_review.js /path/to/serviceAccountKey.json "Escardivol_carga_y_descarga"

 It will print matching documents and their full paths.
*/

const admin = require('firebase-admin');
const path = require('path');

async function main() {
  const keyPath = process.argv[2];
  const pdiId = process.argv[3];
  if (!keyPath || !pdiId) {
    console.error('Usage: node check_review.js /path/to/key.json <pdiId>');
    process.exit(2);
  }

  const keyAbs = path.resolve(keyPath);
  try {
    admin.initializeApp({
      credential: admin.credential.cert(require(keyAbs)),
    });
  } catch (e) {
    console.error('Failed to init admin SDK:', e);
    process.exit(2);
  }

  const db = admin.firestore();

  console.log('Searching for reviews with pdiId=', pdiId);

  try {
    const q1 = db.collectionGroup('reviews').where('pdiId', '==', pdiId);
    const snap1 = await q1.get();
    console.log(`collectionGroup('reviews') matches: ${snap1.size}`);
    snap1.forEach(doc => {
      console.log(' -', doc.ref.path, JSON.stringify(doc.data()));
    });
  } catch (e) {
    console.error('Error querying collectionGroup("reviews")', e);
  }

  try {
    const q2 = db.collectionGroup('review').where('pdiId', '==', pdiId);
    const snap2 = await q2.get();
    console.log(`collectionGroup('review') matches: ${snap2.size}`);
    snap2.forEach(doc => {
      console.log(' -', doc.ref.path, JSON.stringify(doc.data()));
    });
  } catch (e) {
    console.error('Error querying collectionGroup("review")', e);
  }

  try {
    const docRef = db.collection('pdis_v2').doc(pdiId);
    const sub = await docRef.collection('reviews').get();
    console.log(`pdis_v2/${pdiId}/reviews matches: ${sub.size}`);
    sub.forEach(doc => console.log(' -', doc.ref.path, JSON.stringify(doc.data())));
  } catch (e) {
    console.error('Error querying pdis_v2/<id>/reviews', e);
  }

  process.exit(0);
}

main();
