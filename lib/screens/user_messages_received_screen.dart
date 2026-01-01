import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/widgets/firestore_error_widget.dart';
import 'package:myapp/services/firestore_web_compat.dart';

class UserMessagesReceivedScreen extends StatefulWidget {
  const UserMessagesReceivedScreen({super.key});

  @override
  State<UserMessagesReceivedScreen> createState() =>
      _UserMessagesReceivedScreenState();
}

class _UserMessagesReceivedScreenState
    extends State<UserMessagesReceivedScreen> {
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

  void _setReadStatus(String docId, bool read) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    FirebaseFirestore.instance
        .collection('user_messages')
        .doc(docId)
        .update({'read': read})
        .catchError((e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    });
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
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) return;

        // Soft-delete for recipient: mark deletedByRecipient so the sender/admin
        // copies remain intact.
        await FirebaseFirestore.instance.collection('user_messages').doc(docId).update({
          'deletedByRecipient': currentUser.uid,
          'deletedByRecipientAt': FieldValue.serverTimestamp(),
        });

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
    String senderEmail,
  ) {
    // Marcar como leído en background sin esperar
    if (!isRead) {
      _setReadStatus(docId, true);
    }

    final TextEditingController replyController = TextEditingController();
    final currentUser = FirebaseAuth.instance.currentUser;

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
                  // Header con avatar y nombre
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
                          backgroundColor: Colors.white.withAlpha((0.3 * 255).round()),
                          child: Text(
                            senderName.isNotEmpty
                                ? senderName[0].toUpperCase()
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
                                senderName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: Colors.white.withAlpha((0.8 * 255).round()),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatTimestamp(timestamp),
                                    style: TextStyle(
                                      color: Colors.white.withAlpha((0.9 * 255).round()),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
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
                  // Contenido del mensaje
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha((0.08 * 255).round()),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            message,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Campo de respuesta
                        Text(
                          'Tu respuesta',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[700],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha((0.08 * 255).round()),
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
                            maxLines: 4,
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
                  // Botones de acción
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        // Botón Eliminar
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(dialogContext);
                              _deleteMessage(docId);
                            },
                            icon: const Icon(Icons.delete_outline, size: 18),
                            label: const Text('Eliminar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[100],
                              foregroundColor: Colors.red[700],
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Botón Responder
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (replyController.text.trim().isEmpty) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '✋ Por favor escribe una respuesta',
                                      ),
                                      backgroundColor: Colors.orange,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                                return;
                              }

                              final dialogNavigator = Navigator.of(dialogContext);
                              final messenger = ScaffoldMessenger.of(context);

                              try {
                                await FirebaseFirestore.instance
                                    .collection('user_messages')
                                    .add({
                                  'fromUid': currentUser?.uid,
                                  'fromName':
                                      currentUser?.displayName ?? 'Usuario',
                                  'fromEmail': currentUser?.email ?? '',
                                  'fromAdmin': false,
                                  'toUid': fromUid,
                                  'toName': senderName,
                                  'toEmail': senderEmail,
                                  'message': replyController.text,
                                  'read': false,
                                  'timestamp': FieldValue.serverTimestamp(),
                                });

                                dialogNavigator.pop();
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('✅ ¡Respuesta enviada!'),
                                    backgroundColor: Colors.green,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              } catch (e) {
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('❌ Error: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.send_outlined, size: 18),
                            label: const Text('Responder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue[600],
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Debes iniciar sesión para ver tus mensajes.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mensajes recibidos'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: resilientStream(
          FirebaseFirestore.instance.collection('user_messages').snapshots(),
          name: 'user_messages_received_stream',
        ),
        builder: (context, snapshot) {
          // Mostrar estado de conexión
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
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

          // Mostrar errores
          if (snapshot.hasError) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(child: firestoreErrorWidget(context, snapshot.error)),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Reintentar'),
                ),
                const SizedBox(height: 16),
              ],
            );
          }

          // Si no hay datos, mostrar vacío
          if (!snapshot.hasData) {
            return const Center(child: Text('No hay datos disponibles.'));
          }

          // Filtrar solo los mensajes para el usuario actual
          var docs = snapshot.data!.docs
              .where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final toUid = data['toUid'];

                // Mostrar si es para este usuario
                return toUid == user.uid;
              })
              .toList();

          // Excluir mensajes que el destinatario ya haya eliminado (soft-delete)
          docs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['deletedByRecipient'] == null;
          }).toList();

          // Ordenar por timestamp descendente
          docs.sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['timestamp'];
            final bTs = (b.data() as Map<String, dynamic>)['timestamp'];
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

          if (docs.isEmpty) {
            return const Center(child: Text('No hay mensajes recibidos.'));
          }

          // Contar no leídos
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
                    // Lógica NORMAL: read == true significa LEÍDO
                    final readValue = data['read'];
                    final isRead = readValue == true;
          // Prefer explicit admin label when the message is sent by an admin
          final senderName = (data['fromAdmin'] == true)
            ? 'Equipo BusPoints'
            : (data['senderName'] ?? data['fromName'] ?? data['fromEmail'] ?? '?').toString();
                    final message = data['message'] ?? '';
                    final timestamp = data['timestamp'];
                    final fromUid = data['fromUid'] ?? '';
                    final senderEmail = data['senderEmail'] ?? data['fromEmail'] ?? '';

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
                          senderEmail,
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
                                      ? Icons.mark_email_read
                                      : Icons.mark_email_unread,
                                  size: 20,
                                  color: isRead ? Colors.green : Colors.blue,
                                ),
                                tooltip: isRead
                                    ? 'Leído'
                                    : 'No leído',
                                onPressed: null,
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
