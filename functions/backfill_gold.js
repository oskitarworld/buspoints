// One-off backfill script: scan all pdis_v2 documents and set/remove
// 'lista_gold' in `specialCategories` according to the rule:
// >= 3 approved reviews AND average >= 4.0 -> include 'lista_gold'
// Usage: node backfill_gold.js --serviceAccount ../path/to/serviceAccount.json

const admin = require('firebase-admin');
const argv = require('minimist')(process.argv.slice(2));

async function main() {
  const keyPath = argv.serviceAccount || argv.sa;
  if (!keyPath) {
    console.error('Usage: node backfill_gold.js --serviceAccount path/to/serviceAccount.json');
    process.exit(2);
  }

  admin.initializeApp({
    credential: admin.credential.cert(require(keyPath)),
  });

  const db = admin.firestore();
  console.log('Starting backfill: scanning pdis_v2...');

  const pdisSnap = await db.collection('pdis_v2').get();
  console.log(`Found ${pdisSnap.size} pdis_v2 docs`);

  let processed = 0;
  for (const doc of pdisSnap.docs) {
    const pdiId = doc.id;
    try {
      const reviewsSnap = await db.collection('pdis_v2').doc(pdiId).collection('reviews').where('status', '==', 'approved').get();
      const count = reviewsSnap.size;
      let avg = 0;
      if (count > 0) {
        let sum = 0;
        reviewsSnap.docs.forEach(d => { sum += Number((d.data() || {}).rating) || 0; });
        avg = sum / count;
      }

      const shouldBeGold = count >= 3 && avg >= 4.0;

      if (shouldBeGold) {
        await db.collection('pdis_v2').doc(pdiId).update({ specialCategories: admin.firestore.FieldValue.arrayUnion('lista_gold') });
        console.log(`pdi ${pdiId} -> ADD lista_gold (count=${count}, avg=${avg.toFixed(2)})`);
      } else {
        await db.collection('pdis_v2').doc(pdiId).update({ specialCategories: admin.firestore.FieldValue.arrayRemove('lista_gold') });
        console.log(`pdi ${pdiId} -> REMOVE lista_gold (count=${count}, avg=${avg.toFixed(2)})`);
      }
    } catch (err) {
      console.error('Error processing pdi', pdiId, err);
    }
    processed++;
  }
  console.log('Backfill complete. Processed:', processed);
}

main().catch(err => {
  console.error('Backfill failed:', err);
  process.exit(1);
});
