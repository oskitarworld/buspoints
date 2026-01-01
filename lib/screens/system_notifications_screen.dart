import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_web_compat.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SystemNotificationsScreen extends StatefulWidget {
  const SystemNotificationsScreen({super.key});

  @override
  State<SystemNotificationsScreen> createState() => _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState extends State<SystemNotificationsScreen> {
  String _formatTimestamp(dynamic ts) {
    try {
      DateTime date;
      if (ts is int) {
        date = DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      } else if (ts is Timestamp) {
        date = ts.toDate().toLocal();
      } else {
        return '';
      }
      return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _markAsRead(String docId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      // mark per-user read
      await FirebaseFirestore.instance.collection('system_notifications').doc(docId).collection('readBy').doc(currentUser.uid).set({'read': true, 'readAt': FieldValue.serverTimestamp()});
      // For non-broadcasts (to != 'all'), also mark parent doc read for compatibility
      final doc = await FirebaseFirestore.instance.collection('system_notifications').doc(docId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final to = data['to'] ?? 'all';
        if (to != 'all') {
          await FirebaseFirestore.instance.collection('system_notifications').doc(docId).update({'read': true});
        }
      }
    } catch (e) {
      // ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones del sistema')),
      body: StreamBuilder<QuerySnapshot>(
        stream: resilientStream(
          FirebaseFirestore.instance
              .collection('system_notifications')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          name: 'system_notifications_stream',
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No hay notificaciones del sistema.'));

          final docs = snapshot.data!.docs;
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final message = data['message'] ?? '';
              final fromName = data['fromName'] ?? 'Sistema';
              final isRead = data['read'] == true;

              return ListTile(
                title: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('$fromName · ${_formatTimestamp(data['timestamp'])}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  isRead ? const Icon(Icons.check, color: Colors.green) : const Icon(Icons.fiber_new, color: Colors.red),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Eliminar notificación',
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final confirm = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Confirmar'), content: const Text('¿Eliminar esta notificación?'), actions: [TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('No')), TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Sí'))]));
                      if (confirm == true) {
                        try {
                          await FirebaseFirestore.instance.collection('system_notifications').doc(doc.id).delete();
                          if (!mounted) return;
                          messenger.showSnackBar(const SnackBar(content: Text('Notificación eliminada'), backgroundColor: Colors.green));
                          setState(() {});
                        } catch (e) {
                          if (!mounted) return;
                          messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                        }
                      }
                    },
                  ),
                ]),
                onTap: () {
                  // Mark as read in background, don't await to avoid using
                  // BuildContext across async gaps.
                  _markAsRead(doc.id);
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(fromName),
                      content: Text(message),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
                      ],
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
}
