const admin = require('firebase-admin');

async function main() {
  try {
    const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || process.env.PROJECT_ID || 'buspoint-49ea0';
    admin.initializeApp({ projectId: project });
    const db = admin.firestore();

    const tasksDoc = await db.doc('app_config/tasks').get();
    const smtpDoc = await db.doc('app_config/smtp').get();

    const out = {
      project,
      tasks: tasksDoc.exists ? tasksDoc.data() : null,
      smtp: smtpDoc.exists ? smtpDoc.data() : null,
    };

    console.log(JSON.stringify(out, null, 2));
    process.exit(0);
  } catch (e) {
    console.error('Error reading Firestore:', e && e.message);
    process.exit(2);
  }
}

main();
