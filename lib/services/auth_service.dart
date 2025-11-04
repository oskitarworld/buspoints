
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

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
      return result.user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<User?> register(String name, String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      if (user != null) {
        await user.sendEmailVerification();
        await user.updateDisplayName(name);

        final now = DateTime.now();
        final initialSubscription = Subscription(
          startDate: now,
          endDate: DateTime(now.year + 1, now.month, now.day),
        );

        await _firestore.collection('users').doc(user.uid).set({
          'name': name,
          'email': email,
          'role': 'user',
          'status': 'pending',
          'approvedPoisCount': 0,
          'subscriptionHistory': [initialSubscription.toMap()],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      return user;
    } on FirebaseAuthException {
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}
