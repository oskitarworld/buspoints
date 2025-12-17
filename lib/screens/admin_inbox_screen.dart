import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminInboxScreen extends StatefulWidget {
  const AdminInboxScreen({super.key});

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
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

  final String _search = '';

  Future<void> _setReadStatus(String docId, bool read,
      {bool isUserMessage = false}) async {
    try {
      if (isUserMessage) {
        await FirebaseFirestore.instance
            .collection('user_messages')
            .doc(docId)
            .update({'read': read});
      } else {
        await FirebaseFirestore.instance
            .collection('contact_messages')
            .doc(docId)
            .update({'read': read});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showMessageDialog(
    BuildContext context,
    String senderName,
    String senderEmail,
    String message,
    dynamic timestamp,
    String docId,
    bool isRead,
    bool isUserMessage,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue[50]!, Colors.blue[100]!],
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header con gradiente azul
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue[600]!, Colors.blue[400]!],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          child: Text(
                            senderName.isNotEmpty
                                ? senderName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                senderName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                senderEmail,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                  ),
                  // Contenido del mensaje
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.6,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Text(
                                  _formatTimestamp(timestamp),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botones
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Cerrar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              foregroundColor: Colors.grey[700],
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // Auto-marcar como leído
    if (!isRead) {
      _setReadStatus(docId, true, isUserMessage: isUserMessage);
    }
  }

  Future<void> _showReplyDialog(BuildContext context, String recipientName,
      String recipientEmail, String originalMessage) async {
    final TextEditingController replyController = TextEditingController();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final adminEmail = currentUser.email ?? '';
    final adminName = currentUser.displayName ?? 'Admin';

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.green[50]!, Colors.green[100]!],
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green[600]!, Colors.green[400]!],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          child: Text(
                            recipientName.isNotEmpty
                                ? recipientName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                recipientName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                recipientEmail,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                  ),
                  // Contenido
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (originalMessage.isNotEmpty) ...[
                          Text(
                            'Mensaje original',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              originalMessage,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        Text(
                          'Tu respuesta',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: replyController,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: 'Escribe tu respuesta aquí...',
                              hintStyle: TextStyle(
                                color: Colors.grey[400],
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.all(16),
                            ),
                            maxLines: 5,
                            maxLength: 500,
                            buildCounter: (context,
                                {required currentLength,
                                required isFocused,
                                maxLength}) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '$currentLength/$maxLength',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botones
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Cancelar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              foregroundColor: Colors.grey[700],
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (replyController.text.trim().isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✋ Por favor escribe un mensaje'),
                                      backgroundColor: Colors.orange,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                                return;
                              }

                              try {
                                final userQuery = await FirebaseFirestore.instance
                                    .collection('users')
                                    .where('email', isEqualTo: recipientEmail)
                                    .limit(1)
                                    .get();

                                if (userQuery.docs.isEmpty) {
                                  throw Exception(
                                      'No se encontró el usuario destinatario');
                                }

                                final recipientUid = userQuery.docs.first.id;

                                await FirebaseFirestore.instance
                                    .collection('user_messages')
                                    .add({
                                  'fromUid': currentUser.uid,
                                  'toUid': recipientUid,
                                  'fromName': adminName,
                                  'fromEmail': adminEmail,
                                  'toName': recipientName,
                                  'toEmail': recipientEmail,
                                  'message': replyController.text.trim(),
                                  'timestamp': FieldValue.serverTimestamp(),
                                  // mark as unread for the recipient so it appears in their inbox
                                  'read': false,
                                  'fromAdmin': true,
                                  'isReply': true,
                                  'originalMessage': originalMessage,
                                });

                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✅ ¡Mensaje enviado!'),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  setState(() {});
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('❌ Error: $e'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: const Text('Enviar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandeja de entrada'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('contact_messages')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, contactSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('user_messages')
                .where('isContact', isNotEqualTo: true)
                .orderBy('isContact')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, userMessagesSnapshot) {
              if (contactSnapshot.connectionState == ConnectionState.waiting ||
                  userMessagesSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              List<QueryDocumentSnapshot> allDocs = [];
              Set<String> userMessageIds = {};

              if (contactSnapshot.hasData) {
                allDocs.addAll(contactSnapshot.data!.docs.where((doc) => doc.exists && doc.data() != null));
              }
              if (userMessagesSnapshot.hasData) {
                final userMsgDocs = userMessagesSnapshot.data!.docs
                    .where((doc) => doc.exists && doc.data() != null)
                    .toList();
                for (var doc in userMsgDocs) {
                  userMessageIds.add(doc.id);
                }
                allDocs.addAll(userMsgDocs);
              }

              if (allDocs.isEmpty) {
                return const Center(child: Text('No hay mensajes.'));
              }

              final docs = allDocs.where((doc) {
                if (!doc.exists || doc.data() == null) return false;
                final data = doc.data() as Map<String, dynamic>;
                
                // Filtrar por búsqueda
                final name = (data['name'] ?? data['senderName'] ?? data['fromName'] ?? '')
                    .toString()
                    .toLowerCase();
                final email = (data['email'] ?? data['senderEmail'] ?? '').toString().toLowerCase();
                final searchMatch = _search.isEmpty || name.contains(_search) || email.contains(_search);
                
                return searchMatch;
              }).toList();

              // Agrupar por usuario
              Map<String, List<QueryDocumentSnapshot>> messagesByUser = {};
              for (var doc in docs) {
                final data = doc.data() as Map<String, dynamic>;
                final isUserMessage = userMessageIds.contains(doc.id);

                String userEmail = '';

                if (isUserMessage && data['fromAdmin'] == true) {
                  userEmail = data['toEmail'] ?? '';
                } else {
                  userEmail = data['email'] ?? data['senderEmail'] ?? data['fromEmail'] ?? '';
                }

                if (userEmail.isNotEmpty) {
                  messagesByUser.putIfAbsent(userEmail, () => []).add(doc);
                }
              }

              final usersList = messagesByUser.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

              return ListView.builder(
                itemCount: usersList.length,
                itemBuilder: (context, index) {
                  final userEmail = usersList[index].key;
                  final userMessages = usersList[index].value;
                  final unreadCount = userMessages
                      .where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        // No contar como "no leído" si el admin fue quien lo envió
                        return data['read'] != true && data['fromAdmin'] != true;
                      })
                      .length;
                  final firstMsg = userMessages.first.data() as Map<String, dynamic>;
                  final isUserMessage = userMessageIds.contains(userMessages.first.id);
                  final userName = isUserMessage && firstMsg['fromAdmin'] == true
                      ? (firstMsg['toName'] ?? firstMsg['toEmail'] ?? 'Sin nombre')
                      : (firstMsg['name'] ?? firstMsg['fromName'] ?? firstMsg['senderName'] ?? 'Sin nombre');

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ExpansionTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(userEmail, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                              ],
                            ),
                          ),
                          if (unreadCount > 0)
                            Badge(
                              label: Text('$unreadCount'),
                              backgroundColor: Colors.red,
                              textColor: Colors.white,
                            ),
                        ],
                      ),
                      subtitle: Text('${userMessages.length} mensaje${userMessages.length > 1 ? 's' : ''}',
                          style: TextStyle(color: Colors.grey[500])),
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: userMessages.length,
                          itemBuilder: (context, msgIndex) {
                            final doc = userMessages[msgIndex];
                            final data = doc.data() as Map<String, dynamic>;
                            final docId = doc.id;
                            final isRead = data['read'] == true;
                            final isUserMessage = userMessageIds.contains(docId);

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: Icon(
                                isUserMessage && data['fromAdmin'] == true ? Icons.send : Icons.mail,
                                color: isUserMessage && data['fromAdmin'] == true ? Colors.green : Colors.blue,
                              ),
                              title: Text(
                                (data['message'] ?? '').toString().length > 50
                                    ? '${(data['message'] as String).substring(0, 50)}...'
                                    : (data['message'] ?? ''),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(_formatTimestamp(data['timestamp']),
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.reply, color: Colors.blue),
                                    iconSize: 20,
                                    onPressed: () {
                                      _showReplyDialog(context, userName, userEmail, data['message'] ?? '');
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      isRead ? Icons.check_circle : Icons.radio_button_unchecked,
                                      color: isRead ? Colors.green : Colors.grey,
                                    ),
                                    iconSize: 20,
                                    onPressed: () async {
                                      await _setReadStatus(docId, !isRead, isUserMessage: isUserMessage);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    iconSize: 20,
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Eliminar'),
                                          content: const Text('¿Eliminar mensaje?'),
                                          actions: [
                                            TextButton(child: const Text('No'), onPressed: () => Navigator.pop(ctx, false)),
                                            TextButton(child: const Text('Sí'), onPressed: () => Navigator.pop(ctx, true)),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        try {
                                          final currentUser = FirebaseAuth.instance.currentUser;
                                          if (currentUser == null) return;

                                          await FirebaseFirestore.instance.runTransaction((transaction) async {
                                            final docRef = isUserMessage
                                                ? FirebaseFirestore.instance.collection('user_messages').doc(docId)
                                                : FirebaseFirestore.instance.collection('contact_messages').doc(docId);
                                            final snapshot = await transaction.get(docRef);
                                            if (!snapshot.exists) throw Exception('No existe');
                                            transaction.delete(docRef);
                                          });
                                          if (mounted) setState(() {});
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                final senderName = isUserMessage && data['fromAdmin'] == true
                                    ? (data['toName'] ?? data['toEmail'] ?? 'Sin nombre')
                                    : (data['name'] ?? data['fromName'] ?? data['senderName'] ?? 'Sin nombre');
                                final senderEmail = isUserMessage && data['fromAdmin'] == true
                                    ? (data['toEmail'] ?? '')
                                    : (data['email'] ?? data['senderEmail'] ?? data['fromEmail'] ?? '');
                                _showMessageDialog(
                                  context,
                                  senderName,
                                  senderEmail,
                                  data['message'] ?? '',
                                  data['timestamp'],
                                  docId,
                                  isRead,
                                  isUserMessage,
                                );
                              },
                            );
                          },
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
}
