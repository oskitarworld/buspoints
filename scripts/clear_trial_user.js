#!/usr/bin/env node
const admin = require('firebase-admin');

async function main() {
  const uid = process.argv[2];
  if (!uid) {
    console.error('Usage: node clear_trial_user.js <uid>');
    process.exit(2);
  }

  try {
    // Initialize with application default credentials / environment.
    admin.initializeApp();
    const db = admin.firestore();
    const userRef = db.collection('users').doc(uid);
    const snap = await userRef.get();
    if (!snap.exists) {
      console.error('User not found:', uid);
      process.exit(3);
    }

    // Delete trial-related fields and ensure status is approved if needed.
    await userRef.set({
      trialStatus: admin.firestore.FieldValue.delete(),
      trialExpiry: admin.firestore.FieldValue.delete(),
      trialRequested: admin.firestore.FieldValue.delete(),
      trialRequestedAt: admin.firestore.FieldValue.delete(),
      trialDeviceId: admin.firestore.FieldValue.delete(),
      // keep status as-is; if you want to force approval uncomment below
      // status: 'approved',
      // approvedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log('Cleared trial fields for user', uid);
    process.exit(0);
  } catch (err) {
    console.error('Error clearing trial fields:', err);
    process.exit(1);
  }
}

main();
