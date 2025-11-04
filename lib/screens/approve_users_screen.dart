import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/models/user_model.dart';

class ApproveUsersScreen extends StatelessWidget {
  const ApproveUsersScreen({super.key});

  Future<void> _updateUserStatus(BuildContext context, String uid, String status) async {
    final firestore = FirebaseFirestore.instance;
    // It's safer to capture the ScaffoldMessenger before the async gap.
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      Map<String, dynamic> dataToUpdate = {'status': status};

      if (status == 'approved') {
        final now = DateTime.now();
        final newSubscription = Subscription(
          startDate: now,
          endDate: DateTime(now.year + 1, now.month, now.day),
        );
        dataToUpdate['subscriptionHistory'] = [newSubscription.toMap()];
        dataToUpdate['approvedPoisCount'] = 0;
      }

      await firestore.collection('users').doc(uid).update(dataToUpdate);

      final successMessage = status == 'approved'
          ? 'Usuario aprobado con éxito.'
          : 'Usuario rechazado con éxito.';
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: status == 'approved' ? Colors.green : Colors.red,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error al actualizar el usuario: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprobar Usuarios'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('users')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay usuarios pendientes de aprobación.'));
          }

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userData = user.data() as Map<String, dynamic>;
              final userName = userData['name'] ??
                  userData['displayName'] ??
                  userData['email'] ??
                  'Usuario Desconocido';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  title: Text(userName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(userData['email'] ?? 'No se ha proporcionado correo electrónico'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _updateUserStatus(context, user.id, 'approved'),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Aprobar'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _updateUserStatus(context, user.id, 'rejected'),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Rechazar'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
