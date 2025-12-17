// Clean single-definition AppDrawer

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:myapp/screens/profile_screen.dart';
import 'package:myapp/screens/home_screen.dart';
import 'package:myapp/screens/admin_panel_screen.dart';
import 'package:rxdart/rxdart.dart';
import 'package:myapp/screens/terms_of_use_screen.dart';
import 'package:myapp/screens/privacy_policy_screen.dart';
import 'package:myapp/screens/how_it_works_screen.dart';
import 'package:myapp/widgets/contact_dialog.dart';

import '../screens/user_messages_received_screen.dart';
import '../screens/user_messages_sent_screen.dart';
import '../screens/admin_inbox_screen.dart';
import '../screens/system_notifications_screen.dart';
import '../screens/admin_pushes_sent_screen.dart';
import '../screens/admin/security_events_screen.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {

  Widget _buildCountRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          const SizedBox(width: 8),
          Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final didRequestSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Cierre de Sesión'),
          content: const Text('¿Estás seguro de que quieres cerrar la sesión?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (didRequestSignOut == true) {
      await FirebaseAuth.instance.signOut();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthScreen(), settings: const RouteSettings(name: '/auth')),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _navigateToHome(BuildContext context) {
    Navigator.pop(context);
    if (ModalRoute.of(context)?.settings.name != '/home') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen(), settings: const RouteSettings(name: '/home')),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Drawer();
    }
    return Drawer(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          String? userName = user.email;
          String? role;
          if (snapshot.connectionState == ConnectionState.active && snapshot.hasData) {
            final data = snapshot.data?.data() as Map<String, dynamic>?;
            userName = data?['name'] ?? user.email;
            role = data?['role'];
          }
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(
                  userName ?? 'Cargando...',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                accountEmail: Text(user.email ?? ''),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    userName?.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold),
                  ),
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Mapa'),
                onTap: () => _navigateToHome(context),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Perfil'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  );
                },
              ),

              if (role == 'admin')
                Column(
                  children: [
                    StreamBuilder<List<int>>(
                      stream: Rx.combineLatest6<int, int, int, int, int, int, List<int>>(
                        FirebaseFirestore.instance
                          .collection('users')
                          .where('status', isEqualTo: 'pending')
                          .snapshots()
                          .map((snap) => snap.docs.length),
                        FirebaseFirestore.instance
                          .collection('contact_messages')
                          .where('read', isEqualTo: false)
                          .snapshots()
                          .map((snap) => snap.docs.length),
                        FirebaseFirestore.instance
                          .collection('user_messages')
                          .where('read', isEqualTo: false)
                          .snapshots()
                          .map((snap) => snap.docs.length),
                        FirebaseFirestore.instance
                          .collection('user_pois')
                          .where('status', isEqualTo: 'pending')
                          .snapshots()
                          .map((snap) => snap.docs.length),
                        FirebaseFirestore.instance
                          .collectionGroup('reviews')
                          .where('status', isEqualTo: 'pending')
                          .snapshots()
                          .map((snap) => snap.docs.length),
                        FirebaseFirestore.instance
                          .collection('system_notifications')
                          .where('read', isEqualTo: false)
                          .snapshots()
                          .map((snap) => snap.docs.length),
                        (pendingUsers, contactMessages, userMessages, pendingUserPois, pendingReviews, systemNotifications) => [pendingUsers, contactMessages, userMessages, pendingUserPois, pendingReviews, systemNotifications],
                      ),
                      builder: (context, snapshot) {
                        int pendingUsers = 0;
                        int contactMessages = 0;
                        int userMessages = 0;
                        int totalMessages = 0;
                        int pendingUserPois = 0;
                        int pendingReviews = 0;
                        int systemNotifications = 0;
                        if (snapshot.hasData && snapshot.data != null) {
                          pendingUsers = snapshot.data![0];
                          contactMessages = snapshot.data![1];
                          userMessages = snapshot.data![2];
                          pendingUserPois = snapshot.data![3];
                          pendingReviews = snapshot.data![4];
                          systemNotifications = snapshot.data![5];
                          totalMessages = contactMessages + userMessages;
                        }
                        final totalPending = pendingUsers + totalMessages + pendingUserPois + pendingReviews + systemNotifications;
                        final showBadge = totalPending > 0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                          leading: const Icon(Icons.admin_panel_settings),
                          title: Row(
                            children: [
                              const Text('Panel de administración'),
                              if (showBadge)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    totalPending.toString(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            // Show breakdown dialog so admins can see which counts contribute to the badge
                            showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Resumen de pendientes'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildCountRow('Usuarios pendientes', pendingUsers),
                                    _buildCountRow('Mensajes de contacto (no leídos)', contactMessages),
                                    _buildCountRow('Mensajes de usuarios (no leídos)', userMessages),
                                    _buildCountRow('POIs pendientes', pendingUserPois),
                                    _buildCountRow('Reviews pendientes', pendingReviews),
                                    _buildCountRow('Notificaciones del sistema (no leídas)', systemNotifications),
                                    const SizedBox(height: 8),
                                    Text('Total: $totalPending', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      Navigator.pop(context);
                                      Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPanelScreen()));
                                    },
                                    child: const Text('Abrir panel'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                            // Link directo a cuentas bloqueadas / eventos de seguridad
                            ListTile(
                              leading: const Icon(Icons.block, color: Colors.redAccent),
                              title: const Text('Cuentas bloqueadas / Seguridad'),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const SecurityEventsScreen()));
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    ExpansionTile(
                      leading: const Icon(Icons.mail),
                      title: const Text('Mensajes'),
                      children: [
                        ListTile(
                          leading: const Icon(Icons.inbox),
                          title: const Text('Bandeja de entrada'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const AdminInboxScreen()),
                            );
                          },
                        ),
                        // Reordered per request: Mensajes enviados, Enviados (push), Notificaciones del sistema
                        ListTile(
                          leading: const Icon(Icons.send),
                          title: const Text('Mensajes enviados'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const UserMessagesSentScreen()),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.campaign_outlined),
                          title: const Text('Enviados (push)'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const AdminPushesSentScreen()),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.notifications),
                          title: const Text('Notificaciones del sistema'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SystemNotificationsScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                )
              else ...[
                const Divider(),
                    StreamBuilder<List<int>>(
                  stream: Rx.combineLatest3<int, int, int, List<int>>(
                    FirebaseFirestore.instance
                      .collection('user_messages')
                      .where('toUid', isEqualTo: user.uid)
                      .where('read', isEqualTo: false)
                      .snapshots()
                      .map((snap) => snap.docs.length),
                    FirebaseFirestore.instance
                      .collection('user_pois')
                      .where('submittedBy', isEqualTo: user.uid)
                      .where('status', isEqualTo: 'pending')
                      .snapshots()
                      .map((snap) => snap.docs.length),
                    FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .collection('notifications')
                      .where('read', isEqualTo: false)
                      .snapshots()
                      .map((snap) => snap.docs.length),
                    (unreadCount, myPendingPois, unreadSystem) => [unreadCount, myPendingPois, unreadSystem],
                  ),
                  builder: (context, snapshot) {
                    int unreadCount = 0;
                    int myPendingPois = 0;
                    int unreadSystem = 0;
                    if (snapshot.hasData && snapshot.data != null) {
                      unreadCount = snapshot.data![0];
                      myPendingPois = snapshot.data![1];
                      unreadSystem = snapshot.data![2];
                    }
                    final userTotal = unreadCount + myPendingPois + unreadSystem;
                    return ExpansionTile(
                      leading: const Icon(Icons.mail),
                      title: Row(
                        children: [
                          const Text('Mensajes'),
                          if (userTotal > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                userTotal.toString(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                      children: [
                        ListTile(
                          leading: const Icon(Icons.inbox),
                          title: const Text('Recibidos'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const UserMessagesReceivedScreen(),
                              ),
                            );
                          },
                        ),
                        // For regular users keep order: Recibidos, Enviados, Notificaciones
                        ListTile(
                          leading: const Icon(Icons.send),
                          title: const Text('Enviados'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const UserMessagesSentScreen(),
                              ),
                            );
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.notifications),
                          title: const Text('Notificaciones del sistema'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SystemNotificationsScreen()),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                // Botón para contactar con administradores
                ListTile(
                  leading: const Icon(Icons.mail_outline, color: Colors.blue),
                  title: const Text('Contactar con Administradores'),
                  subtitle: const Text('Envía un mensaje al equipo', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    showContactDialog(context);
                  },
                ),
                // Bloque de información legal
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Términos de Uso'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TermsOfUseScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Política de Privacidad'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline, color: Colors.blueGrey),
                  title: const Text('¿Cómo funciona?'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HowItWorksScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.recommend_outlined),
                  title: const Text('Recomiéndanos'),
                  onTap: () {},
                ),
              ],
              const Divider(),
              // Small branded row: logo at left (height = two lines of text) and version + byline at right
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: 28, // approx height for two lines of small text
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'v1.0.2',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'by OskitarWorld',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                onTap: () => _confirmSignOut(context),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 10),
            ],
          );
        },
      ),
    );
  }

}
