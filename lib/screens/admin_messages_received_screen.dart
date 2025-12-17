import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminMessagesReceivedScreen extends StatelessWidget {
  const AdminMessagesReceivedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Debes iniciar sesión para ver tus mensajes.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes recibidos (admin)')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_messages')
            .where('toUid', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error al cargar mensajes.'));
          }
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No hay mensajes.'));
          docs.sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['timestamp'];
            final bTs = (b.data() as Map<String, dynamic>)['timestamp'];
            DateTime aDate = aTs is Timestamp ? aTs.toDate() : (aTs is int ? DateTime.fromMillisecondsSinceEpoch(aTs) : DateTime(1970));
            DateTime bDate = bTs is Timestamp ? bTs.toDate() : (bTs is int ? DateTime.fromMillisecondsSinceEpoch(bTs) : DateTime(1970));
            return bDate.compareTo(aDate);
          });
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final message = data['message'] ?? '';
              final truncated = message.length > 40 ? message.substring(0, 40) + '...' : message;
              final isUnread = data['read'] == false;
              return ListTile(
                leading: isUnread
                    ? Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
                title: Text(truncated),
                subtitle: Text('De: ${data['fromName'] ?? data['fromEmail'] ?? 'Usuario'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_formatTime(data['timestamp'])),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(isUnread ? Icons.mark_email_read : Icons.mark_email_unread, color: Colors.blue),
                      tooltip: isUnread ? 'Marcar como leído' : 'Marcar como no leído',
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('user_messages')
                            .doc(docs[index].id)
                            .update({'read': !isUnread});
                      },
                    ),
                  ],
                ),
                onTap: () {
                  if (isUnread) {
                    FirebaseFirestore.instance
                        .collection('user_messages')
                        .doc(docs[index].id)
                        .update({'read': true});
                  }
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('De: ${data['fromName'] ?? data['fromEmail'] ?? 'Usuario'}'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message),
                          const SizedBox(height: 12),
                          Text('Hora: ${_formatTime(data['timestamp'])}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
              );
            },
          );
        },
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is int) {
      date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      date = DateTime.tryParse(timestamp.toString()) ?? DateTime(1970);
    }
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
