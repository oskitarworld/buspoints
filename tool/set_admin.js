// Script para restaurar el rol admin a un usuario en Firestore
// Ejecuta este script con: node tool/set_admin.js [email_del_usuario]
// Ejemplo: node tool/set_admin.js admin@example.com

const admin = require('firebase-admin');

// Inicializa Firebase Admin con tus credenciales
admin.initializeApp({
  credential: admin.credential.cert(require('./buspoint-49ea0-firebase-adminsdk-fbsvc-617a198e25.json')),
});

const db = admin.firestore();
const auth = admin.auth();

// Obtener email del argumento o usar uno por defecto
const emailOrUid = process.argv[2];

if (!emailOrUid) {
  console.error('❌ Por favor proporciona el email o UID del usuario');
  console.error('Uso: node tool/set_admin.js [email_o_uid]');
  process.exit(1);
}

async function setAdmin() {
  try {
    let uid = emailOrUid;
    
    // Si es un email, obtener el UID
    if (emailOrUid.includes('@')) {
      console.log(`🔍 Buscando usuario con email: ${emailOrUid}...`);
      const userRecord = await auth.getUserByEmail(emailOrUid);
      uid = userRecord.uid;
      console.log(`✅ UID encontrado: ${uid}`);
    }
    
    // Obtener datos actuales del usuario
    const userDoc = await db.collection('users').doc(uid).get();
    if (!userDoc.exists) {
      console.error(`❌ Usuario con UID ${uid} no existe en Firestore`);
      process.exit(1);
    }
    
    const userData = userDoc.data();
    console.log(`📋 Datos actuales del usuario:`);
    console.log(JSON.stringify(userData, null, 2));
    
    // Actualizar isAdmin
    await db.collection('users').doc(uid).update({ 
      isAdmin: true,
      role: 'admin'
    });
    
    console.log(`✅ Rol admin asignado correctamente al usuario ${uid}`);
    console.log(`✅ Ahora puedes eliminar y actualizar mensajes sin problemas`);
  } catch (err) {
    console.error('❌ Error:', err.message);
    process.exit(1);
  }
}

setAdmin();
