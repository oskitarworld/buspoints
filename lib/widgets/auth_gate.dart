import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:myapp/services/auth_service.dart';
import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:myapp/models/user_model.dart';
import 'package:myapp/screens/home_screen.dart';
import 'package:myapp/screens/pending_approval_screen.dart';
import 'package:myapp/screens/subscription_screen.dart';
import 'package:myapp/screens/frozen_account_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);

    if (user == null) {
      return const AuthScreen();
    }

    return UserRoleGate(user: user);
  }
}

class UserRoleGate extends StatelessWidget {
  final User user;

  const UserRoleGate({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    Future<void> subscribeToRoleTopic(String role) async {
      try {
        if (role == 'admin') {
          await FirebaseMessaging.instance.subscribeToTopic('admins');
        } else {
          await FirebaseMessaging.instance.subscribeToTopic('users');
        }
        // Subscribe to a per-user topic so admins can send notifications to a
        // specific user by topic name `user_<uid>`.
        await FirebaseMessaging.instance.subscribeToTopic('user_${user.uid}');
        // Register FCM token for this device in the user document so server
        // can send per-device messages (and set APNs badge numbers).
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'fcmTokens': FieldValue.arrayUnion([token])
            }, SetOptions(merge: true));
          }
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
              'fcmTokens': FieldValue.arrayUnion([newToken])
            }, SetOptions(merge: true));
          });
        } catch (e) {
          debugPrint('No se pudo registrar el token FCM: $e');
        }
      } catch (e) {
        debugPrint('Error al suscribirse a topic FCM: $e');
      }
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        // If the stream yields an error (e.g. permission-denied), don't
        // immediately sign the user out — show a friendly message and
        // allow the UX to proceed (the VerifyEmailScreen or other flows
        // will still work).
        if (snapshot.hasError) {
          final err = snapshot.error;
          debugPrint('[UserRoleGate] Snapshot error for users/${user.uid}: $err');
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text('Esperando permisos para leer el perfil de usuario. Si esto persiste, cierra sesión e inténtalo de nuevo.', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        context.read<AuthService>().signOut();
                      },
                      child: const Text('Cerrar sesión'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // If there is no document yet, show a short waiting state rather
          // than forcing a sign-out; this avoids race conditions just after
          // user creation when rules or replication may delay availability.
          return const Scaffold(body: Center(child: Text('Perfil de usuario en creación...')));
        }

        final userModel = UserModel.fromFirestore(snapshot.data!);
        subscribeToRoleTopic(userModel.role);

        if (userModel.role == 'admin') {
          return const HomeScreen();
        }

        if (userModel.subscriptionFrozen == true) {
          return FrozenAccountScreen(username: userModel.name);
        }
        switch (userModel.status) {
          case 'approved':
            return userModel.isSubscriptionActive ? const HomeScreen() : const SubscriptionScreen();
          case 'pending':
          default:
            return const PendingApprovalScreen();
        }
      },
    );
  }
}
