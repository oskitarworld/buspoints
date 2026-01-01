/*
Apply iconPath updates from a dry-run CSV.
- Reads CSV `tool/dryrun_icon_map_local.csv` (or provided via --csv)
- Selects rows where proposedType==storage_signed_url and matchedDocId is set
- Backs up current documents to tool/backups/pdis_full_icon_backup_<ts>.json
- Updates Firestore documents setting { iconPath: proposedValue }

Usage:
  node tool/apply_icon_map_from_csv.js --serviceAccount=tool/sa.json --csv=tool/dryrun_icon_map_local.csv --dryRun=false

CAUTION: This will write to Firestore. Default is dryRun=true.
*/

const fs = require('fs');
const path = require('path');
const argv = require('minimist')(process.argv.slice(2));
const admin = require('firebase-admin');

const saPath = argv.serviceAccount || argv.s || 'tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json';
const csvPath = argv.csv || 'tool/dryrun_icon_map_local.csv';
const dryRun = (argv.dryRun === undefined) ? true : (String(argv.dryRun) !== 'false');

if (!fs.existsSync(saPath)) { console.error('Service account not found:', saPath); process.exit(1); }
if (!fs.existsSync(csvPath)) { console.error('CSV not found:', csvPath); process.exit(1); }

admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(saPath))) });
const firestore = admin.firestore();

function parseCsvLines(text) {
  const lines = text.split('\n').map(l => l.trim()).filter(l => l.length>0);
  if (lines.length<=1) return [];
  const header = lines[0].split(',');
  const rows = [];
  for (let i=1;i<lines.length;i++) {
    const line = lines[i];
    // naive CSV split respecting quoted fields
    const parts = [];
    let cur=''; let inq=false;
    for (let c of line) {
      if (c==='"') { inq = !inq; cur += c; }
      else if (c===',' && !inq) { parts.push(cur); cur=''; }
      else cur += c;
    }
    parts.push(cur);
    // map to object
    const obj = {};
    for (let j=0;j<header.length;j++) obj[header[j]] = (parts[j]||'').replace(/^"|"$/g,'');
    rows.push(obj);
  }
  return rows;
}

(async ()=>{
  try {
    const csv = fs.readFileSync(csvPath,'utf8');
    const rows = parseCsvLines(csv);
    console.log('CSV rows parsed:', rows.length);
    const toApply = rows.filter(r => r.proposedType==='storage_signed_url' && r.matchedDocId);
    console.log('High-confidence rows to apply:', toApply.length);
    if (toApply.length===0) { console.log('Nothing to apply. Exiting.'); process.exit(0); }

    // prepare backup
    const backupDir = path.join('tool','backups'); if (!fs.existsSync(backupDir)) fs.mkdirSync(backupDir,{recursive:true});
    const ts = new Date().toISOString().replace(/[:.]/g,'-');
    const backupPath = path.join(backupDir, `pdis_full_icon_backup_${ts}.json`);

    const ids = [...new Set(toApply.map(r=>r.matchedDocId))];
    console.log('Docs to update (unique):', ids.length);

    const backupDocs = {};
    for (let i=0;i<ids.length;i++) {
      const id = ids[i];
      const doc = await firestore.collection('Pdis_full').doc(id).get();
      if (doc.exists) backupDocs[id] = doc.data();
      else backupDocs[id] = null;
    }
    fs.writeFileSync(backupPath, JSON.stringify(backupDocs,null,2),'utf8');
    console.log('Wrote backup to', backupPath);

    if (dryRun) { console.log('Dry run enabled — no changes applied. To apply, rerun with --dryRun=false');
      // still print sample
      console.log('Sample proposals (up to 20):');
      toApply.slice(0,20).forEach((r,i)=>console.log(`${i+1}. doc=${r.matchedDocId} proposed=${r.proposedValue}`));
      process.exit(0);
    }

    // Apply updates in batches of 400
    const BATCH = 400;
    for (let i=0;i<ids.length;i+=BATCH) {
      const batch = firestore.batch();
      const chunk = ids.slice(i, i+BATCH);
      chunk.forEach(id => {
        const r = toApply.find(x => x.matchedDocId===id);
        if (r) batch.update(firestore.collection('Pdis_full').doc(id), { iconPath: r.proposedValue });
      });
      await batch.commit();
      console.log('Committed batch', Math.floor(i/BATCH)+1, 'size', chunk.length);
    }

    console.log('Apply completed. Wrote backup at', backupPath);
    process.exit(0);
  } catch (e) { console.error('Error:', e); process.exit(2); }
})();
