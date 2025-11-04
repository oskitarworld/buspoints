import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _usersCollectionName = 'users';

  Future<void> ensureAdminUser(User user) async {
    final userDocRef =
        _firestore.collection(_usersCollectionName).doc(user.uid);
    final userDoc = await userDocRef.get();

    if (!userDoc.exists) {
      await userDocRef.set({
        'email': user.email,
        'username': 'admin',
        'isAdmin': true, // Default to true for the first admin
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> createUserDocument(User user, {required String username}) async {
    final userDocRef =
        _firestore.collection(_usersCollectionName).doc(user.uid);
    final userDoc = await userDocRef.get();

    if (!userDoc.exists) {
      await userDocRef.set({
        'email': user.email,
        'username': username,
        'isAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<bool> isAdmin(String uid) async {
    try {
      final userDoc =
          await _firestore.collection(_usersCollectionName).doc(uid).get();
      if (userDoc.exists && userDoc.data()!['isAdmin'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      developer.log('Error checking admin status: $e',
          name: 'FirestoreService');
      return false;
    }
  }

  Future<void> updateUserStatus(String uid, String status) async {
    try {
      await _firestore
          .collection(_usersCollectionName)
          .doc(uid)
          .update({'status': status});
      developer.log('User status updated successfully',
          name: 'FirestoreService');
    } catch (e) {
      developer.log('Error updating user status: $e', name: 'FirestoreService');
      // Re-throw the exception to be handled by the UI layer
      rethrow;
    }
  }

  static const String _collectionName = 'locations';

  Stream<QuerySnapshot> getBusLocationStream() {
    developer.log(
        '[map.firestore] FORENSICS: Subscribing to Firestore collection: $_collectionName',
        name: 'map.firestore');
    return _firestore
        .collection(_collectionName)
        .snapshots()
        .handleError((error) {
      developer.log(
        '[map.firestore] FORENSICS: Error in Firestore stream.',
        error: error,
        name: 'map.firestore',
      );
      // The stream is automatically closed on error, but we could transform it to an error state if needed.
    });
  }

  Future<void> addPointOfInterest(
      String name, String description, GeoPoint location) {
    return _firestore.collection(_collectionName).add({
      'name': name,
      'description': description,
      'geopoint': location, 
    }).catchError((e) {
      developer.log('Error adding point of interest: $e', name: 'FirestoreService');
      // Re-throw the exception to be handled by the UI layer
      throw e;
    });
  }
}
