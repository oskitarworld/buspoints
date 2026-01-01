import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/widgets/firestore_error_widget.dart';

class UserMessagesReceivedScreen extends StatefulWidget {
  const UserMessagesReceivedScreen({super.key});

  @override
  State<UserMessagesReceivedScreen> createState() =>
      _UserMessagesReceivedScreenState();
}

class _UserMessagesReceivedScreenState
    extends State<UserMessagesReceivedScreen> {
  late Future<List<QueryDocumentSnapshot>> _messagesFuture;
  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _messagesFuture = _loadMessages();
  }

  Future<List<QueryDocumentSnapshot>> _loadMessages() async {
    if (user == null) return [];

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('user_messages')
          .get();

      var docs = snapshot.docs
          .where((doc) => (doc.data())['toUid'] == user!.uid)
          .toList();

      // Ordenar por timestamp descendente
      docs.sort((a, b) {
        final aTs = (a.data())['timestamp'];
        final bTs = (b.data())['timestamp'];
        DateTime aDate = aTs is Timestamp
            ? aTs.toDate()
            : (aTs is int
                ? DateTime.fromMillisecondsSinceEpoch(aTs)
                : DateTime(1970));
        DateTime bDate = bTs is Timestamp
            ? bTs.toDate()
            : (bTs is int
                ? DateTime.fromMillisecondsSinceEpoch(bTs)
                : DateTime(1970));
        return bDate.compareTo(aDate);
      });

      return docs;
    } catch (e) {
      rethrow;
    }
  }

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
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _setReadStatus(String docId, bool read) async {
    try {
      await FirebaseFirestore.instance
          .collection('user_messages')
          .doc(docId)
          .update({'read': read});
      if (!mounted) return;
      setState(() {
        _messagesFuture = _loadMessages();
      });
    } catch (e) {
      // No UI interaction here (background operation). Log the error instead.
      debugPrint('Error setting read status: $e');
    }
  }

  Future<void> _deleteMessage(String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar mensaje'),
        content: const Text('¿Estás seguro de que quieres eliminar este mensaje?'),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          TextButton(
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('user_messages')
            .doc(docId)
            .delete();
        if (mounted) {
          setState(() {
            _messagesFuture = _loadMessages();
          });
        }
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ Mensaje eliminado'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showMessageDialog(
    String docId,
    String senderName,
    String message,
    bool isRead,
    dynamic timestamp,
    String fromUid,
  ) {
    // Marcar como leído sin esperar
    if (!isRead) {
      _setReadStatus(docId, true);
    }

    final TextEditingController replyController = TextEditingController();
    final currentUser = FirebaseAuth.instance.currentUser;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Mensaje de $senderName'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'De: $senderName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      message,
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hora: ${_formatTimestamp(timestamp)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: replyController,
                decoration: const InputDecoration(
                  labelText: 'Tu respuesta',
                  border: OutlineInputBorder(),
                  hintText: 'Escribe tu respuesta aquí...',
                ),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cerrar'),
            onPressed: () => Navigator.pop(ctx),
          ),
          TextButton(
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
            onPressed: () {
              Navigator.pop(ctx);
              _deleteMessage(docId);
            },
          ),
          ElevatedButton(
            onPressed: () async {
              if (replyController.text.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor escribe una respuesta'),
                    ),
                  );
                }
                return;
              }

              final dialogNavigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);

              try {
                await FirebaseFirestore.instance
                    .collection('user_messages')
                    .add({
                  'fromUid': currentUser?.uid,
                  'fromName': currentUser?.displayName ?? 'Usuario',
                  'fromAdmin': false,
                  'toUid': fromUid,
                  'toName': senderName,
                  'message': replyController.text,
                  'read': false,
                  'timestamp': FieldValue.serverTimestamp(),
                });

                dialogNavigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('✅ Respuesta enviada'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Responder'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Debes iniciar sesión para ver tus mensajes.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensajes recibidos'),
      ),
      body: FutureBuilder<List<QueryDocumentSnapshot>>(
        future: _messagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Cargando mensajes...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Expanded(child: firestoreErrorWidget(context, snapshot.error)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _messagesFuture = _loadMessages();
                    });
                  },
                  child: const Text('Reintentar'),
                ),
              ],
            );
          }

          final docs = snapshot.data ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('No hay mensajes recibidos.'));
          }

          final unreadCount = docs
              .where((doc) => (doc.data() as Map<String, dynamic>)['read'] != true)
              .length;

          return Column(
            children: [
              if (unreadCount > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha((0.1 * 255).round()),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withAlpha((0.3 * 255).round())),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mark_email_unread,
                          color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$unreadCount ${unreadCount == 1 ? "mensaje nuevo" : "mensajes nuevos"}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final docId = doc.id;
                    final isRead = data['read'] == true;
                    final senderName = data['senderName'] ?? data['fromName'] ?? 'Admin';
                    final message = data['message'] ?? '';
                    final timestamp = data['timestamp'];
                    final fromUid = data['fromUid'] ?? '';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      elevation: isRead ? 1 : 3,
                      color: isRead ? null : Colors.blue.withAlpha((0.05 * 255).round()),
                      child: InkWell(
                        onTap: () => _showMessageDialog(
                          docId,
                          senderName,
                          message,
                          isRead,
                          timestamp,
                          fromUid,
                        ),
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor:
                                isRead ? Colors.grey[300] : Colors.blue[100],
                            child: Icon(
                              Icons.person,
                              color: isRead ? Colors.grey[600] : Colors.blue[700],
                            ),
                          ),
                          title: Text(
                            senderName,
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                message.length > 60
                                    ? '${message.substring(0, 60)}...'
                                    : message,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[700],
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatTimestamp(timestamp),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  isRead
                                      ? Icons.mark_email_unread
                                      : Icons.mark_email_read,
                                  size: 20,
                                  color: Colors.blue,
                                ),
                                tooltip: isRead
                                    ? 'Marcar como no leído'
                                    : 'Marcar como leído',
                                onPressed: () async {
                                  await _setReadStatus(docId, !isRead);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    size: 20, color: Colors.red),
                                tooltip: 'Eliminar',
                                onPressed: () => _deleteMessage(docId),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
