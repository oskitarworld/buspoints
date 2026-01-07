// Usage:
// 1) Set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON with Firestore access.
// 2) From repo root run: cd functions && node tools/update_pdi_categories.js --collection pdis_v2 [--apply]
// By default the script runs in dry-run mode and prints proposed updates. Add --apply to commit changes.

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
    console.log('update_pdi_categories.js --collection <name> [--apply] [--project <projectId>] [--stats]');
    console.log('  --stats   : print category/name statistics and sample docs (no writes)');
    process.exit(0);
  }

  try {
    // Initialize admin SDK. It will use GOOGLE_APPLICATION_CREDENTIALS if set.
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: opts.project,
    });
  } catch (e) {
    console.error('Failed to initialize firebase-admin. Make sure GOOGLE_APPLICATION_CREDENTIALS is set or you have application default credentials.');
    console.error(e);
    process.exit(1);
  }

  const db = admin.firestore();
  const col = opts.collection || 'pdis_v2';
  console.log(`Collection: ${col}`);
  console.log(`Dry-run mode: ${!opts.apply}. Pass --apply to write changes.`);
  if (opts.stats) console.log('Stats mode: ON (will not write changes)');

  const snapshot = await db.collection(col).get();
  console.log(`Found ${snapshot.size} documents in ${col}.`);

  let updates = [];
  const categoryCounts = new Map();
  const nameMatches = [];
  const categoryMatches = [];

  snapshot.forEach(doc => {
    const data = doc.data();
    const id = doc.id;
    const nameRaw = data.name || data.nombre || '';
    const name = String(nameRaw).toUpperCase();
  const catRaw = data.category || data.categoria || data.type || '';
    const category = String(catRaw || '').toLowerCase();

    let newCategory = null;

    // Rule: if name contains COLEGIO or INS or INSTITUTO -> parada_bus
    if (name.includes('COLEGIO') || name.includes('INS') || name.includes('INSTITUTO')) {
      if (category !== 'parada_bus') newCategory = 'parada_bus';
    }

    // Other renames (only if name rule didn't already set it)
    if (!newCategory) {
      // zona_de_espera_o_autocares -> zona_espera
      if (category === 'zona_de_espera_o_autocares') newCategory = 'zona_espera';
      // parada_de_bus -> parada_bus
      else if (category === 'parada_de_bus') newCategory = 'parada_bus';
      // gasolineras (plural) or variants containing 'gasolin' -> gasolinera
      else if (category === 'gasolineras' || category.includes('gasolin')) newCategory = 'gasolinera';
    }

    if (newCategory && newCategory !== category) {
      updates.push({ id, before: category, after: newCategory, name: nameRaw });
    }

    // Collect stats
    categoryCounts.set(category, (categoryCounts.get(category) || 0) + 1);
    // names containing keywords
    if (name.includes('COLEGIO') || name.includes('INS') || name.includes('INSTITUTO')) {
      nameMatches.push({ id, name: nameRaw, category });
    }
    // categories of interest (substring match)
    if (category === 'zona_de_espera_o_autocares' || category === 'parada_de_bus' || category === 'gasolineras' || category.includes('gasolin')) {
      categoryMatches.push({ id, name: nameRaw, category });
    }
  });

  // If stats mode requested, print useful diagnostics and exit
  if (opts.stats) {
    console.log('\n--- Category counts (sample) ---');
    // show top 40 categories
    const sorted = Array.from(categoryCounts.entries()).sort((a,b) => b[1]-a[1]);
    sorted.slice(0, 40).forEach(([cat, cnt]) => console.log(`${cat}: ${cnt}`));
    console.log(`\nFound ${nameMatches.length} docs with names matching (COLEGIO/INS/INSTITUTO). Showing up to 20:`);
    nameMatches.slice(0,20).forEach(m => console.log(`${m.id} | ${m.category} | ${m.name}`));
    console.log(`\nFound ${categoryMatches.length} docs with categories of interest. Showing up to 20:`);
    categoryMatches.slice(0,20).forEach(m => console.log(`${m.id} | ${m.category} | ${m.name}`));
    console.log('\nStats complete. No changes made.');
    process.exit(0);
  }

  console.log(`Proposed updates: ${updates.length}`);
  updates.slice(0, 50).forEach(u => console.log(`${u.id}: '${u.before}' -> '${u.after}' -- name='${u.name}'`));
  if (updates.length > 50) console.log(`...and ${updates.length - 50} more`);

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
