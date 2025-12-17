// Script para probar acceso a Firestore desde Node.js
// Requiere instalar firebase-admin: npm install firebase-admin

const admin = require('firebase-admin');
const serviceAccount = require('../tool/buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://buspoint-49ea0.firebaseio.com'
});

const db = admin.firestore();

async function testAccess() {
  try {
    // Leer mensajes de contacto
    const contactSnap = await db.collection('contact_messages').limit(5).get();
    console.log('contact_messages:', contactSnap.docs.map(doc => doc.data()));

    // Leer mensajes de usuario para un admin específico
    const adminUid = 'CzIo0lrr3FfCzPDt7yxTzwLqJF73';
    const userMsgSnap = await db.collection('users').doc(adminUid).collection('user_messages').limit(5).get();
    console.log('user_messages:', userMsgSnap.docs.map(doc => doc.data()));
  } catch (e) {
    console.error('Firestore access error:', e);
  }
}

testAccess();
