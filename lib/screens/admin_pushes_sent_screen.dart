import 'package:flutter/material.dart';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminPushesSentScreen extends StatelessWidget {
  const AdminPushesSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Debes iniciar sesión')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Enviados (push)')),
      body: FutureBuilder<HttpsCallableResult>(
        future: FirebaseFunctions.instance.httpsCallable('getAdminPushes').call(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final err = snapshot.error;
            return Center(child: Text('Error al cargar enviados: ${err ?? ''}'));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final result = snapshot.data!;
          final raw = result.data;

          // Normalize dynamic results (Map<dynamic,dynamic>) into Map<String,dynamic>
          final broadcasts = _normalizeList(raw?['systemNotifications']);
          final directs = _normalizeList(raw?['userMessages']);

          final items = <Map<String, dynamic>>[];
          for (var d in broadcasts) {
            items.add({
              'type': 'broadcast',
              'id': d['id'] ?? '',
              'timestamp': d['timestamp'],
              'message': d['message'] ?? d['body'] ?? '',
              'to': d['to'] ?? 'all',
            });
          }
          for (var d in directs) {
            items.add({
              'type': 'direct',
              'id': d['id'] ?? '',
              'timestamp': d['timestamp'],
              'message': d['message'] ?? d['body'] ?? '',
              'to': d['to'] ?? d['toUid'] ?? d['to'] ?? '',
              'toName': d['toName'] ?? d['toEmail'] ?? '',
            });
          }

          items.sort((a, b) {
            DateTime aDate = _toDate(a['timestamp']);
            DateTime bDate = _toDate(b['timestamp']);
            return bDate.compareTo(aDate);
          });

          if (items.isEmpty) return const Center(child: Text('No hay envíos registrados.'));

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final it = items[index];
              final type = it['type'] as String;
              final message = it['message'] as String;
              final to = it['to'];
              final id = it['id'] as String;

              return ListTile(
                leading: Icon(type == 'broadcast' ? Icons.campaign : Icons.send, color: type == 'broadcast' ? Colors.blue : Colors.green),
                title: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(type == 'broadcast' ? 'Público' : 'Directo · Para: ${it['toName'] ?? to}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.group),
                    tooltip: 'Ver destinatarios',
                    onPressed: () => _showRecipients(context, it),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Eliminar registro'),
                          content: const Text('¿Eliminar este registro de envío? No se eliminará el mensaje original en las colecciones de usuarios.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        try {
                          await FirebaseFirestore.instance.collection(type == 'broadcast' ? 'system_notifications' : 'user_messages').doc(id).delete();
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro eliminado')));
                        } catch (e) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      }
                    },
                  ),
                ]),
                onTap: () async {
                  // show message details
                  await showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(type == 'broadcast' ? 'Broadcast' : 'Mensaje directo'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message),
                          const SizedBox(height: 12),
                          Text('Fecha: ${_formatDate(it['timestamp'])}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static DateTime _toDate(dynamic ts) {
    if (ts == null) return DateTime.fromMillisecondsSinceEpoch(0);
    if (ts is Timestamp) return ts.toDate();
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
    return DateTime.tryParse(ts.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  // Normalize a dynamic list (from callable result) into List<Map<String,dynamic>>
  static List<Map<String, dynamic>> _normalizeList(dynamic input) {
    if (input == null) return <Map<String,dynamic>>[];
    if (input is List) {
      return input.map<Map<String,dynamic>>((e) {
        if (e is Map) {
          final out = <String,dynamic>{};
          e.forEach((k, v) {
            out[k?.toString() ?? ''] = v;
          });
          return out;
        }
        return <String,dynamic>{};
      }).toList();
    }
    return <Map<String,dynamic>>[];
  }

  static String _formatDate(dynamic ts) {
    final d = _toDate(ts);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  void _showRecipients(BuildContext context, Map<String, dynamic> item) async {
  final type = item['type'] as String;
  final id = item['id'] as String;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Destinatarios'),
          content: SizedBox(
            width: 400,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadRecipients(type, id),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
                if (snap.hasError) return Text('Error: ${snap.error}');
                final list = snap.data ?? [];
                if (list.isEmpty) return const Text('No se encontraron destinatarios');

                // compute read/total
                final total = list.length;
                final readCount = list.where((e) => e['read'] == true).length;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text('Leídos $readCount / $total', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final u = list[idx];
                          return ListTile(
                            leading: CircleAvatar(child: Text((u['name'] ?? 'U').toString().substring(0, 1).toUpperCase())),
                            title: Text(u['name'] ?? u['email'] ?? ''),
                            subtitle: Text(u['email'] ?? ''),
                            trailing: u['read'] == true ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadRecipients(String type, String id) async {
    final firestore = FirebaseFirestore.instance;
    try {
      final List<Map<String, dynamic>> out = [];
      if (type == 'direct') {
        final doc = await firestore.collection('user_messages').doc(id).get();
        if (!doc.exists) return [];
        final data = doc.data() as Map<String, dynamic>;
        final uid = data['to'] ?? data['toUid'];
        final userDoc = await firestore.collection('users').doc(uid).get();
        final userData = userDoc.data();
        out.add({'name': userData?['name'] ?? userData?['email'] ?? '', 'email': userData?['email'] ?? '', 'read': data['read'] == true});
        return out;
      }

      // broadcast: if 'to' == 'all', list all users and check readBy subcollection
      final notifDoc = await firestore.collection('system_notifications').doc(id).get();
      if (!notifDoc.exists) return [];
      final notifData = notifDoc.data() as Map<String, dynamic>;
      final to = notifData['to'] ?? 'all';

      if (to == 'all') {
        final usersSnap = await firestore.collection('users').get();
        for (var u in usersSnap.docs) {
          final udata = u.data();
          // Prefer per-user notification copy if exists
          final userNotifDoc = await firestore.collection('users').doc(u.id).collection('notifications').doc(id).get();
          bool read = false;
          if (userNotifDoc.exists) {
            final ndata = userNotifDoc.data() as Map<String, dynamic>;
            read = ndata['read'] == true;
          } else {
            // fallback to legacy readBy subcollection
            final readDoc = await firestore.collection('system_notifications').doc(id).collection('readBy').doc(u.id).get();
            read = readDoc.exists;
          }
          out.add({'name': udata['name'] ?? '', 'email': udata['email'] ?? '', 'read': read});
        }
        return out;
      }

      // if to is an array of uids
      if (to is List) {
        for (var uid in to) {
          final userDoc = await firestore.collection('users').doc(uid.toString()).get();
          final udata = userDoc.data();
          final userNotifDoc = await firestore.collection('users').doc(uid.toString()).collection('notifications').doc(id).get();
          bool read = false;
          if (userNotifDoc.exists) {
            final ndata = userNotifDoc.data() as Map<String, dynamic>;
            read = ndata['read'] == true;
          } else {
            final readDoc = await firestore.collection('system_notifications').doc(id).collection('readBy').doc(uid.toString()).get();
            read = readDoc.exists;
          }
          out.add({'name': udata?['name'] ?? '', 'email': udata?['email'] ?? '', 'read': read});
        }
        return out;
      }

      return out;
    } catch (e, s) {
      // Defensive: if permissions block any of these reads, log and return empty
      // recipients so the UI doesn't throw.
      developer.log('Failed to load recipients for push $id: $e', name: 'AdminPushes', error: e, stackTrace: s);
      return <Map<String, dynamic>>[];
    }
  }
}
