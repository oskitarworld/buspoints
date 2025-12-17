import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
        stream: FirebaseFirestore.instance
            .collection('system_notifications')
            .orderBy('timestamp', descending: true)
            .snapshots(),
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
                subtitle: Text('${fromName} · ${_formatTimestamp(data['timestamp'])}'),
                trailing: isRead ? const Icon(Icons.check, color: Colors.green) : const Icon(Icons.fiber_new, color: Colors.red),
                onTap: () async {
                  await _markAsRead(doc.id);
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
