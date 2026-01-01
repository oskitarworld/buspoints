const admin = require('firebase-admin');
const fs = require('fs');

function usage() {
  console.log('Usage: node migrate_reviews_from_users.js [--key /path/to/key.json] [--restore-pdisv2]');
  process.exit(1);
}

const args = process.argv.slice(2);
let keyPath = null;
let restorePdisV2 = false;
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--key') { keyPath = args[i+1]; i++; }
  else if (args[i] === '--restore-pdisv2') { restorePdisV2 = true; }
  else usage();
}

try {
  if (keyPath) {
    if (!fs.existsSync(keyPath)) {
      console.error('Service account not found at', keyPath);
      process.exit(1);
    }
    admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  } else {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }
} catch (e) {
  console.error('Failed to initialize admin:', e && e.message ? e.message : e);
  process.exit(1);
}

const db = admin.firestore();

async function migrate() {
  console.log('Scanning users collection for reviews...');
  const usersSnap = await db.collection('users').get();
  let total = 0;
  for (const userDoc of usersSnap.docs) {
    const uid = userDoc.id;
    const reviewsRef = db.collection('users').doc(uid).collection('reviews');
    const revSnap = await reviewsRef.get();
    if (revSnap.empty) continue;
    for (const r of revSnap.docs) {
      const data = r.data();
      // Build canonical review doc
      const reviewDoc = {
        comment: data.comment || null,
        rating: data.rating || null,
        userId: data.userId || uid,
        status: data.status || 'pending',
        createdAt: data.createdAt || admin.firestore.FieldValue.serverTimestamp(),
        pdiId: data.pdiId || null,
        pdiName: data.pdiName || null,
        pdiCategory: data.pdiCategory || null,
        source: 'users_mirror',
      };

      // Write to root-level 'reviews' collection with same id
      try {
        await db.collection('reviews').doc(r.id).set(reviewDoc, { merge: true });
        total++;
      } catch (e) {
        console.error('Failed to write review', r.id, e && e.message ? e.message : e);
      }

      // Optionally restore under pdis_v2/<pdiId>/reviews
      if (restorePdisV2 && reviewDoc.pdiId) {
        try {
          await db.collection('pdis_v2').doc(reviewDoc.pdiId).collection('reviews').doc(r.id).set(reviewDoc, { merge: true });
        } catch (e) {
          console.error('Failed to restore review to pdis_v2 for', reviewDoc.pdiId, e && e.message ? e.message : e);
        }
      }
    }
  }
  console.log(`Migration complete. Reviews migrated: ${total}`);
}

migrate().catch(err => { console.error('Migration failed:', err && err.message ? err.message : err); process.exit(1); });
