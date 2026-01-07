// inspect_categories.js
// Usage:
// ADC: gcloud auth application-default login
// From functions/: node tools/inspect_categories.js --collection pdis_v2 [--limit 10000]

const admin = require('firebase-admin');

function argvToOpts(argv) {
  const opts = { collection: 'pdis_v2', limit: 0 };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--collection' && argv[i+1]) { opts.collection = argv[i+1]; i++; }
    else if (a === '--limit' && argv[i+1]) { opts.limit = parseInt(argv[i+1], 10) || 0; i++; }
    else if (a === '--help' || a === '-h') { opts.help = true; }
  }
  return opts;
}

(async function main() {
  const opts = argvToOpts(process.argv);
  if (opts.help) {
    console.log('inspect_categories.js --collection <name> [--limit N]');
    process.exit(0);
  }

  try {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  } catch (e) {
    console.error('Failed to initialize firebase-admin. Make sure ADC or GOOGLE_APPLICATION_CREDENTIALS is set.');
    console.error(e);
    process.exit(1);
  }

  const db = admin.firestore();
  const col = opts.collection;
  console.log(`Collection: ${col}`);
  const snapshot = await db.collection(col).get();
  console.log(`Found ${snapshot.size} documents.`);

  const categoryCounts = new Map();
  const sampleByCategory = new Map();
  const nameMatches = [];
  const categoryMatches = [];

  let processed = 0;
  for (const doc of snapshot.docs) {
    if (opts.limit && processed >= opts.limit) break;
    processed++;
    const data = doc.data();
    const id = doc.id;

    // Determine category field(s): try common names
    let rawCat = data.category ?? data.categoria ?? data.type ?? data.categories ?? null;

    // Normalize to array of strings for counting
    let cats = [];
    if (rawCat == null) {
      // nothing
    } else if (Array.isArray(rawCat)) {
      cats = rawCat.map(c => String(c).toLowerCase());
    } else {
      cats = [String(rawCat).toLowerCase()];
    }

    // If there is a nested object with category field
    if (cats.length === 0) {
      // try to detect common nested shapes
      for (const k of Object.keys(data)) {
        const v = data[k];
        if (v && typeof v === 'object' && !Array.isArray(v)) {
          if (v.category || v.categoria) {
            const rc = v.category ?? v.categoria;
            if (rc) cats.push(String(rc).toLowerCase());
          }
        }
      }
    }

    if (cats.length === 0) cats.push('<<no-category>>');

    for (const c of cats) {
      categoryCounts.set(c, (categoryCounts.get(c) || 0) + 1);
      if (!sampleByCategory.has(c)) sampleByCategory.set(c, []);
      if (sampleByCategory.get(c).length < 3) sampleByCategory.get(c).push({ id, name: data.name ?? data.nombre ?? '', rawCategory: rawCat });

      if (c === 'zona_de_espera_o_autocares' || c === 'parada_de_bus' || c === 'gasolineras' || c.includes('gasolin')) {
        categoryMatches.push({ id, name: data.name ?? data.nombre ?? '', category: c });
      }
    }

    const nameRaw = String(data.name ?? data.nombre ?? '').toUpperCase();
    if (nameRaw.includes('COLEGIO') || nameRaw.includes('INS') || nameRaw.includes('INSTITUTO')) {
      nameMatches.push({ id, name: data.name ?? data.nombre ?? '', category: cats.join(',') });
    }
  }

  console.log('\nTop categories:');
  const sorted = Array.from(categoryCounts.entries()).sort((a,b) => b[1]-a[1]);
  sorted.slice(0, 60).forEach(([cat, cnt]) => console.log(`${cat}: ${cnt}`));

  console.log('\nSample by interesting categories:');
  ['zona_de_espera_o_autocares','parada_de_bus','gasolineras'].forEach(cat => {
    const s = sampleByCategory.get(cat) || [];
    console.log(`\nCategory ${cat} -> ${s.length} samples`);
    s.forEach(x => console.log(`  ${x.id} | ${x.name} | rawCategory=${JSON.stringify(x.rawCategory)}`));
  });

  console.log(`\nDocs with names containing COLEGIO/INS/INSTITUTO: ${nameMatches.length} (showing up to 40)`);
  nameMatches.slice(0,40).forEach(m => console.log(`${m.id} | ${m.category} | ${m.name}`));

  console.log(`\nDocs with categories matching patterns: ${categoryMatches.length} (showing up to 40)`);
  categoryMatches.slice(0,40).forEach(m => console.log(`${m.id} | ${m.category} | ${m.name}`));

  process.exit(0);
})();
