const admin = require('firebase-admin');
const { execSync } = require('child_process');

async function main() {
  try {
    const uid = process.argv[2];
    if (!uid) {
      console.error('Usage: node delete_pending_task_for_user.js <uid>');
      process.exit(2);
    }
    const project = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || 'buspoint-49ea0';
    admin.initializeApp({ projectId: project });
    const db = admin.firestore();
    const docRef = db.collection('users').doc(uid);
    const snap = await docRef.get();
    if (!snap.exists) {
      console.error('User not found', uid);
      process.exit(3);
    }
    const data = snap.data() || {};
    const taskName = data.pendingReminderTask;
    if (!taskName) {
      console.log('No pendingReminderTask found for user', uid);
      process.exit(0);
    }
    console.log('Found pendingReminderTask:', taskName);
    const m = taskName.match(/^projects\/([^\/]+)\/locations\/([^\/]+)\/queues\/([^\/]+)\/tasks\/([^\/]+)$/);
    if (!m) {
      console.error('Task name not in expected format');
      process.exit(4);
    }
    const [, proj, location, queue, taskId] = m;
    console.log('Deleting task id', taskId, 'from queue', queue, 'in', location, 'project', proj);
    try {
      execSync(`gcloud tasks delete ${taskId} --project=${proj} --queue=${queue} --location=${location} --quiet`, { stdio: 'inherit' });
      console.log('Task deleted via gcloud');
    } catch (e) {
      console.error('gcloud tasks delete failed:', e.message);
      process.exit(5);
    }

    try {
      await docRef.update({ pendingReminderTask: admin.firestore.FieldValue.delete() });
      console.log('Cleared pendingReminderTask field from user doc');
    } catch (e) {
      console.error('Failed to clear field from Firestore:', e && e.message);
      process.exit(6);
    }
    process.exit(0);
  } catch (err) {
    console.error('Error:', err && err.stack ? err.stack : err);
    process.exit(1);
  }
}

main();
