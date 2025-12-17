import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_inbox_screen.dart';
import 'manage_users_screen.dart';
import 'poi_approval_screen.dart';
import 'review_approval_screen.dart';
import 'user_approval_screen.dart';
import 'create_user_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        backgroundColor: Colors.red[800],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Image.asset(
                'assets/images/logo.png',
                height: 100,
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // (Bandeja de entrada accesible desde el menú lateral)
                // Aprobar Usuarios
                _buildButtonWithBadge(
                  context,
                  'Aprobar Usuarios',
                  const UserApprovalScreen(),
                  'users',
                  filterField: 'status',
                  filterValue: 'pending',
                ),
                const SizedBox(height: 16),
                // Gestionar Usuarios
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ManageUsersScreen()),
                      );
                    },
                    child: const Text('Gestionar Usuarios', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                // Crear Usuario (aprobado directamente)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateUserScreen()),
                      );
                    },
                    child: const Text('Crear Usuario', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                // Aprobar POIs
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PoiApprovalScreen()),
                      );
                    },
                    child: const Text('Aprobar Puntos de Interés', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 16),
                // Aprobar Reviews/Valoraciones con badge de pendientes
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collectionGroup('reviews')
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  builder: (context, snapshot) {
                    int pendingCount = 0;
                    if (snapshot.hasData) {
                      pendingCount = snapshot.data!.docs.length;
                    }
                    return Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ReviewApprovalScreen()),
                              );
                            },
                            child: const Text('Aprobar Comentarios/Valoraciones', style: TextStyle(fontSize: 16)),
                          ),
                        ),
                        if (pendingCount > 0)
                          Positioned(
                            top: -8,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                pendingCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInboxBadge(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contact_messages')
          .snapshots(),
      builder: (context, contactSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('user_messages')
              .snapshots(),
          builder: (context, userMessagesSnapshot) {
            int totalUnread = 0;
            
            // Contar mensajes sin leer de contact_messages
            if (contactSnapshot.hasData) {
              totalUnread += contactSnapshot.data!.docs
                  .where((doc) => (doc.data() as Map<String, dynamic>)['read'] != true)
                  .length;
            }
            
            // Contar mensajes sin leer de user_messages
            if (userMessagesSnapshot.hasData) {
              totalUnread += userMessagesSnapshot.data!.docs
                  .where((doc) => (doc.data() as Map<String, dynamic>)['read'] != true)
                  .length;
            }
            
            return Stack(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AdminInboxScreen()),
                      );
                    },
                    child: const Text('Bandeja de entrada', style: TextStyle(fontSize: 16)),
                  ),
                ),
                if (totalUnread > 0)
                  Positioned(
                    top: -10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        totalUnread.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildButtonWithBadge(
    BuildContext context,
    String label,
    Widget screen,
    String collection, {
    String? filterField,
    String? filterValue,
    bool Function(QueryDocumentSnapshot)? customFilter,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        int count = 0;
        if (snapshot.hasData) {
          if (customFilter != null) {
            count = snapshot.data!.docs.where(customFilter).length;
          } else if (filterField != null && filterValue != null) {
            count = snapshot.data!.docs
                .where((doc) => (doc.data() as Map<String, dynamic>)[filterField] == filterValue)
                .length;
          } else {
            count = snapshot.data!.docs.length;
          }
        }
        return Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => screen),
                  );
                },
                child: Text(label, style: const TextStyle(fontSize: 16)),
              ),
            ),
            if (count > 0)
              Positioned(
                top: -8,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
