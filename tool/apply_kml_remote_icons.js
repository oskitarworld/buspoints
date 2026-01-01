/*
Script: apply_kml_remote_icons.js
- Reads a KMZ (default: assets/pdifull_icon/buspointfull.KMZ)
- Extracts doc.kml and any <href> entries
- For each href that is an HTTP(s) URL, fetches it. If it's a KML, parses it for <Icon><href> or <href> entries that point to images.
- Collects image URLs and uses the first one as defaultIcon
- Updates Firestore collections `Pdis_full` and `user_pois`, setting `iconPath` to defaultIcon for docs that don't have it

Usage:
  node tool/apply_kml_remote_icons.js --serviceAccount=tool/sa.json --kmz=assets/pdifull_icon/buspointfull.KMZ [--dry]

By default it runs in dry-run mode. Pass --apply to perform updates.
*/

const AdmZip = require('adm-zip');
const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

const serviceAccountPath = argv.serviceAccount || argv.s;
const kmzPath = argv.kmz || argv.k;
const apply = argv.apply || false;

if (!serviceAccountPath || !kmzPath) {
  console.log('Usage: node tool/apply_kml_remote_icons.js --serviceAccount=tool/sa.json --kmz=assets/pdifull_icon/buspointfull.KMZ [--apply]');
  process.exit(1);
}
if (!fs.existsSync(serviceAccountPath)) { console.error('Service account not found:', serviceAccountPath); process.exit(2); }
if (!fs.existsSync(kmzPath)) { console.error('KMZ file not found:', kmzPath); process.exit(2); }

const sa = require(path.resolve(serviceAccountPath));
admin.initializeApp({ credential: admin.credential.cert(sa) });
const firestore = admin.firestore();

const http = require('http');
const https = require('https');
 

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    try {
      const client = url.startsWith('https://') ? https : http;
      client.get(url, (res) => {
        const status = res.statusCode;
        if (status >= 300 && status < 400 && res.headers.location) {
          // follow redirect
          return resolve(fetchUrl(res.headers.location));
        }
        if (status >= 400) return reject(new Error('HTTP ' + status));
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const buf = Buffer.concat(chunks);
          const ct = (res.headers['content-type'] || '').split(';')[0];
          resolve({ buf, contentType: ct, url });
        });
      }).on('error', (err) => reject(err));
    } catch (err) { reject(err); }
  });
}

function extractHrefValues(kmlText) {
  const hrefs = [];
  const hrefRegex = /<href>([\s\S]*?)<\/href>/gi;
  let m;
  while ((m = hrefRegex.exec(kmlText))) {
    if (m[1]) hrefs.push(m[1].trim());
  }
  return hrefs.map(h => h.replace(/^<!\[CDATA\[/i, '').replace(/\]\]>$/i, '').replace(/[\r\n\t]/g, '').trim()).filter(Boolean);
}

(async () => {
  try {
    console.log('Reading KMZ:', kmzPath);
    const zip = new AdmZip(kmzPath);
    const entries = zip.getEntries();
    const kmlEntry = entries.find(e => e.entryName.toLowerCase().endsWith('.kml') || /doc\.kml$/i.test(e.entryName));
    if (!kmlEntry) {
      console.log('No KML found inside KMZ. Exiting.');
      process.exit(0);
    }
    const kmlText = kmlEntry.getData().toString('utf8');
    const hrefs = extractHrefValues(kmlText);
    if (hrefs.length === 0) {
      console.log('No <href> entries found inside KML. Exiting.');
      process.exit(0);
    }
    console.log('Found hrefs in KMZ KML:', hrefs);

    // For each href that is an http(s) URL, fetch it and extract image hrefs
    const candidateImageUrls = [];
    for (const href of hrefs) {
      const normalized = href.replace(/[\r\n\t]/g, '').trim();
      if (/^https?:\/\//i.test(normalized)) {
        console.log('Fetching remote href:', normalized);
        try {
          const { buf, contentType, url } = await fetchUrl(normalized);
          // If it's a KMZ (zip) we need to parse inner KML
          if (contentType && /kmz|zip|application\/vnd\.google-earth\.kmz/i.test(contentType)) {
            try {
              const innerZip = new AdmZip(buf);
              const innerEntries = innerZip.getEntries();
              const innerKml = innerEntries.find(e => e.entryName.toLowerCase().endsWith('.kml') || /doc\.kml$/i.test(e.entryName));
              if (innerKml) {
                const innerText = innerKml.getData().toString('utf8');
                const found = extractHrefValues(innerText);
                console.log(` - inner KMZ fetched, found ${found.length} hrefs`);
                // show a sample of found hrefs for diagnostics
                console.log('   sample hrefs:', found.slice(0, 20));
                for (const f of found) {
                  const nf = f.replace(/[\r\n\t]/g, '').trim();
                  if (/^https?:\/\//i.test(nf) && /\.(png|jpe?g|svg|webp)(?:\?|$)/i.test(nf)) {
                    candidateImageUrls.push(nf);
                  } else if (/^https?:\/\//i.test(nf)) {
                    // collect remote hrefs too; we may need to follow them later
                    candidateImageUrls.push(nf);
                  }
                }
              } else {
                console.log(' - inner KMZ has no KML entries');
              }
            } catch (err) {
              console.warn(' - could not parse remote KMZ buffer:', err.message || err);
            }
            continue;
          }

          if (contentType && /xml|kml|text\//i.test(contentType)) {
            const text = buf.toString('utf8');
            const found = extractHrefValues(text);
            console.log(` - KML fetched, found ${found.length} hrefs`);
            for (const f of found) {
              const nf = f.replace(/[\r\n\t]/g, '').trim();
              if (/^https?:\/\//i.test(nf) && /\.(png|jpe?g|svg|webp)(?:\?|$)/i.test(nf)) {
                candidateImageUrls.push(nf);
              } else if (/^https?:\/\//i.test(nf)) {
                // maybe it's an icon URL without extension; accept it anyway
                candidateImageUrls.push(nf);
              }
            }
          } else if (contentType && /^image\//i.test(contentType)) {
            // the href itself points to an image
            candidateImageUrls.push(url);
            console.log(' - href is an image:', url);
          } else {
            console.log(' - remote href not KML or image, contentType=', contentType);
          }
        } catch (err) {
          console.warn('Could not fetch remote href', normalized, err.message || err);
        }
      } else {
        console.log('Skipping non-http href:', normalized);
      }
    }

    const uniqueImages = Array.from(new Set(candidateImageUrls)).filter(Boolean);
    if (uniqueImages.length === 0) {
      console.log('No remote image URLs discovered from KML(s). Exiting.');
      process.exit(0);
    }

    console.log('Discovered image URLs (examples):', uniqueImages.slice(0, 10));
    const defaultIcon = uniqueImages[0];
    console.log('Default icon chosen:', defaultIcon);

    // Confirm: update Firestore collections
    const collections = ['Pdis_full', 'user_pois'];
    for (const col of collections) {
      console.log('Scanning collection', col);
      const snap = await firestore.collection(col).get();
      console.log(` - Found ${snap.size} documents in ${col}`);
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
      console.log(` - Collection ${col}: updated ${updated} documents`);
    }

    console.log('\nDone.');
    process.exit(0);
  } catch (e) {
    console.error('Error:', e);
    process.exit(2);
  }
})();
