import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class UserApprovalScreen extends StatelessWidget {
  const UserApprovalScreen({super.key});

  Future<void> _approveUser(BuildContext context, String uid, String email) async {
    try {
      final now = DateTime.now();
      final subscriptionEndDate = now.add(const Duration(days: 365));
      
      // Crear objeto Subscription
      final newSubscription = Subscription(
        startDate: now,
        endDate: subscriptionEndDate,
      );
      
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'status': 'approved',
        'approvedAt': FieldValue.serverTimestamp(),
        // Add both explicit start/end fields and append to subscriptionHistory.
        'subscriptionStart': Timestamp.fromDate(now),
        'subscriptionEnd': Timestamp.fromDate(subscriptionEndDate),
        // Also set alternate timestamp keys used elsewhere for compatibility
        'subscriptionStartDate': Timestamp.fromDate(now),
        'subscriptionEndDate': Timestamp.fromDate(subscriptionEndDate),
        'subscriptionHistory': FieldValue.arrayUnion([newSubscription.toMap()]),
        'subscriptionActive': true,
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Usuario $email aprobado. Suscripción válida hasta $subscriptionEndDate')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al aprobar usuario: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectUser(BuildContext context, String uid, String email) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Usuario $email rechazado y eliminado')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al rechazar usuario: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprobar Usuarios'),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('Sin datos'));
          }

          // Filtrar usuarios con status 'pending'
          final allUsers = snapshot.data!.docs;
          
          final users = allUsers.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final status = data['status'];
            return status == 'pending';
          }).toList();
          
          if (users.isEmpty) {
            return const Center(
              child: Text('No hay usuarios pendientes de aprobación'),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final userDoc = users[index];
              final data = userDoc.data() as Map<String, dynamic>;
              final uid = userDoc.id;
              final name = data['name'] ?? 'Sin nombre';
              final email = data['email'] ?? 'Sin email';
              final phone = data['phone'] ?? 'Sin teléfono';
              final createdAt = data['createdAt'] as Timestamp?;
              final createdDate = createdAt?.toDate() ?? DateTime.now();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text('Email: $email', style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Text('Teléfono: $phone', style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        'Registrado: ${createdDate.day}/${createdDate.month}/${createdDate.year}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.close),
                            label: const Text('Rechazar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _showConfirmDialog(
                              context,
                              '¿Rechazar a $name?',
                              'Este usuario será eliminado',
                              () => _rejectUser(context, uid, email),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Aprobar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _showConfirmDialog(
                              context,
                              '¿Aprobar a $name?',
                              'Se le asignará una suscripción de 1 año',
                              () => _approveUser(context, uid, email),
                            ),
                          ),
                        ],
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

  void _showConfirmDialog(
    BuildContext context,
    String title,
    String message,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }
}
