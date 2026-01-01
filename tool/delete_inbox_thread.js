#!/usr/bin/env node
/**
 * delete_inbox_thread.js
 * ----------------------
 * Admin helper to locate (and optionally delete) documents in
 * `contact_messages` and `user_messages` that don't have an email
 * (empty or missing). Run locally with a Firebase service account JSON.
 *
 * Usage:
 * 1) Install dependency: npm install firebase-admin
 * 2) Dry run (list matches):
 *    node tool/delete_inbox_thread.js --dry-run --limit 200 --key /path/to/key.json
 * 3) Delete matches (interactive unless --force):
 *    node tool/delete_inbox_thread.js --delete --force --limit 200 --key /path/to/key.json
 *
 * Options:
 * --dry-run    : only list matches (default if neither --dry-run nor --delete provided)
 * --delete     : actually delete the matching docs
 * --force      : skip confirmation prompt when deleting
 * --limit N    : limit number of documents fetched per collection (default: 1000)
 * --key PATH   : path to service account JSON (optional if GOOGLE_APPLICATION_CREDENTIALS env var set)
 *
 * Notes:
 * - Firestore cannot query for missing fields server-side; this script fetches documents
 *   (respecting --limit) and filters client-side for docs where email is missing/empty.
 * - Use small limits first for safety.
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

function parseArgs() {
  const argv = process.argv.slice(2);
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dry-run') args.dryRun = true;
    else if (a === '--delete') args.delete = true;
    else if (a === '--force') args.force = true;
    else if (a === '--limit') args.limit = parseInt(argv[++i] || '1000', 10);
    else if (a === '--key') args.key = argv[++i];
    else if (a === '--help' || a === '-h') args.help = true;
    else {
      console.warn('Unknown arg', a);
    }
  }
  if (!args.dryRun && !args.delete) args.dryRun = true;
  if (!args.limit) args.limit = 1000;
  return args;
}

async function main() {
  const args = parseArgs();
  if (args.help) {
    console.log('See top of file for usage.');
    process.exit(0);
  }

  // Initialize admin
  if (args.key) {
    if (!fs.existsSync(args.key)) {
      console.error('Service account key not found at', args.key);
      process.exit(1);
    }
    const keyPath = path.resolve(args.key);
    admin.initializeApp({
      credential: admin.credential.cert(require(keyPath)),
    });
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
    });
  } else {
    console.error('No credentials provided. Set GOOGLE_APPLICATION_CREDENTIALS or pass --key /path/to/key.json');
    process.exit(1);
  }

  const db = admin.firestore();
  const collections = ['contact_messages', 'user_messages'];
  const matches = [];

  console.log(`Running ${args.dryRun ? 'dry-run (no deletes)' : 'delete mode'} with limit ${args.limit} per collection`);

  for (const col of collections) {
    console.log(`\nScanning collection: ${col}`);
    try {
      // Fetch up to limit docs — for safety. If you need full collection, increase the limit.
      const snap = await db.collection(col).limit(args.limit).get();
      console.log(`Fetched ${snap.size} docs from ${col}`);
      snap.forEach((doc) => {
        const data = doc.data() || {};
        const email = data.email;
        const emailMissing = (email === undefined || email === null || (typeof email === 'string' && email.trim() === ''));
        if (emailMissing) {
          matches.push({ collection: col, id: doc.id, path: `${col}/${doc.id}`, data: {
            email: data.email,
            name: data.name || data.displayName || null,
            createdAt: data.createdAt || data.timestamp || null,
          }});
        }
      });

    } catch (err) {
      console.error('Error reading collection', col, err);
    }
  }

  if (matches.length === 0) {
    console.log('\nNo matching documents found (with given limit).');
    process.exit(0);
  }

  console.log(`\nFound ${matches.length} documents with missing/empty email:`);
  matches.forEach((m, idx) => {
    console.log(`${idx + 1}. ${m.path}  name=${m.data.name || '(sin nombre)'}  createdAt=${m.data.createdAt || '(sin fecha)'} `);
  });

  if (args.dryRun) {
    console.log('\nDry run complete. To delete these documents, re-run with --delete --force (careful!).');
    process.exit(0);
  }

  // Delete mode
  if (!args.force) {
    const prompt = require('prompt-sync')({sigint: true});
    const answer = prompt(`\nAre you sure you want to DELETE ${matches.length} documents? Type YES to confirm: `);
    if (answer !== 'YES') {
      console.log('Aborting delete. No changes made.');
      process.exit(0);
    }
  }

  console.log('\nDeleting documents...');
  const batchLimit = 450; // keep under 500
  for (let i = 0; i < matches.length; i += batchLimit) {
    const chunk = matches.slice(i, i + batchLimit);
    const batch = db.batch();
    chunk.forEach((m) => {
      const ref = db.collection(m.collection).doc(m.id);
      batch.delete(ref);
    });
    try {
      await batch.commit();
      console.log(`Deleted batch ${i / batchLimit + 1} (${chunk.length} docs)`);
    } catch (err) {
      console.error('Error deleting batch', err);
      process.exit(1);
    }
  }

  console.log('\nDelete complete.');
  process.exit(0);
}

main().catch((err) => {
  console.error('Fatal error', err);
  process.exit(1);
});
