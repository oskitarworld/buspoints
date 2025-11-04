import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:myapp/widgets/contact_dialog.dart';

import 'package:myapp/screens/profile_screen.dart';
import 'package:myapp/screens/admin_screen.dart';
import 'package:myapp/screens/home_screen.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

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
              onPressed: () => Navigator.of(context).pop(false), // User does not want to sign out
            ),
            TextButton(
              child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true), // User confirms sign out
            ),
          ],
        );
      },
    );

    // If the user confirmed, proceed with sign-out
    if (didRequestSignOut == true) {
      await FirebaseAuth.instance.signOut();
      // Use the captured navigator to avoid using context across async gaps.
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthScreen(), settings: const RouteSettings(name: '/auth')),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _navigateToHome(BuildContext context) {
    Navigator.pop(context); // Close the drawer
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
      // This is a fallback for the brief moment after sign-out before navigation occurs.
      return const Drawer();
    }

    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                  builder: (context, snapshot) {
                    String? userName = user.email; // Default to email

                    if (snapshot.connectionState == ConnectionState.active && snapshot.hasData) {
                      final data = snapshot.data?.data() as Map<String, dynamic>?;
                      userName = data?['name'] ?? user.email;
                    }

                    return UserAccountsDrawerHeader(
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
                    );
                  },
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
                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.active && snapshot.hasData) {
                      final data = snapshot.data?.data() as Map<String, dynamic>?;
                      final role = data?['role'];
                      if (role == 'admin') {
                        return ListTile(
                          leading: const Icon(Icons.admin_panel_settings),
                          title: const Text('Panel de Administrador'),
                          onTap: () {
                            Navigator.pop(context);
                            if (ModalRoute.of(context)?.settings.name != '/admin') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AdminScreen(),
                                  settings: const RouteSettings(name: '/admin'),
                                ),
                              );
                            }
                          },
                        );
                      }
                    }
                    return const SizedBox.shrink(); // Return empty space if not admin or loading
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.contact_mail),
                  title: const Text('Contacto'),
                  onTap: () {
                    Navigator.pop(context);
                    showContactDialog(context);
                  },
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Image.asset(
              'assets/images/logo.png',
              height: 100,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.exit_to_app, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
            onTap: () => _confirmSignOut(context),
          ),
          const SizedBox(height: 10), // Padding at the bottom
        ],
      ),
    );
  }
}
