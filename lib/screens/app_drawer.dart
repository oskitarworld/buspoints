import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_messages_screen.dart';
import 'admin_panel_screen.dart';


class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const ListTile(
            title: Text('Drawer activo', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.blue),
            accountName: FutureBuilder<DocumentSnapshot>(
              future: user != null ? FirebaseFirestore.instance.collection('users').doc(user.uid).get() : null,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                if (snapshot.hasData && snapshot.data != null) {
                  final doc = snapshot.data as DocumentSnapshot;
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data != null && (data['isAdmin'] == true || data['role'] == 'admin')) {
                    return const Text('Administrador', style: TextStyle(color: Colors.white));
                  } else {
                    return const Text('Usuario', style: TextStyle(color: Colors.white));
                  }
                }
                return const Text('Usuario', style: TextStyle(color: Colors.white));
              },
            ),
            accountEmail: Text(user?.email ?? '', style: const TextStyle(color: Colors.white)),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Colors.blue, size: 40),
            ),
          ),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Mis mensajes enviados'),
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const UserMessagesScreen(),
                ));
              },
            ),
          if (user != null)
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Hacerte administrador'),
              onTap: () async {
                final uid = user.uid;
                await FirebaseFirestore.instance.collection('users').doc(uid).set({
                  'isAdmin': true,
                }, SetOptions(merge: true));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('¡Ahora eres administrador!')),
                );
              },
            ),
          if (user != null)
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox.shrink();
                }
                if (snapshot.hasData && snapshot.data != null) {
                  final doc = snapshot.data as DocumentSnapshot;
                  final data = doc.data() as Map<String, dynamic>?;
                  debugPrint('=== Drawer user data ===');
                  debugPrint(data?.toString() ?? 'No data');
                  if (data != null && (data['isAdmin'] == true || data['role'] == 'admin')) {
                    return ListTile(
                      leading: const Icon(Icons.admin_panel_settings),
                      title: const Text('Panel de administración'),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) => const AdminPanelScreen(),
                        ));
                      },
                    );
                  }
                }
                return const SizedBox.shrink();
              },
            ),
                const Divider(),
                if (user != null)
                  ListTile(
                    leading: const Icon(Icons.exit_to_app),
                    title: const Text('Cerrar sesión'),
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                  ),
          // ...otros items del menú...
        ],
      ),
    );
  }
}
