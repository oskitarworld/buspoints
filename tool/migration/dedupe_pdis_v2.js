/**
 * dedupe_pdis_v2.js
 *
 * Deduplicates documents in `pdis_v2` using a chosen strategy.
 * Default is --dryRun: no writes, only prints actions.
 *
 * Usage examples:
 *  node dedupe_pdis_v2.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --by=slug --strategy=keep-first --dryRun --limit=50
 *  node dedupe_pdis_v2.js --serviceAccount ../buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --by=coords --strategy=merge
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

function roundCoord(n, precision = 5) {
  return Math.round((n || 0) * Math.pow(10, precision)) / Math.pow(10, precision);
}

function chooseCanonical(docs) {
  // Choose doc with most non-empty fields, tiebreaker: earliest id
  let best = docs[0];
  let bestScore = -1;
  for (const d of docs) {
    let score = 0;
    const data = d.data;
    for (const k of Object.keys(data)) {
      const v = data[k];
      if (v === null || v === undefined) continue;
      if (typeof v === 'string' && v.trim() === '') continue;
      score++;
    }
    if (score > bestScore || (score === bestScore && d.id < best.id)) {
      best = d;
      bestScore = score;
    }
  }
  return best;
}

function mergeDocs(canonical, others) {
  // Merge simple fields: if canonical missing or empty, take from others (first non-empty)
  const out = Object.assign({}, canonical.data);
  for (const other of others) {
    for (const [k, v] of Object.entries(other.data)) {
      if (out[k] === undefined || out[k] === null || (typeof out[k] === 'string' && out[k].trim() === '')) {
        out[k] = v;
      }
      // arrays: try to concat unique values
      if (Array.isArray(out[k]) && Array.isArray(v)) {
        const set = new Set(out[k].concat(v).filter(x => x != null));
        out[k] = Array.from(set);
      }
    }
  }
  return out;
}

async function main() {
  const serviceAccount = argv.serviceAccount;
  const saPath = serviceAccount ? path.resolve(__dirname, serviceAccount) : null;
  const by = (argv.by || 'slug').toString(); // slug | coords
  const strategy = (argv.strategy || 'keep-first').toString(); // keep-first | merge
  const dryRun = argv.dryRun !== undefined ? !!argv.dryRun : true;
  const limit = parseInt(argv.limit || '0', 10);

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

  console.log('Scanning pdis_v2 for groups by', by, 'strategy', strategy, 'dryRun=', dryRun);

  const groups = new Map();

  // paginate
  let last = null; const pageSize = 500; let scanned = 0;
  while (true) {
    let q = coll.orderBy('__name__').limit(pageSize);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    for (const doc of snap.docs) {
      scanned++;
      const data = doc.data();
      let key = '_no_key_';
      if (by === 'slug') {
        key = (data.slug || '_no_slug_').toString();
      } else {
        const loc = data.location || data.loc || null;
        if (loc && loc.latitude != null && loc.longitude != null) {
          key = `${roundCoord(loc.latitude)}_${roundCoord(loc.longitude)}`;
        } else {
          key = '_no_loc_';
        }
      }
      const list = groups.get(key) || [];
      list.push({ id: doc.id, data });
      groups.set(key, list);
    }
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break;
  }

  // filter groups with more than 1 member
  const dupGroups = Array.from(groups.entries()).filter(([k, v]) => v.length > 1).map(([k, v]) => ({ key: k, docs: v }));
  console.log('Found duplicate groups:', dupGroups.length);

  let processed = 0;
  for (const group of dupGroups) {
    if (limit && processed >= limit) break;
    processed++;
    const docs = group.docs;
    const canonical = chooseCanonical(docs);
    const others = docs.filter(d => d.id !== canonical.id);

    if (strategy === 'keep-first') {
      console.log(`[ACTION] keep-first - keep ${canonical.id}, delete ${others.map(o=>o.id).join(', ')}`);
      if (!dryRun) {
        const batch = db.batch();
        for (const o of others) batch.delete(coll.doc(o.id));
        await batch.commit();
      }
    } else if (strategy === 'merge') {
      const merged = mergeDocs(canonical, others);
      console.log(`[ACTION] merge - will set ${canonical.id} (merge fields) and delete ${others.map(o=>o.id).join(', ')}`);
      if (!dryRun) {
        const batch = db.batch();
        batch.set(coll.doc(canonical.id), merged, { merge: true });
        for (const o of others) batch.delete(coll.doc(o.id));
        await batch.commit();
      }
    }
  }

  console.log('Done. Processed groups:', processed, 'scanned docs:', scanned);
  process.exit(0);
}

main().catch(err => { console.error(err); process.exit(1); });
