/**
 * copy_pdis_to_pdis_v2.js
 *
 * Copies documents from `pdis` into `pdis_v2`, normalizing `slug` and `category`.
 * Use --dryRun to preview operations without writing.
 *
 * Usage:
 *  node copy_pdis_to_pdis_v2.js --serviceAccount ../tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json --batchSize 500 --dryRun
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));

function slugify(s) {
  if (!s) return '';
  return s
    .toString()
    .normalize('NFKD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function shortHash(s) {
  // Simple, deterministic short hash for human-readable suffixes
  let h = 2166136261 >>> 0;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return (h >>> 0).toString(36).slice(-6);
}

function normalizeCategory(cat) {
  if (!cat) return 'otros';
  const c = cat.toString().toLowerCase().trim();
  if (c === '') return 'otros';
  if (/icon-?\d+/.test(c) || c.startsWith('icon-')) return 'otros';
  return c.replace(/[^a-z0-9]+/g, '_');
}

async function main() {
  const serviceAccount = argv.serviceAccount;
  const batchSize = parseInt(argv.batchSize || '500', 10);
  const dryRun = !!argv.dryRun;
  const idStrategy = (argv.idStrategy || 'slug+hash').toString(); // slug | slug+hash | sourceId
  const sourceCollection = argv.source || 'pdis';
  const targetCollection = argv.target || 'pdis_v2';

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

  let lastDoc = null;
  let total = 0;
  const seenSlugs = new Map(); // slug -> [sourceId,...]

  while (true) {
    let query = db.collection(sourceCollection).orderBy('__name__').limit(batchSize);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) break;

    const batch = db.batch();
    for (const doc of snap.docs) {
      const data = doc.data();
      const name = (data.name || data.title || '').toString();
      const rawCategory = data.category || data.type || '';
      const category = normalizeCategory(rawCategory);
      const slug = slugify(`${name}_${category}`) || slugify(name) || doc.id;
      // Decide output id according to idStrategy
      let outId;
      if (idStrategy === 'sourceId') {
        outId = doc.id;
      } else if (idStrategy === 'slug') {
        outId = slug;
      } else {
        // default: slug+hash
        outId = `${slug}_${shortHash(doc.id)}`;
      }

      const out = {
        ...data,
        slug: slug,
        category: category,
        migrated_from: sourceCollection,
        migrated_at: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (dryRun) {
        console.log('[DRYRUN] would write doc:', outId, 'from source id:', doc.id);
        // record slug collisions (based on plain slug)
        const list = seenSlugs.get(slug) || [];
        list.push(doc.id);
        seenSlugs.set(slug, list);
      } else {
        const ref = db.collection(targetCollection).doc(outId);
        batch.set(ref, out, { merge: true });
      }

      total += 1;
      lastDoc = doc;
    }

    if (!dryRun) {
      await batch.commit();
      console.log(`Committed batch, total so far: ${total}`);
    }

    if (snap.size < batchSize) break;
  }

  console.log('Done. Processed documents:', total);

  if (dryRun) {
    // report collisions: slugs with more than one source id
    const collisions = [];
    for (const [s, ids] of seenSlugs.entries()) {
      if (ids.length > 1) collisions.push({ slug: s, count: ids.length, samples: ids.slice(0, 5) });
    }
    collisions.sort((a, b) => b.count - a.count);
    if (collisions.length) {
      console.log('\n[DRYRUN] Detected slug collisions:', collisions.length);
      console.log('[DRYRUN] Top collisions (slug, count, sample sourceIds):');
      collisions.slice(0, 20).forEach(c => {
        console.log('[COLLISION]', c.slug, c.count, c.samples.join(', '));
      });
    } else {
      console.log('\n[DRYRUN] No slug collisions detected.');
    }
    console.log('[DRYRUN] idStrategy:', idStrategy);
    if (idStrategy === 'slug') {
      console.log('[DRYRUN] Warning: using idStrategy=slug may overwrite when collisions exist.');
    }
  }
}

main().catch(err => { console.error(err); process.exit(1); });
