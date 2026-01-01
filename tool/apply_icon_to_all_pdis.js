/*
Set the same iconPath for all documents in Pdis_full.
Usage:
  node tool/apply_icon_to_all_pdis.js --serviceAccount=tool/sa.json --storagePath=pdis_icons/icon-36.png
Or pass --iconUrl to use an explicit URL instead of signed URL.

What it does:
- gets a signed URL for the storage path (if provided)
- backs up all documents in Pdis_full to tool/backups/pdis_full_backup_<ts>.json
- updates all docs in Pdis_full setting { iconPath: <signedUrl> }
*/

const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));
const admin = require('firebase-admin');

const saPath = argv.serviceAccount || argv.s || 'tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json';
const storagePath = argv.storagePath; // e.g. pdis_icons/icon-36.png
const iconUrl = argv.iconUrl; // if provided, use directly
const bucketName = argv.bucket || 'buspoint-49ea0.firebasestorage.app';
const dryRun = (argv.dryRun === undefined) ? false : (String(argv.dryRun) !== 'false');

if (!fs.existsSync(saPath)) { console.error('Service account not found:', saPath); process.exit(1); }
if (!storagePath && !iconUrl) { console.error('Provide --storagePath or --iconUrl'); process.exit(1); }

admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(saPath))) });
const firestore = admin.firestore();
const storage = admin.storage().bucket(bucketName);

async function getSignedUrlFor(pathInBucket) {
  try {
    const file = storage.file(pathInBucket);
    const expires = new Date('2035-03-01');
    const [url] = await file.getSignedUrl({ action: 'read', expires });
    return url;
  } catch (e) {
    console.error('Failed to get signed url for', pathInBucket, e.message || e);
    return null;
  }
}

(async () => {
  try {
    let finalUrl = iconUrl;
    if (!finalUrl) {
      console.log('Getting signed URL for', storagePath);
      finalUrl = await getSignedUrlFor(storagePath);
      if (!finalUrl) throw new Error('Could not obtain signed URL for ' + storagePath);
    }
    console.log('Icon URL to apply:', finalUrl.substring(0,120) + '...');

    // fetch all docs
    console.log('Fetching all documents from Pdis_full...');
    const snap = await firestore.collection('Pdis_full').get();
    const docs = [];
    snap.forEach(d => { docs.push({ id: d.id, data: d.data() }); });
    console.log('Documents fetched:', docs.length);

    // backup
    const backupDir = path.join('tool','backups'); if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir,{recursive:true});
    const ts = new Date().toISOString().replace(/[:.]/g,'-');
    const backupPath = path.join(backupDir, `pdis_full_backup_${ts}.json`);
    const backupObj = {};
    for (const d of docs) backupObj[d.id] = d.data;
    fs.writeFileSync(backupPath, JSON.stringify(backupObj, null, 2), 'utf8');
    console.log('Backup written to', backupPath);

    if (dryRun) { console.log('Dry run, no updates applied.'); process.exit(0); }

    // apply updates in batches
    const BATCH = 400;
    for (let i=0;i<docs.length;i+=BATCH) {
      const batch = firestore.batch();
      const chunk = docs.slice(i, i+BATCH);
      for (const d of chunk) {
        const ref = firestore.collection('Pdis_full').doc(d.id);
        batch.update(ref, { iconPath: finalUrl });
      }
      await batch.commit();
      console.log('Committed batch', Math.floor(i/BATCH)+1, 'size', chunk.length);
    }

    console.log('All documents updated. Backup at', backupPath);
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(2);
  }
})();
