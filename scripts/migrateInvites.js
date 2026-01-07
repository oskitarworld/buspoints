// scripts/migrateInvites.js
// Run this locally with a service account to migrate employees into nested invites
// Usage:
//   export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
//   node scripts/migrateInvites.js <companyId> [--delete-old]

const admin = require('firebase-admin');

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error('Please set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON file');
  process.exit(1);
}

admin.initializeApp();
const db = admin.firestore();

async function migrate(companyId, deleteOld) {
  const empColRef = db.collection('companies').doc(companyId).collection('employees');
  const snapshot = await empColRef.get();
  if (snapshot.empty) {
    console.log('No employee documents found for company', companyId);
    return;
  }
  console.log(`Found ${snapshot.size} employee docs for company ${companyId}`);

  let batch = db.batch();
  let opsInBatch = 0;
  let migrated = 0;

  for (const doc of snapshot.docs) {
    const uid = doc.id;
    const dataDoc = doc.data() || {};
    const inviterId = dataDoc.invitedBy ? String(dataDoc.invitedBy) : 'unknown_inviter';
    // Try to resolve inviter human-readable name to avoid clients needing
    // cross-doc reads. This mirrors the server-side migration behavior.
    let inviterNameResolved = inviterId;
    let inviterCompanyResolved = null;
    try {
      if (inviterId && inviterId !== 'unknown_inviter') {
        const invSnap = await db.collection('users').doc(inviterId).get();
        if (invSnap.exists) {
          const invData = invSnap.data() || {};
          inviterNameResolved = invData.displayName || invData.name || inviterId;
          inviterCompanyResolved = invData.companyName || null;
        }
      }
    } catch (e) {
      console.warn('Failed to resolve inviter name for', inviterId, e && e.message);
    }

    const targetRef = db.collection('companies').doc(companyId)
      .collection('employees_by_inviter').doc(inviterId)
      .collection('invited').doc(uid);

    const toWrite = Object.assign({}, dataDoc, {
      migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      invitedByName: inviterNameResolved,
      invitedByCompanyName: inviterCompanyResolved,
    });

    batch.set(targetRef, toWrite, { merge: true });
    opsInBatch++;
      // Also ensure the original employees/* doc has invitedByName for client reads
      try {
        batch.set(empColRef.doc(uid), { invitedByName: inviterNameResolved, invitedByCompanyName: inviterCompanyResolved }, { merge: true });
        opsInBatch++;
      } catch (e) {
        console.warn('Failed to queue update for original employee doc', uid, e && e.message);
      }
    if (deleteOld) {
      batch.delete(empColRef.doc(uid));
      opsInBatch++;
    }

    migrated++;
    if (opsInBatch >= 450) {
      console.log('Committing batch...');
      await batch.commit();
      batch = db.batch();
      opsInBatch = 0;
    }
  }

  if (opsInBatch > 0) {
    console.log('Committing final batch...');
    await batch.commit();
  }

  console.log('Migration complete. Migrated count:', migrated);
}

(async () => {
  const companyId = process.argv[2];
  const deleteOld = process.argv.includes('--delete-old');
  if (!companyId) {
    console.error('Usage: node scripts/migrateInvites.js <companyId> [--delete-old]');
    process.exit(1);
  }
  try {
    await migrate(companyId, deleteOld);
    console.log('Done');
    process.exit(0);
  } catch (err) {
    console.error('Migration failed:', err && err.message);
    process.exit(2);
  }
})();