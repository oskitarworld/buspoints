const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Helper to normalize keys for doc ids
function normalizeKey(s) {
  return s.replace(/[^a-z0-9]/gi, '_').toLowerCase();
}

exports.createUser = functions.https.onCall(async (data, context) => {
  // Only allow authenticated admins (optional). If you want to allow
  // only callable from trusted environments, check context.auth.token.role
  // or use IAM restrictions.
  try {
    const name = data.name || '';
    const email = data.email || '';
    const phone = data.phone || '';
    const password = data.password || '';
    const role = data.role || 'user';

    if (!email || !password) {
      throw new functions.https.HttpsError('invalid-argument', 'Email and password are required');
    }

    // 1) Create Auth user (this will fail if email is already in use in Auth)
    let userRecord;
    try {
      userRecord = await admin.auth().createUser({
        email: email,
        emailVerified: false,
        password: password,
        displayName: name,
        phoneNumber: phone || undefined,
      });
    } catch (err) {
      console.error('Error creating auth user:', err);
      if (err.code && err.code.includes('auth/')) {
        throw new functions.https.HttpsError('already-exists', err.message || 'Auth creation failed');
      }
      throw new functions.https.HttpsError('internal', 'Auth creation failed');
    }

    const uid = userRecord.uid;
    const firestore = admin.firestore();
    const emailKey = normalizeKey(email);
    const phoneKey = normalizeKey(phone || '');

    const userRef = firestore.collection('users').doc(uid);
    const emailRef = firestore.collection('unique_emails').doc(emailKey);
    const phoneRef = phone ? firestore.collection('unique_phones').doc(phoneKey) : null;

    const now = admin.firestore.FieldValue.serverTimestamp();
    const subscriptionStart = admin.firestore.Timestamp.fromDate(new Date());
    const subscriptionEnd = admin.firestore.Timestamp.fromDate(new Date(new Date().setFullYear(new Date().getFullYear() + 1)));

    // Run a transaction to create uniqueness docs and user doc atomically
    try {
      await firestore.runTransaction(async (tx) => {
        // Check email uniqueness doc
        const emailSnap = await tx.get(emailRef);
        if (emailSnap.exists) {
          throw new functions.https.HttpsError('already-exists', 'Email already in use');
        }
        // Check phone uniqueness if provided
        if (phoneRef) {
          const phoneSnap = await tx.get(phoneRef);
          if (phoneSnap.exists) {
            throw new functions.https.HttpsError('already-exists', 'Phone already in use');
          }
        }

        // Create uniqueness docs
        tx.create(emailRef, { uid: uid, createdAt: now });
        if (phoneRef) tx.create(phoneRef, { uid: uid, createdAt: now });

        // Create the user document
        tx.create(userRef, {
          name: name,
          email: email,
          phone: phone,
          role: role,
          status: 'approved',
          approvedPoisCount: 0,
          subscriptionHistory: [{ startDate: subscriptionStart, endDate: subscriptionEnd }],
          subscriptionStart: subscriptionStart,
          subscriptionEnd: subscriptionEnd,
          createdAt: now,
        });
      });
    } catch (err) {
      console.error('Transaction failed, deleting created auth user:', err);
      // Rollback: delete the auth user we created to avoid dangling auth accounts
      try { await admin.auth().deleteUser(uid); } catch (delErr) { console.error('Failed to delete auth user during rollback:', delErr); }
      // If the error is an HttpsError we rethrow it so client gets the code
      if (err instanceof functions.https.HttpsError) throw err;
      throw new functions.https.HttpsError('internal', 'Failed to create user');
    }

    return { uid };
  } catch (err) {
    console.error('createUser callable error:', err);
    if (err instanceof functions.https.HttpsError) throw err;
    throw new functions.https.HttpsError('internal', err.message || 'Unknown error');
  }
});
