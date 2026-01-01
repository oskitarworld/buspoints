import 'dart:math';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  FirebaseFirestore get firestore => _firestore;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently() ?? 
                                            await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);
      User? user = result.user;

      if (user != null && result.additionalUserInfo?.isNewUser == true) {
        final now = DateTime.now();
        final initialSubscription = Subscription(
          startDate: now,
          endDate: DateTime(now.year + 1, now.month, now.day),
        );

        await _firestore.collection('users').doc(user.uid).set({
          'name': user.displayName ?? 'Usuario de Google',
          'email': user.email,
          'role': 'user',
          'status': 'approved',
          'approvedPoisCount': 0,
          'subscriptionHistory': [initialSubscription.toMap()],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      return user;
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {

      throw Exception('An unknown error occurred during Google sign-in.');
    }
  }

  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      if (user == null) return null;

      // Protect against concurrent logins: use a per-device persistent
      // session id stored in SharedPreferences. We enforce the rule here
      // by using a Firestore transaction so updates are atomic.
      final docRef = _firestore.collection('users').doc(user.uid);

      final deviceId = await _getOrCreateDeviceId();

      await _firestore.runTransaction((tx) async {
        final snapshot = await tx.get(docRef);
        final data = snapshot.exists ? snapshot.data() ?? {} : {};

        final status = (data['status'] as String?) ?? 'approved';
        if (status == 'cancelled' || status == 'locked') {
          // Account already locked/cancelled -> deny login
          throw FirebaseAuthException(
            code: 'account-locked',
            message: 'Esta cuenta está deshabilitada. Contacte con soporte.'
          );
        }

        final bool sessionActive = (data['sessionActive'] as bool?) ?? false;
        final String? existingDeviceId = data['sessionDeviceId'] as String?;

        if (sessionActive && existingDeviceId != null && existingDeviceId != deviceId) {
          // Another active session exists on a different device -> increment
          // the suspiciousAttempts counter and possibly cancel account.
          final int attempts = (data['suspiciousAttempts'] as int?) ?? 0;
          final int newAttempts = attempts + 1;

          final updates = <String, Object>{
            'suspiciousAttempts': newAttempts,
            'lastSuspiciousAt': FieldValue.serverTimestamp(),
          };

          if (newAttempts >= 3) {
            updates['status'] = 'cancelled';
            updates['cancellationReason'] = 'Multiple concurrent login attempts detected';
            updates['cancelledAt'] = FieldValue.serverTimestamp();
          }

          tx.set(docRef, updates, SetOptions(merge: true));

          // Deny this login by throwing an exception that we'll catch below
          throw FirebaseAuthException(
            code: 'already-logged-in',
            message: 'Ya existe una sesión activa con esta cuenta en otro dispositivo.\n\n' 
                     'Si esto ocurre 3 veces, la cuenta será cancelada automáticamente sin derecho a reclamo.\n' 
                     'Si crees que se trata de un error, contacta con soporte inmediatamente.'
          );
        }

        // No conflicting session — register this device as the active session.
        tx.set(docRef, {
          'sessionActive': true,
          'sessionDeviceId': deviceId,
          'sessionStartedAt': FieldValue.serverTimestamp(),
          // reset suspiciousAttempts on a successful legitimate login
          'suspiciousAttempts': 0,
        }, SetOptions(merge: true));
      });

      return user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  // Generate or return a persistent device session id saved in SharedPreferences.
  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    const key = 'device_session_id';
    String? id = prefs.getString(key);
    if (id != null && id.isNotEmpty) return id;

    // Create a simple but reasonably unique id: timestamp + random int
    final rand = Random.secure();
    id = '${DateTime.now().millisecondsSinceEpoch}-${rand.nextInt(1 << 32)}';
    await prefs.setString(key, id);
    return id;
  }

  Future<User?> register(String name, String email, String phone, String password) async {
    try {
  developer.log('Iniciando registro para $email', name: 'AuthService');
      // Verificar que el nombre de usuario sea único
      try {
        final usernameExists = await _firestore.collection('users')
          .where('name', isEqualTo: name)
          .get();
  developer.log('usernameExists: ${usernameExists.docs.length}', name: 'AuthService');
        if (usernameExists.docs.isNotEmpty) {
          throw FirebaseAuthException(
            code: 'username-already-in-use',
            message: 'El nombre de usuario ya está en uso. Elige otro.'
          );
        }
      } on FirebaseException catch (e) {
        // If the client is not allowed to read `users` collection (common when
        // Firestore rules restrict reads for unauthenticated users), don't block
        // the signup flow. We'll log a warning and continue; auth will still
        // enforce email uniqueness. A proper uniqueness check for username/phone
        // should be implemented server-side (Cloud Function) in production.
        developer.log('Firestore error during username check: $e', name: 'AuthService', error: e, stackTrace: StackTrace.current);
        if (e.code == 'permission-denied' || (e.message ?? '').toLowerCase().contains('permission')) {
          developer.log('Permission denied when checking username; skipping pre-check.', name: 'AuthService');
        } else {
          throw FirebaseAuthException(code: 'firestore-error', message: 'No se pudo verificar el usuario: ${e.message}');
        }
      }
      // Verificar que el email no esté en uso
      try {
        final emailExists = await _firestore.collection('users')
          .where('email', isEqualTo: email)
          .get();
  developer.log('emailExists: ${emailExists.docs.length}', name: 'AuthService');
        if (emailExists.docs.isNotEmpty) {
          throw FirebaseAuthException(
            code: 'email-already-in-use',
            message: 'Ya existe una cuenta para ese correo electrónico.'
          );
        }
      } on FirebaseException catch (e) {
        developer.log('Firestore error during email check: $e', name: 'AuthService', error: e, stackTrace: StackTrace.current);
        if (e.code == 'permission-denied' || (e.message ?? '').toLowerCase().contains('permission')) {
          developer.log('Permission denied when checking email; skipping pre-check.', name: 'AuthService');
        } else {
          throw FirebaseAuthException(code: 'firestore-error', message: 'No se pudo verificar el correo: ${e.message}');
        }
      }
      // Verificar que el teléfono no esté en uso
      try {
        final phoneExists = await _firestore.collection('users')
          .where('phone', isEqualTo: phone)
          .get();
  developer.log('phoneExists: ${phoneExists.docs.length}', name: 'AuthService');
        if (phoneExists.docs.isNotEmpty) {
          throw FirebaseAuthException(
            code: 'phone-already-in-use',
            message: 'Ya existe una cuenta para ese teléfono.'
          );
        }
      } on FirebaseException catch (e) {
        developer.log('Firestore error during phone check: $e', name: 'AuthService', error: e, stackTrace: StackTrace.current);
        if (e.code == 'permission-denied' || (e.message ?? '').toLowerCase().contains('permission')) {
          developer.log('Permission denied when checking phone; skipping pre-check.', name: 'AuthService');
        } else {
          throw FirebaseAuthException(code: 'firestore-error', message: 'No se pudo verificar el teléfono: ${e.message}');
        }
      }

      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;
  developer.log('Usuario creado en Auth: ${user?.uid}', name: 'AuthService');

      if (user != null) {
        await user.updateDisplayName(name);

        // NOTE: sending the verification email is handled by the
        // `VerifyEmailScreen` when the user arrives there. Removing the
        // duplicated send here avoids race conditions and makes failures
        // easier to present to the user from the UI that is responsible
        // for verification flows.

        final userData = {
          'name': name,
          'nameLower': name.toLowerCase(),
          'email': email,
          'phone': phone,
          'role': 'user',
          'status': 'pending',
          'approvedPoisCount': 0,
          'subscriptionHistory': [],
          'createdAt': FieldValue.serverTimestamp(),
        };
  developer.log('Intentando crear documento en Firestore: $userData', name: 'AuthService');
        try {
          await _firestore.collection('users').doc(user.uid).set(userData);
          developer.log('Documento creado en Firestore para ${user.uid}', name: 'AuthService');
        } on FirebaseException catch (e) {
          developer.log('Firestore error creating user doc: $e', name: 'AuthService', error: e, stackTrace: StackTrace.current);
          throw FirebaseAuthException(code: 'firestore-error', message: 'No se pudo crear el perfil de usuario: ${e.message}');
        } catch (e) {
          developer.log('Error al crear documento en Firestore: $e', name: 'AuthService', error: e, stackTrace: StackTrace.current);
          throw Exception('Firestore error: $e');
        }
      }
      return user;
    } on FirebaseAuthException catch (e) {
      developer.log('FirebaseAuthException: ${e.code} - ${e.message}', name: 'AuthService', error: e, stackTrace: StackTrace.current);
      rethrow;
    } catch (e) {
      developer.log('Error inesperado: $e', name: 'AuthService', error: e, stackTrace: StackTrace.current);
      throw Exception('Error inesperado: $e');
    }
  }

  Future<void> signOut() async {
    // Clear sessionActive in Firestore if this device holds the active session
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final deviceId = await _getOrCreateDeviceId();
        final docRef = _firestore.collection('users').doc(user.uid);

        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(docRef);
          if (!snap.exists) return;
          final data = snap.data() ?? {};
          final String? existing = data['sessionDeviceId'] as String?;
          if (existing != null && existing == deviceId) {
            tx.set(docRef, {
              'sessionActive': false,
              'sessionDeviceId': FieldValue.delete(),
              'sessionEndedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        });
      }
    } catch (e) {
      // non-fatal: don't block sign-out if firestore update fails
      developer.log('Warning: could not clear sessionActive on signOut: $e', name: 'AuthService', error: e, stackTrace: StackTrace.current);
    }

    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
