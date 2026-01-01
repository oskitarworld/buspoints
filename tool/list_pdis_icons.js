/*
List files under a storage prefix and produce signed URLs (long expiry) for selection.
Usage:
  node tool/list_pdis_icons.js --serviceAccount=tool/sa.json --bucket=buspoint-49ea0.firebasestorage.app --prefix=pdis_icons/ --limit=20
*/
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

const saPath = argv.serviceAccount || argv.s || 'tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json';
const bucketName = argv.bucket || 'buspoint-49ea0.firebasestorage.app';
const prefix = argv.prefix || 'pdis_icons/';
const limit = parseInt(argv.limit || '20', 10);

if (!fs.existsSync(saPath)) { console.error('Service account not found:', saPath); process.exit(1); }
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(saPath))) });
const storage = admin.storage().bucket(bucketName);

(async () => {
  try {
    const [files] = await storage.getFiles({ prefix });
    console.log('Found', files.length, 'files under', prefix);
    const sample = files.slice(0, limit);
    for (let i=0;i<sample.length;i++) {
      const f = sample[i];
      let url = '';
      try {
        const [signed] = await f.getSignedUrl({ action: 'read', expires: new Date('2035-03-01') });
        url = signed;
      } catch (e) {
        url = 'gs://' + bucketName + '/' + f.name;
      }
      console.log(`${i+1}. ${f.name} -> ${url}`);
    }
    process.exit(0);
  } catch (e) { console.error('Error listing files:', e); process.exit(2); }
})();
