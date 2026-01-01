import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_web_compat.dart';

class UserInboxScreen extends StatefulWidget {
  const UserInboxScreen({super.key});

  @override
  State<UserInboxScreen> createState() => _UserInboxScreenState();
}

class _UserInboxScreenState extends State<UserInboxScreen> {
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
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _setReadStatus(String docId, bool read) async {
    await FirebaseFirestore.instance.collection('user_messages').doc(docId).update({'read': read});
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Debes iniciar sesión para ver tus mensajes.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandeja de entrada'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: resilientStream(
          FirebaseFirestore.instance
              .collection('user_messages')
              .where('toUid', isEqualTo: user.uid)
              .orderBy('timestamp', descending: true)
              .snapshots(),
          name: 'user_inbox_stream',
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay mensajes.'));
          }
          final docs = snapshot.data!.docs;
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;
              final isRead = data['read'] == true;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['fromName'] ?? data['fromEmail'] ?? 'Remitente',
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!isRead)
                        const Icon(Icons.fiber_new, color: Colors.red, size: 18),
                    ],
                  ),
                  subtitle: Text(
                    (data['message'] ?? '').toString().length > 40
                        ? '${(data['message'] as String).substring(0, 40)}...'
                        : (data['message'] ?? ''),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          isRead ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: isRead ? Colors.green : Colors.grey,
                        ),
                        tooltip: isRead ? 'Marcado como leído' : 'Marcar como leído',
                        onPressed: () => _setReadStatus(docId, !isRead),
                      ),
                    ],
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(data['fromName'] ?? data['fromEmail'] ?? 'Remitente'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Mensaje completo:'),
                            const SizedBox(height: 4),
                            Text(data['message'] ?? ''),
                            if (data['timestamp'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text('Fecha: ${_formatTimestamp(data['timestamp'])}'),
                              ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            child: const Text('Cerrar'),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
