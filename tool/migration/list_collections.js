/**
 * list_collections.js
 *
 * Lists counts for candidate collections so you can verify where POIs live.
 * Usage:
 *   node list_collections.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

async function main() {
  const serviceAccount = argv.serviceAccount;
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
  const candidates = ['pdis', 'pdis_v2', 'pois', 'places', 'points', 'user_pois', 'users'];

  for (const c of candidates) {
    try {
      const snap = await db.collection(c).limit(1).get();
      if (snap.empty) {
        console.log(`${c}: 0 (or collection missing / no read permission)`);
      } else {
        // If we can read at least one doc, get an approximate count via a small query.
        const countSnap = await db.collection(c).limit(1000).get();
        console.log(`${c}: ${countSnap.size} (sampled up to 1000)`);
      }
    } catch (err) {
      console.log(`${c}: error reading (${err.message})`);
    }
  }

  process.exit(0);
}

main().catch(err => { console.error(err); process.exit(1); });
