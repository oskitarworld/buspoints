// force_update_categories.js
// Force-apply category normalization rules across a Firestore collection.
// WARNING: This will WRITE to Firestore when run with --apply.
// Usage:
//   # dry-run (shows what would be changed):
//   node tools/force_update_categories.js --collection pdis_v2
//   # apply changes (will update documents):
//   node tools/force_update_categories.js --collection pdis_v2 --apply

const admin = require('firebase-admin');

function argvToOpts(argv) {
  const opts = { apply: false, collection: 'pdis_v2', project: undefined };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--apply') opts.apply = true;
    else if (a === '--collection' && argv[i+1]) { opts.collection = argv[i+1]; i++; }
    else if (a === '--project' && argv[i+1]) { opts.project = argv[i+1]; i++; }
    else if (a === '--help' || a === '-h') { opts.help = true; }
  }
  return opts;
}

(async function main() {
  const opts = argvToOpts(process.argv);
  if (opts.help) {
    console.log('force_update_categories.js --collection <name> [--apply] [--project <projectId>]');
    process.exit(0);
  }

  try {
    admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId: opts.project });
  } catch (e) {
    console.error('Failed to initialize firebase-admin. Make sure GOOGLE_APPLICATION_CREDENTIALS or ADC is configured.');
    console.error(e);
    process.exit(1);
  }

  const db = admin.firestore();
  const col = opts.collection || 'pdis_v2';
  console.log(`Collection: ${col}`);
  console.log(`Apply mode: ${opts.apply}. (Pass --apply to write changes)`);

  const snapshot = await db.collection(col).get();
  console.log(`Found ${snapshot.size} documents in ${col}.`);

  const updates = [];

  snapshot.forEach(doc => {
    const data = doc.data();
    const id = doc.id;
    const nameRaw = data.name || data.nombre || '';
    const name = String(nameRaw).toUpperCase();
    const catRaw = data.category || data.categoria || data.type || '';
    const category = String(catRaw || '').toLowerCase().trim();

    let newCategory = null;

    // Name-based rule (highest priority)
    if (name.includes('COLEGIO') || name.includes('INS') || name.includes('INSTITUTO')) {
      newCategory = 'parada_bus';
    }

    // Category normalization (catch variants and plural forms)
    if (!newCategory) {
      // Normalize whitespace/accents loosely by checking substrings
      const catNorm = category.replace(/\s+/g, '_');
      if (catNorm === 'zona_de_espera_o_autocares' || category.includes('zona') && category.includes('espera') && category.includes('autocares')) {
        newCategory = 'zona_espera';
      } else if (catNorm === 'parada_de_bus' || category === 'parada-de-bus' || category.includes('parada') && category.includes('bus')) {
        newCategory = 'parada_bus';
      } else if (category === 'gasolineras' || category.includes('gasolin')) {
        newCategory = 'gasolinera';
      }
    }

    if (newCategory && newCategory !== category) {
      updates.push({ id, before: category, after: newCategory, name: nameRaw });
    }
  });

  if (updates.length === 0) {
    console.log('No documents to update.');
    process.exit(0);
  }

  console.log(`Proposed updates: ${updates.length}`);
  updates.slice(0, 100).forEach(u => console.log(`${u.id}: '${u.before}' -> '${u.after}' -- name='${u.name}'`));
  if (updates.length > 100) console.log(`...and ${updates.length - 100} more`);

  if (!opts.apply) {
    console.log('\nDry-run complete. Rerun with --apply to commit changes.');
    process.exit(0);
  }

  // Commit in batches of 400
  const BATCH_SIZE = 400;
  let committed = 0;
  for (let i = 0; i < updates.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const slice = updates.slice(i, i + BATCH_SIZE);
    slice.forEach(u => {
      const ref = db.collection(col).doc(u.id);
      batch.update(ref, { category: u.after });
    });
    await batch.commit();
    committed += slice.length;
    console.log(`Committed ${committed}/${updates.length}`);
  }

  console.log('All updates committed.');
  process.exit(0);
})();
