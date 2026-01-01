import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SecurityEventsScreen extends StatefulWidget {
  const SecurityEventsScreen({super.key});

  @override
  State<SecurityEventsScreen> createState() => _SecurityEventsScreenState();
}

class _SecurityEventsScreenState extends State<SecurityEventsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _reactivateUser(String uid) async {
    final docRef = _firestore.collection('users').doc(uid);
    await docRef.update({
      'status': 'approved',
      'suspiciousAttempts': 0,
      'cancellationReason': FieldValue.delete(),
      'cancelledAt': FieldValue.delete(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad — Usuarios con alertas')),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Error cargando datos'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          // Filter locally: users with suspiciousAttempts > 0 or cancelled status
          final items = docs.where((d) {
            final data = d.data() as Map<String, dynamic>? ?? {};
            final attempts = (data['suspiciousAttempts'] as num?)?.toInt() ?? 0;
            final status = (data['status'] as String?) ?? '';
            return attempts > 0 || status.toLowerCase() == 'cancelled';
          }).toList();

          if (items.isEmpty) {
            return const Center(child: Text('No hay usuarios con alertas de seguridad.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final d = items[index];
              final data = d.data() as Map<String, dynamic>? ?? {};
              final attempts = (data['suspiciousAttempts'] as num?)?.toInt() ?? 0;
              final status = (data['status'] as String?) ?? '';
              final name = (data['name'] as String?) ?? data['email'] ?? d.id;
              final email = (data['email'] as String?) ?? '';

              return ListTile(
                title: Text(name),
                subtitle: Text(email.isNotEmpty ? '$email • Intentos: $attempts' : 'Intentos: $attempts'),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(status, style: TextStyle(color: status.toLowerCase() == 'cancelled' ? Colors.red : Colors.orange)),
                    const SizedBox(height: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      onPressed: status.toLowerCase() == 'cancelled' || attempts > 0
                          ? () async {
                              final nav = Navigator.of(context);
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Confirmar reactivación'),
                                  content: Text('¿Deseas reactivar la cuenta de $name? Esto restablecerá los intentos sospechosos.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                                    ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reactivar')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                try {
                                  await _reactivateUser(d.id);
                                  if (!mounted) return;
                                  messenger.showSnackBar(const SnackBar(content: Text('Cuenta reactivada')));
                                } catch (e) {
                                  if (!mounted) return;
                                  showDialog(context: nav.context, builder: (c) => AlertDialog(title: const Text('Error'), content: Text('No se pudo reactivar: $e')));
                                }
                              }
                            }
                          : null,
                      child: const Text('Reactivar', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
