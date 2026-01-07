const admin = require('firebase-admin');

async function main() {
  const argv = process.argv.slice(2);
  if (argv.length < 1) {
    console.error('Usage: node scripts/inspectCompany.js <companyId>');
    process.exit(1);
  }
  const companyId = argv[0];

  // Initialize admin SDK. Requires GOOGLE_APPLICATION_CREDENTIALS env var or
  // that the environment already has application default credentials.
  try {
    admin.initializeApp();
  } catch (e) {
    // ignore if already initialized
  }
  const db = admin.firestore();

  try {
    console.log('Reading companies/%s ...', companyId);
    const compRef = db.collection('companies').doc(companyId);
    const compSnap = await compRef.get();
    if (!compSnap.exists) {
      console.log('companies/%s: NOT FOUND', companyId);
    } else {
      console.log('companies/%s: %s', companyId, JSON.stringify(compSnap.data(), null, 2));
    }
  } catch (e) {
    console.error('Error reading companies doc:', e.message || e);
  }

  try {
    console.log('\nReading users/%s ...', companyId);
    const userRef = db.collection('users').doc(companyId);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      console.log('users/%s: NOT FOUND', companyId);
    } else {
      console.log('users/%s: %s', companyId, JSON.stringify(userSnap.data(), null, 2));
    }
  } catch (e) {
    console.error('Error reading users doc:', e.message || e);
  }

  process.exit(0);
}

main().catch(err => { console.error(err); process.exit(2); });
