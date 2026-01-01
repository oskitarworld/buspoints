/*
  Usage:
    # from repository root
    cd functions
    npm install firebase-admin
    # set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON that has project-level permissions, or run where Application Default Credentials are available
    node tools/generate_password_reset_link.js user@example.com

  This script initializes firebase-admin with default credentials and prints a generated password reset link for the supplied email.
*/

const admin = require('firebase-admin');

async function main() {
  const email = process.argv[2];
  if (!email) {
    console.error('Usage: node tools/generate_password_reset_link.js <email>');
    process.exit(1);
  }

  try {
    // Initialize app if not already initialized
    if (admin.apps.length === 0) {
      admin.initializeApp();
    }

    const link = await admin.auth().generatePasswordResetLink(email);
    console.log('Generated password reset link for', email);
    console.log(link);
  } catch (err) {
    console.error('Error generating link:', err && err.message ? err.message : err);
    process.exit(2);
  }
}

main();
