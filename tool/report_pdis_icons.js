/*
Report how many Pdis_full documents reference uploaded icons (pdis_icons/) and show examples.
Usage:
  node tool/report_pdis_icons.js --serviceAccount=tool/sa.json --limitExamples=20
*/
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

const saPath = argv.serviceAccount || argv.s || 'tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json';
const limitExamples = parseInt(argv.limitExamples || argv.l || '20', 10);

if (!fs.existsSync(saPath)) {
  console.error('Service account not found:', saPath);
  process.exit(1);
}

const sa = require(path.resolve(saPath));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const firestore = admin.firestore();

(async () => {
  try {
    console.log('Fetching all documents from Pdis_full (this will fetch ~2000 docs)...');
    const snap = await firestore.collection('Pdis_full').get();
    const total = snap.size;
    const docs = [];
    snap.forEach(d => {
      const data = d.data();
      docs.push({ id: d.id, iconPath: data.iconPath || null, name: data.name || '', lat: data.latitude || data.lat || null, lon: data.longitude || data.long || data.lng || null });
    });

    const withIcon = docs.filter(d => d.iconPath);
    const withPdisIcons = docs.filter(d => d.iconPath && d.iconPath.includes('pdis_icons'));

    console.log('Total documents in Pdis_full:', total);
    console.log('Documents with any iconPath:', withIcon.length);
    console.log('Documents with iconPath containing "pdis_icons":', withPdisIcons.length);

    console.log('\nExamples (up to', limitExamples, ') of documents using pdis_icons:');
    withPdisIcons.slice(0, limitExamples).forEach((d, i) => {
      console.log(`${i+1}. id=${d.id} name=${d.name} lat=${d.lat} lon=${d.lon}`);
      console.log('   iconPath=', d.iconPath);
    });

    if (withPdisIcons.length === 0) console.log('\nNo documents reference pdis_icons/ — maybe iconPath is null or points to remote URLs.');

    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(2);
  }
})();
