import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:developer' as developer;
import 'dart:async';
import 'package:myapp/services/firestore_web_compat.dart';

import 'package:myapp/services/auth_service.dart';
import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:myapp/models/user_model.dart';
import 'package:myapp/screens/home_screen.dart';
import 'package:myapp/screens/pending_approval_screen.dart';
import 'package:myapp/screens/subscription_screen.dart';
import 'package:myapp/screens/frozen_account_screen.dart';

// Track which users have already been shown the trial popup during this app session
final Set<String> _trialDialogShown = <String>{};

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    // If there's no authenticated user, show the auth screen.
    if (user == null) return const AuthScreen();
    // Otherwise delegate to the user-role gate which handles trials/subscriptions.
    return UserRoleGate(user: user);
  }
}

// Persistent banner showing trial countdown in HHH:MM:SS and animating every second.
class TrialCountdownBanner extends StatefulWidget {
  final DateTime expiry;
  const TrialCountdownBanner({super.key, required this.expiry});

  @override
  State<TrialCountdownBanner> createState() => _TrialCountdownBannerState();
}

class _TrialCountdownBannerState extends State<TrialCountdownBanner> {
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final now = DateTime.now().toUtc();
    final rem = widget.expiry.toUtc().difference(now);
    if (mounted) {
      setState(() {
        _remaining = rem.isNegative ? Duration.zero : rem;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _format(Duration d) {
    final hoursTotal = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, "0");
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, "0");
  return '${hoursTotal.toString().padLeft(2, "0")}:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining <= Duration.zero) return const SizedBox.shrink();
    final textStyle = const TextStyle(fontFamily: 'monospace', color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15);
    return Material(
      elevation: 12,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingApprovalScreen())),
        child: Container(
          color: Colors.red.shade700,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                const Icon(Icons.timer, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Prueba gratuita — Quedan',
                          style: textStyle.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
                        child: Text(
                          _format(_remaining),
                          key: ValueKey<String>(_format(_remaining)),
                          style: textStyle.copyWith(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UserRoleGate extends StatelessWidget {
  final User user;

  const UserRoleGate({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    Future<void> subscribeToRoleTopic(String role) async {
      try {
        if (kIsWeb) {
          developer.log('Running on web: skipping topic subscriptions (use server-side topic management for web)', name: 'AuthGate');
        } else {
          if (role == 'admin') {
            await FirebaseMessaging.instance.subscribeToTopic('admins');
          } else {
            await FirebaseMessaging.instance.subscribeToTopic('users');
          }
          await FirebaseMessaging.instance.subscribeToTopic('user_${user.uid}');
        }
        if (!kIsWeb) {
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
          } catch (e, s) {
            developer.log('No se pudo registrar el token FCM: $e', name: 'AuthGate', error: e, stackTrace: s);
          }
        }
      } catch (e) {
        debugPrint('Error al suscribirse a topic FCM: $e');
      }
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: resilientStream(FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(), name: 'auth_gate_user_doc'),
      builder: (context, snapshot) {
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
                      onPressed: () => context.read<AuthService>().signOut(),
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
          return const Scaffold(body: Center(child: Text('Perfil de usuario en creación...')));
        }

        final userModel = UserModel.fromFirestore(snapshot.data!);
        subscribeToRoleTopic(userModel.role);

        // Show trial popup once per app session
        if (userModel.isTrialActive && !_trialDialogShown.contains(user.uid)) {
          _trialDialogShown.add(user.uid);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            final now = DateTime.now().toUtc();
            final expiry = userModel.trialExpiry!.toUtc();
            final remaining = expiry.difference(now).isNegative ? Duration.zero : expiry.difference(now);

            final remainingNotifier = ValueNotifier<Duration>(remaining);
            final timer = Timer.periodic(const Duration(seconds: 1), (_) {
              final now2 = DateTime.now().toUtc();
              final rem2 = expiry.difference(now2);
              remainingNotifier.value = rem2.isNegative ? Duration.zero : rem2;
            });

            showDialog<void>(
              context: context,
              builder: (ctx) => Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: remainingNotifier,
                    builder: (ctx2, rem, _) {
                      final hours2 = rem.inHours;
                      final minutes2 = rem.inMinutes.remainder(60);
                      final seconds2 = rem.inSeconds.remainder(60);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Theme.of(context).colorScheme.primary.withAlpha((0.12 * 255).round()),
                            child: Icon(Icons.star_border, size: 30, color: Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Periodo de prueba activo',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${hours2.toString().padLeft(2, "0")}:${minutes2.toString().padLeft(2, "0")}:${seconds2.toString().padLeft(2, "0")}',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary),
                          ),
                          const SizedBox(height: 12),
                          // Mostrar sólo el cronómetro en formato HHH:MM:SS para evitar
                          // duplicar la información visual. Si quieres añadir una
                          // línea de texto adicional, la podemos reintroducir aquí.
                          const SizedBox(height: 8),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    side: const BorderSide(color: Colors.deepOrangeAccent, width: 2),
                                    foregroundColor: Colors.deepOrangeAccent,
                                    backgroundColor: Colors.transparent,
                                    minimumSize: const Size.fromHeight(44),
                                    alignment: Alignment.center,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                  },
                                  child: const Text('Recordármelo después', textAlign: TextAlign.center),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    backgroundColor: Colors.deepPurpleAccent,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size.fromHeight(44),
                                    alignment: Alignment.center,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  onPressed: () {
                                    Navigator.of(ctx).pop();
                                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PendingApprovalScreen()));
                                  },
                                  child: const Text('Hazte Premium', textAlign: TextAlign.center),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text('Cerrar', style: TextStyle(color: Colors.grey[700])),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ).then((_) {
              timer.cancel();
              remainingNotifier.dispose();
            });
          });
        }

        if (userModel.role == 'admin') {
          return const HomeScreen();
        }

        if (userModel.subscriptionFrozen == true) {
          return FrozenAccountScreen(username: userModel.name);
        }

        if (userModel.isSubscriptionActive || userModel.isTrialActive) {
          if (userModel.isTrialActive && _trialDialogShown.contains(user.uid)) {
            return Stack(
              children: [
                const HomeScreen(),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: TrialCountdownBanner(expiry: userModel.trialExpiry!),
                ),
              ],
            );
          }
          return const HomeScreen();
        }

        switch (userModel.status) {
          case 'approved':
            return const SubscriptionScreen();
          case 'pending':
          default:
            return const PendingApprovalScreen();
        }
      },
    );
  }
}
