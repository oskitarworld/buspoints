// list_pendings.js
// Usage: node tool/list_pendings.js
// Requires the service account json at tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const serviceAccountPath = path.join(__dirname, 'buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('Service account file not found at', serviceAccountPath);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

async function main() {
  try {
    console.log('Counting pending items in project buspoint-49ea0...');

    const [usersPendingSnap, contactUnreadSnap, userMessagesUnreadSnap, userPoisPendingSnap, reviewsPendingSnap] = await Promise.all([
      db.collection('users').where('status', '==', 'pending').get(),
      db.collection('contact_messages').where('read', '==', false).get(),
      db.collection('user_messages').where('read', '==', false).get(),
      db.collection('user_pois').where('status', '==', 'pending').get(),
      db.collectionGroup('reviews').where('status', '==', 'pending').get(),
    ]);

    console.log('Pending users:', usersPendingSnap.size);
    console.log('Unread contact_messages:', contactUnreadSnap.size);
    console.log('Unread user_messages:', userMessagesUnreadSnap.size);
    console.log('Pending user_pois:', userPoisPendingSnap.size);
    console.log('Pending reviews (collectionGroup):', reviewsPendingSnap.size);

    // List top 10 unread user_messages
    console.log('\nTop unread user_messages (first 10):');
    userMessagesUnreadSnap.docs.slice(0,10).forEach(doc => {
      const d = doc.data();
      console.log(doc.id, d.fromName || d.fromEmail, '->', d.toUid || d.toEmail, 'read:', d.read, 'fromAdmin:', d.fromAdmin || false);
    });

    // List top 10 unread contact messages
    console.log('\nTop unread contact_messages (first 10):');
    contactUnreadSnap.docs.slice(0,10).forEach(doc => {
      const d = doc.data();
      console.log(doc.id, d.name || d.email, 'msg:', (d.message || '').slice(0,80));
    });

    process.exit(0);
  } catch (err) {
    console.error('Error listing pendings:', err);
    process.exit(2);
  }
}

main();
