/*
Script: upload_icons_folder.js
- Uploads all image files from a local folder to a Firebase Storage bucket
- Generates signed read URLs and updates Firestore collections Pdis_full and user_pois

Usage:
  node tool/upload_icons_folder.js --serviceAccount=tool/sa.json --folder=assets/pdifull_icon --bucket=buspoint-49ea0.appspot.com --prefix=pdis_icons/ [--apply]

By default runs in dry-run mode; pass --apply to perform uploads and Firestore updates.
*/

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

const serviceAccountPath = argv.serviceAccount || argv.s;
const folder = argv.folder || argv.f;
const bucketName = argv.bucket;
const prefix = argv.prefix || 'pdis_icons/';
const apply = argv.apply || false;

if (!serviceAccountPath || !folder || !bucketName) {
  console.log('Usage: node tool/upload_icons_folder.js --serviceAccount=tool/sa.json --folder=assets/pdifull_icon --bucket=buspoint-49ea0.appspot.com --prefix=pdis_icons/ [--apply]');
  process.exit(1);
}
if (!fs.existsSync(serviceAccountPath)) { console.error('Service account not found:', serviceAccountPath); process.exit(2); }
if (!fs.existsSync(folder)) { console.error('Folder not found:', folder); process.exit(2); }

const sa = require(path.resolve(serviceAccountPath));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const bucket = admin.storage().bucket(bucketName);
const firestore = admin.firestore();

const allowedExt = ['.png', '.jpg', '.jpeg', '.svg', '.webp'];

(async () => {
  try {
    // check bucket exists
    try {
      const [exists] = await bucket.exists();
      if (!exists) {
        console.error('Bucket does not exist or not accessible:', bucketName);
        process.exit(2);
      }
    } catch (err) {
      console.error('Error checking bucket:', err.message || err);
      process.exit(2);
    }

    const files = fs.readdirSync(folder).filter(f => allowedExt.includes(path.extname(f).toLowerCase()));
    if (files.length === 0) {
      console.log('No image files found in folder:', folder);
      process.exit(0);
    }
    console.log('Found image files:', files.length);

    const uploaded = [];
    for (const filename of files) {
      const localPath = path.join(folder, filename);
      const dest = `${prefix}${filename}`;
      console.log((apply? 'Uploading':'Would upload'), filename, '->', dest);
      if (apply) {
        await bucket.upload(localPath, { destination: dest, resumable: false, validation: false });
        const file = bucket.file(dest);
        const [url] = await file.getSignedUrl({ action: 'read', expires: '2035-03-01' });
        uploaded.push({ filename, dest, url });
      } else {
        uploaded.push({ filename, dest, url: `DRYRUN://storage/${bucketName}/${dest}` });
      }
    }

    console.log('Uploaded summary (sample):', uploaded.slice(0, 10));
    if (uploaded.length === 0) { console.log('No uploads done. Exiting.'); process.exit(0); }

    const defaultIcon = uploaded[0].url;
    console.log('Default icon URL (used for docs without match):', defaultIcon);

    // Update Firestore: for each doc in Pdis_full and user_pois missing iconPath, try to match by filename inside some fields, else use default
    const collections = ['Pdis_full', 'user_pois'];
    for (const col of collections) {
      console.log('Scanning collection', col);
      const snap = await firestore.collection(col).get();
      console.log(' - found', snap.size, 'documents');
      let updated = 0;
      for (const doc of snap.docs) {
        const data = doc.data();
        if (data.iconPath) continue; // skip existing

        // heuristic: look for any string field that contains a known filename
        let matchedUrl = null;
        const text = JSON.stringify(data).toLowerCase();
        for (const up of uploaded) {
          if (text.includes(up.filename.toLowerCase())) {
            matchedUrl = up.url;
            break;
          }
        }
        if (!matchedUrl) matchedUrl = defaultIcon;
        console.log(`[${col}] would update ${doc.ref.path} -> iconPath=${matchedUrl}`);
        if (apply) {
          await doc.ref.update({ iconPath: matchedUrl });
          updated++;
        }
      }
      console.log(` - Collection ${col}: updated ${updated} documents`);
    }

    console.log('\nDone.');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(3);
  }
})();
