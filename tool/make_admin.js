#!/usr/bin/env node
/**
 * make_admin.js
 * Simple admin helper to set `isAdmin: true` (or role: 'admin') on a user document in Firestore.
 * Usage:
 *   npm install firebase-admin prompt-sync
 *   node tool/make_admin.js --key /path/to/serviceAccount.json --uid <UID> [--force]
 * Or set GOOGLE_APPLICATION_CREDENTIALS env var and omit --key.
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

function parseArgs() {
  const argv = process.argv.slice(2);
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--key') args.key = argv[++i];
    else if (a === '--uid') args.uid = argv[++i];
    else if (a === '--force') args.force = true;
    else if (a === '--help' || a === '-h') args.help = true;
    else console.warn('Unknown arg', a);
  }
  return args;
}

async function main() {
  const args = parseArgs();
  if (args.help) {
    console.log('Usage: node tool/make_admin.js --key /path/key.json --uid <UID> [--force]');
    process.exit(0);
  }

  if (!args.key && !process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error('Provide a service account JSON via --key or set GOOGLE_APPLICATION_CREDENTIALS');
    process.exit(1);
  }
  if (args.key && !fs.existsSync(args.key)) {
    console.error('Service account key not found at', args.key);
    process.exit(1);
  }
  if (!args.uid) {
    console.error('Missing --uid <UID>');
    process.exit(1);
  }

  // init
  if (args.key) {
    const keyPath = path.resolve(args.key);
    admin.initializeApp({ credential: admin.credential.cert(require(keyPath)) });
  } else {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }

  const db = admin.firestore();
  const uid = args.uid;

  // confirm
  if (!args.force) {
    const prompt = require('prompt-sync')({ sigint: true });
    const answer = prompt(`Set isAdmin=true for users/${uid}? Type YES to confirm: `);
    if (answer !== 'YES') {
      console.log('Aborted.');
      process.exit(0);
    }
  }

  try {
    const ref = db.collection('users').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
      console.log('User document does not exist. Creating users/' + uid);
      await ref.set({ isAdmin: true, role: 'admin' }, { merge: true });
    } else {
      await ref.set({ isAdmin: true, role: 'admin' }, { merge: true });
    }
    console.log('Updated users/' + uid + ' -> isAdmin=true');
    process.exit(0);
  } catch (err) {
    console.error('Error updating user:', err);
    process.exit(1);
  }
}

main();
