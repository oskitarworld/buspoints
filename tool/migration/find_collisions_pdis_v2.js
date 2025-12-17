/**
 * find_collisions_pdis_v2.js
 *
 * Scans `pdis_v2` for potential duplicates and writes a report to stdout and
 * to `tool/migration/pdis_v2_collisions.json`.
 *
 * Usage:
 *  node find_collisions_pdis_v2.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

function roundCoord(n, precision = 5) {
  return Math.round((n || 0) * Math.pow(10, precision)) / Math.pow(10, precision);
}

async function main() {
  const serviceAccount = argv.serviceAccount;
  const saPath = serviceAccount ? path.resolve(__dirname, serviceAccount) : null;

  if (serviceAccount) {
    if (!fs.existsSync(saPath)) {
      console.error('Service account file not found:', saPath);
      process.exit(1);
    }
    admin.initializeApp({ credential: admin.credential.cert(require(saPath)) });
  } else {
    console.log('No --serviceAccount provided, using Application Default Credentials.');
    admin.initializeApp();
  }

  const db = admin.firestore();
  const coll = db.collection('pdis_v2');

  console.log('Scanning pdis_v2 (this may take a while)...');

  const slugMap = new Map();
  const coordMap = new Map();

  let last = null;
  const pageSize = 500;
  let scanned = 0;

  while (true) {
    let q = coll.orderBy('__name__').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      scanned++;
      const data = doc.data();
      const slug = (data.slug || '_no_slug_').toString();
      const list = slugMap.get(slug) || [];
      list.push({ id: doc.id, slug, data });
      slugMap.set(slug, list);

      const loc = data.location || data.loc || null;
      if (loc && loc.latitude != null && loc.longitude != null) {
        const key = `${roundCoord(loc.latitude)}_${roundCoord(loc.longitude)}`;
        const g = coordMap.get(key) || [];
        g.push({ id: doc.id, slug, lat: loc.latitude, lng: loc.longitude });
        coordMap.set(key, g);
      }
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }

  const slugCollisions = Array.from(slugMap.entries()).filter(([k, v]) => v.length > 1)
    .map(([slug, list]) => ({ slug, count: list.length, samples: list.slice(0, 5).map(x => x.id) }));

  const coordGroups = Array.from(coordMap.entries()).filter(([k, v]) => v.length > 1)
    .map(([key, list]) => ({ key, count: list.length, samples: list.slice(0, 5).map(x => x.id) }));

  slugCollisions.sort((a, b) => b.count - a.count);
  coordGroups.sort((a, b) => b.count - a.count);

  const report = {
    scanned,
    slugCollisionsCount: slugCollisions.length,
    coordGroupsCount: coordGroups.length,
    topSlugCollisions: slugCollisions.slice(0, 50),
    topCoordGroups: coordGroups.slice(0, 50),
  };

  const outPath = path.resolve(__dirname, 'pdis_v2_collisions.json');
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log('Scan complete. Report written to', outPath);
  console.log('Summary:', JSON.stringify({ scanned: report.scanned, slugCollisions: report.slugCollisionsCount, coordGroups: report.coordGroupsCount }));
  process.exit(0);
}

main().catch(err => { console.error(err); process.exit(1); });
