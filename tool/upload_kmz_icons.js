/*
Script: upload_kmz_icons.js
- Extracts image files from assets/pdifull_icon/buspointfull.KMZ
- Uploads them to Firebase Storage (bucket from service account project)
- Generates signed read URLs (long expiration)
- Updates Firestore documents in Pdis_full and user_pois to set iconPath (if not present)

Usage:
  node upload_kmz_icons.js --serviceAccount=tool/buspoint-XXX.json --kmz=assets/pdifull_icon/buspointfull.KMZ --prefix=pdis_icons/ --apply

By default it runs in dry-run mode unless --apply is passed.
*/

const AdmZip = require('adm-zip');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function usageAndExit() {
  console.log('Usage: node upload_kmz_icons.js --serviceAccount=tool/sa.json --kmz=assets/pdifull_icon/buspointfull.KMZ [--prefix=pdis_icons/] [--apply]');
  process.exit(1);
}

const argv = require('minimist')(process.argv.slice(2));
const serviceAccountPath = argv.serviceAccount || argv.s;
const kmzPath = argv.kmz || argv.k;
const prefix = argv.prefix || 'pdis_icons/';
const apply = argv.apply || false;

if (!serviceAccountPath || !kmzPath) usageAndExit();
if (!fs.existsSync(serviceAccountPath)) { console.error('Service account not found:', serviceAccountPath); process.exit(2); }
if (!fs.existsSync(kmzPath)) { console.error('KMZ file not found:', kmzPath); process.exit(2); }

const sa = require(path.resolve(serviceAccountPath));
const projectId = sa.project_id;
if (!projectId) { console.error('Could not read project_id from service account'); process.exit(2); }

admin.initializeApp({
  credential: admin.credential.cert(sa),
});

const bucketArg = argv.bucket || argv.b;
const defaultBucketName = `${projectId}.appspot.com`;
const bucketName = bucketArg || defaultBucketName;
const bucket = admin.storage().bucket(bucketName);

// check bucket existence early and list alternatives if missing
async function ensureBucketExistsOrList() {
  try {
    const [exists] = await bucket.exists();
    if (!exists) {
      console.error(`Bucket '${bucketName}' does not exist or is not accessible with these credentials.`);
      console.log('Attempting to list available buckets for the project...');
      try {
        const [buckets] = await admin.storage().getBuckets();
        if (!buckets || buckets.length === 0) {
          console.log('No buckets found or insufficient permissions to list buckets.');
        } else {
          console.log('Available buckets:');
          for (const b of buckets) console.log(' -', b.name);
        }
      } catch (err) {
        console.error('Could not list buckets:', err.message || err);
      }
      process.exit(4);
    }
  } catch (err) {
    console.error('Error checking bucket existence:', err.message || err);
    process.exit(4);
  }
}
const firestore = admin.firestore();

(async () => {
  try {
    console.log('Extracting KMZ:', kmzPath);
    const zip = new AdmZip(kmzPath);
    const entries = zip.getEntries();
    const images = entries.filter(e => {
      const ext = path.extname(e.entryName).toLowerCase();
      return ['.png', '.jpg', '.jpeg', '.svg', '.webp'].includes(ext);
    });

    const uploaded = [];

  // verify bucket exists before attempting uploads
  await ensureBucketExistsOrList();

    // helper: upload a local tmp file path to storage
    async function uploadTmp(tmpPath, filename) {
      const dest = `${prefix}${filename}`;
      console.log('Uploading', filename, '->', dest);
      if (apply) {
        await bucket.upload(tmpPath, { destination: dest, resumable: false, validation: false });
        const file = bucket.file(dest);
        const [url] = await file.getSignedUrl({ action: 'read', expires: '2035-03-01' });
        return { filename, dest, url };
      } else {
        return { filename, dest, url: `DRYRUN://storage/${projectId}/${dest}` };
      }
    }

    // If we have embedded images inside the KMZ, upload them first
    if (images.length > 0) {
      console.log('Found images inside KMZ:', images.map(e => e.entryName));
      for (const entry of images) {
        const filename = path.basename(entry.entryName);
        const tmpPath = path.join('/tmp', `kmz_${Date.now()}_${filename}`);
        fs.writeFileSync(tmpPath, entry.getData());
        try {
          const res = await uploadTmp(tmpPath, filename);
          uploaded.push(res);
        } finally {
          try { fs.unlinkSync(tmpPath); } catch (e) {}
        }
      }
    } else {
      // No embedded images: try to parse any KML (doc.kml) and extract <href> entries
      const kmlEntry = entries.find(e => e.entryName.toLowerCase().endsWith('.kml') || /doc\.kml$/i.test(e.entryName));
      if (!kmlEntry) {
        console.log('No image files found inside KMZ and no KML file present. Exiting.');
        process.exit(0);
      }
      const kmlText = kmlEntry.getData().toString('utf8');
      // crude regex to extract <href>...</href> values
      const hrefs = [];
      const hrefRegex = /<href>([\s\S]*?)<\/href>/gi;
      let m;
      while ((m = hrefRegex.exec(kmlText))) {
        if (m[1]) {
          hrefs.push(m[1].trim());
        }
      }
      const normalizeHref = (h) => {
        if (!h) return '';
        // strip CDATA wrappers and whitespace/newlines
        return h.replace(/^<!\[CDATA\[/i, '').replace(/\]\]>$/i, '').replace(/[\r\n\t]/g, '').trim();
      };
      const uniqueHrefs = Array.from(new Set(hrefs.map(normalizeHref))).filter(Boolean);
      if (uniqueHrefs.length === 0) {
        console.log('No <href> entries found inside KML after normalization. Exiting.');
        process.exit(0);
      }
      console.log('Found hrefs in KML (normalized):', uniqueHrefs);

      // helper: download a remote URL or handle data: URI into a tmp file
      const http = require('http');
      const https = require('https');

      async function downloadToTmp(url) {
        if (!url) return null;
        // data URI
        if (url.startsWith('data:')) {
          const match = url.match(/^data:(image\/[^;]+);base64,(.*)$/i);
          if (!match) return null;
          const mime = match[1];
          const b64 = match[2];
          const ext = mime.split('/')[1].split('+')[0] || 'png';
          const filename = `kmz_datauri_${Date.now()}.${ext}`;
          const tmpPath = path.join('/tmp', filename);
          fs.writeFileSync(tmpPath, Buffer.from(b64, 'base64'));
          return { tmpPath, filename };
        }

        // remote http(s)
        if (/^https?:\/\//i.test(url)) {
          return new Promise((resolve, reject) => {
            try {
              const client = url.startsWith('https://') ? https : http;
              client.get(url, (res) => {
                if (res.statusCode && res.statusCode >= 400) return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
                const contentType = res.headers['content-type'] || '';
                const ext = (() => {
                  const m = /image\/(png|jpe?g|svg|webp)/i.exec(contentType);
                  if (m) return m[1].replace('jpeg','jpg');
                  const parsed = path.parse(url);
                  return (parsed.ext && parsed.ext.substring(1)) || 'png';
                })();
                const filename = `kmz_remote_${Date.now()}.${ext}`;
                const tmpPath = path.join('/tmp', filename);
                const fileStream = fs.createWriteStream(tmpPath);
                res.pipe(fileStream);
                fileStream.on('finish', () => {
                  fileStream.close(() => resolve({ tmpPath, filename }));
                });
                fileStream.on('error', (err) => reject(err));
              }).on('error', (err) => reject(err));
            } catch (err) { reject(err); }
          });
        }

        // otherwise treat as relative path inside KMZ (not found earlier)
        const relEntry = entries.find(e => e.entryName === url || e.entryName.endsWith('/' + url));
        if (relEntry) {
          const filename = path.basename(relEntry.entryName);
          const tmpPath = path.join('/tmp', `kmz_${Date.now()}_${filename}`);
          fs.writeFileSync(tmpPath, relEntry.getData());
          return { tmpPath, filename };
        }
        return null;
      }

      for (const href of uniqueHrefs) {
        try {
          console.log('Processing href:', href);
          const dl = await downloadToTmp(href);
          if (!dl) {
            console.warn('Could not download or locate href:', href);
            continue;
          }
          try {
            const res = await uploadTmp(dl.tmpPath, dl.filename);
            uploaded.push(res);
          } finally {
            try { fs.unlinkSync(dl.tmpPath); } catch (e) {}
          }
        } catch (e) {
          console.error('Error processing href', href, e.message || e);
        }
      }
    }

    console.log('Upload results:', uploaded);

    if (uploaded.length === 0) {
      console.log('No icons were uploaded. Exiting without updating Firestore.');
      process.exit(0);
    }

    // Choose a default icon URL (first uploaded)
    const defaultIcon = uploaded[0].url;
    console.log('Default icon URL:', defaultIcon);

    // Update Firestore docs in Pdis_full and user_pois
    const updateCollections = ['Pdis_full', 'user_pois'];
    for (const col of updateCollections) {
      console.log('Scanning collection', col);
      const snap = await firestore.collection(col).get();
      console.log(`Found ${snap.size} documents in ${col}`);
      let updated = 0;
      for (const doc of snap.docs) {
        const data = doc.data();
        if (!data.iconPath) {
          console.log(`[${col}] would update ${doc.ref.path} -> iconPath=${defaultIcon}`);
          if (apply) {
            await doc.ref.update({ iconPath: defaultIcon });
            updated++;
          }
        }
      }
      console.log(`Collection ${col}: updated ${updated} documents`);
    }

    console.log('\nDone.');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(3);
  }
})();
