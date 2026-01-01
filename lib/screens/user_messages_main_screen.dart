import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_web_compat.dart';

class UserMessagesMainScreen extends StatefulWidget {
  final int tabIndex;
  const UserMessagesMainScreen({super.key, this.tabIndex = 0});

  @override
  State<UserMessagesMainScreen> createState() => _UserMessagesMainScreenState();
}

class _UserMessagesMainScreenState extends State<UserMessagesMainScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Debes iniciar sesión para ver tus mensajes.')),
      );
    }
    return DefaultTabController(
      initialIndex: widget.tabIndex,
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mensajes'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Recibidos'),
              Tab(text: 'Enviados'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Recibidos
            _buildReceivedMessages(context, user),
            // Enviados
            _buildSentMessages(context, user),
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedMessages(BuildContext context, User user) {
    return StreamBuilder<QuerySnapshot>(
      stream: resilientStream(
        FirebaseFirestore.instance
            .collection('user_messages')
            .where('toUid', isEqualTo: user.uid)
            .snapshots(),
        name: 'user_messages_received_stream',
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Error al cargar mensajes.'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        var docs = snapshot.data!.docs;
        // Exclude documents that the recipient (current user) has soft-deleted
        docs = docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['deletedByRecipient'] == null;
        }).toList();
        if (docs.isEmpty) return const Center(child: Text('No hay mensajes.'));

        docs.sort((a, b) {
          final aTs = (a.data() as Map<String, dynamic>)['timestamp'];
          final bTs = (b.data() as Map<String, dynamic>)['timestamp'];
          DateTime aDate = aTs is Timestamp ? aTs.toDate() : (aTs is int ? DateTime.fromMillisecondsSinceEpoch(aTs) : DateTime(1970));
          DateTime bDate = bTs is Timestamp ? bTs.toDate() : (bTs is int ? DateTime.fromMillisecondsSinceEpoch(bTs) : DateTime(1970));
          return bDate.compareTo(aDate);
        });

        // Agrupar por hilo
        Map<String, List<QueryDocumentSnapshot>> threadMap = {};
        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final fromUid = data['fromUid'] ?? '';
          final toUid = data['toUid'] ?? '';
          final threadKey = [fromUid, toUid]..sort();
          final key = threadKey.join('_');

          if (!threadMap.containsKey(key)) {
            threadMap[key] = [];
          }
          threadMap[key]!.add(doc);
        }

        // Ordenar cada hilo
        for (var entry in threadMap.entries) {
          entry.value.sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['timestamp'];
            final bTs = (b.data() as Map<String, dynamic>)['timestamp'];
            DateTime aDate = aTs is Timestamp ? aTs.toDate() : (aTs is int ? DateTime.fromMillisecondsSinceEpoch(aTs) : DateTime(1970));
            DateTime bDate = bTs is Timestamp ? bTs.toDate() : (bTs is int ? DateTime.fromMillisecondsSinceEpoch(bTs) : DateTime(1970));
            return bDate.compareTo(aDate);
          });
        }

        final threads = threadMap.entries.toList();
        threads.sort((a, b) {
          final aLastTs = (a.value.first.data() as Map<String, dynamic>)['timestamp'];
          final bLastTs = (b.value.first.data() as Map<String, dynamic>)['timestamp'];
          DateTime aDate = aLastTs is Timestamp ? aLastTs.toDate() : (aLastTs is int ? DateTime.fromMillisecondsSinceEpoch(aLastTs) : DateTime(1970));
          DateTime bDate = bLastTs is Timestamp ? bLastTs.toDate() : (bLastTs is int ? DateTime.fromMillisecondsSinceEpoch(bLastTs) : DateTime(1970));
          return bDate.compareTo(aDate);
        });

        final unreadCount = docs.where((doc) => (doc.data() as Map<String, dynamic>)['read'] != true).length;

        return Column(
          children: [
            if (unreadCount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.blue.withAlpha((0.1 * 255).round()),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$unreadCount sin leer',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: threads.length,
                itemBuilder: (context, threadIndex) {
                  final threadMessages = threads[threadIndex].value;
                  final lastMessage = threadMessages.first;
                  final lastData = lastMessage.data() as Map<String, dynamic>;

                  final unreadInThread = threadMessages.where((msg) => 
                    (msg.data() as Map<String, dynamic>)['read'] != true
                  ).length;

          final senderName = (lastData['fromAdmin'] == true)
            ? 'Equipo BusPoints'
            : (lastData['senderName'] ?? lastData['fromName'] ?? lastData['fromEmail'] ?? 'Usuario').toString();
                  final lastMessagePreview = (lastData['message'] ?? '').toString().length > 40 
                      ? '${(lastData['message'] as String).substring(0, 40)}...'
                      : (lastData['message'] ?? '');

                  return ExpansionTile(
                    key: Key(threads[threadIndex].key),
                    initiallyExpanded: unreadInThread > 0,
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          senderName,
                          style: TextStyle(
                            fontWeight: unreadInThread > 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          lastMessagePreview,
                          style: const TextStyle(fontSize: 13, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    trailing: unreadInThread > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unreadInThread.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : null,
                    children: [
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: threadMessages.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, msgIndex) {
                          final doc = threadMessages[msgIndex];
                          final data = doc.data() as Map<String, dynamic>;
                          final message = data['message'] ?? '';
                          final truncated = message.length > 40 ? message.substring(0, 40) + '...' : message;
                          final isUnread = data['read'] == false;
                          final concept = data['concept'] ?? '';

                          return Container(
                            decoration: BoxDecoration(
                              color: isUnread ? Colors.red.withAlpha((0.08 * 255).round()) : Colors.green.withAlpha((0.06 * 255).round()),
                              border: Border(
                                left: BorderSide(
                                  color: isUnread ? Colors.red : Colors.green,
                                  width: 4,
                                ),
                              ),
                            ),
                            child: ListTile(
                              title: Text(
                                truncated,
                                style: TextStyle(
                                  fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('De: ${data['senderName'] ?? data['fromName'] ?? 'Usuario'}'),
                                  if (concept.isNotEmpty)
                                    Text('Concepto: $concept', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_formatTime(data['timestamp'])),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Eliminar',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Eliminar mensaje'),
                                          content: const Text('¿Estás seguro?'),
                                          actions: [
                                            TextButton(
                                              child: const Text('Cancelar'),
                                              onPressed: () => Navigator.of(ctx).pop(false),
                                            ),
                                            TextButton(
                                              child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                              onPressed: () => Navigator.of(ctx).pop(true),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        try {
                                          // Soft-delete for recipient: mark deletedByRecipient so sender/admin copies remain
                                          await FirebaseFirestore.instance
                                              .collection('user_messages')
                                              .doc(doc.id)
                                              .update({
                                            'deletedByRecipient': user.uid,
                                            'deletedByRecipientAt': FieldValue.serverTimestamp(),
                                          });
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Eliminado.'), backgroundColor: Colors.green),
                                            );
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Error: $e')),
                                            );
                                          }
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                              onTap: () {
                                if (isUnread) {
                                  FirebaseFirestore.instance
                                      .collection('user_messages')
                                      .doc(doc.id)
                                      .update({'read': true})
                                      .onError((error, stackTrace) {
                                        debugPrint('Error: $error');
                                        return null;
                                      });
                                }
                                showDialog(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('De: ${data['senderName'] ?? data['fromName'] ?? 'Usuario'}'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (concept.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(bottom: 12.0),
                                            child: Text('Concepto: $concept', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          ),
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
                                      TextButton(
                                        child: const Text('Responder'),
                                        onPressed: () async {
                                          Navigator.of(ctx).pop();
                                          final String senderUid = data['fromUid'] ?? '';
                                          final String currentUserName = user.displayName ?? 'Usuario';
                                          if (senderUid.isEmpty) {
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Error: No se puede identificar al remitente.')),
                                              );
                                            }
                                            return;
                                          }
                                          final replyController = TextEditingController();
                                          if (context.mounted) {
                                            showDialog(
                                              context: context,
                                              builder: (replyCtx) => AlertDialog(
                                                title: const Text('Responder'),
                                                content: TextField(
                                                  controller: replyController,
                                                  decoration: const InputDecoration(
                                                    hintText: 'Tu respuesta...',
                                                    border: OutlineInputBorder(),
                                                  ),
                                                  maxLines: 4,
                                                ),
                                                actions: [
                                                  TextButton(
                                                    child: const Text('Cancelar'),
                                                    onPressed: () => Navigator.of(replyCtx).pop(),
                                                  ),
                                                  TextButton(
                                                    child: const Text('Enviar'),
                                                    onPressed: () async {
                                                      final replyText = replyController.text.trim();
                                                      if (replyText.isEmpty) {
                                                        ScaffoldMessenger.of(replyCtx).showSnackBar(
                                                          const SnackBar(content: Text('El mensaje no puede estar vacío.')),
                                                        );
                                                        return;
                                                      }
                                                      try {
                                                        await FirebaseFirestore.instance.collection('user_messages').add({
                                                          'fromUid': user.uid,
                                                          'toUid': senderUid,
                                                          'senderName': currentUserName,
                                                          'senderEmail': user.email ?? '',
                                                          'senderPhone': '',
                                                          'toName': data['senderName'] ?? data['fromName'] ?? 'Usuario',
                                                          'toEmail': data['senderEmail'] ?? data['fromEmail'] ?? '',
                                                          'concept': currentUserName,
                                                          'message': replyText,
                                                          'timestamp': FieldValue.serverTimestamp(),
                                                          'read': false,
                                                        });
                                                        if (replyCtx.mounted) {
                                                          Navigator.of(replyCtx).pop();
                                                          if (context.mounted) {
                                                            ScaffoldMessenger.of(context).showSnackBar(
                                                              const SnackBar(content: Text('Respuesta enviada.')),
                                                            );
                                                          }
                                                        }
                                                      } catch (e) {
                                                        if (replyCtx.mounted) {
                                                          ScaffoldMessenger.of(replyCtx).showSnackBar(
                                                            SnackBar(content: Text('Error: $e')),
                                                          );
                                                        }
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                      TextButton(
                                        child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: ctx,
                                            builder: (ctx2) => AlertDialog(
                                              title: const Text('Confirmar'),
                                              content: const Text('¿Eliminar este mensaje?'),
                                              actions: [
                                                TextButton(
                                                  child: const Text('Cancelar'),
                                                  onPressed: () => Navigator.of(ctx2).pop(false),
                                                ),
                                                TextButton(
                                                  child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                                  onPressed: () => Navigator.of(ctx2).pop(true),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm == true) {
                                            try {
                                              await FirebaseFirestore.instance
                                                  .collection('user_messages')
                                                  .doc(doc.id)
                                                  .delete();
                                              if (context.mounted) {
                                                Navigator.of(ctx).pop();
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Eliminado.')),
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Error: $e')),
                                                );
                                              }
                                            }
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSentMessages(BuildContext context, User user) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('user_messages')
          .where('fromUid', isEqualTo: user.uid)
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

            return ListTile(
              title: Text(truncated),
              subtitle: Text('Para: ${data['toName'] ?? data['toEmail'] ?? 'Usuario'}'),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Eliminar mensaje'),
                      content: const Text('¿Estás seguro?'),
                      actions: [
                        TextButton(
                          child: const Text('Cancelar'),
                          onPressed: () => Navigator.of(ctx).pop(false),
                        ),
                        TextButton(
                          child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    ),
                  );
                    if (confirm == true) {
                    try {
                      // Soft-delete sender copy so recipient/admin copies remain
                      await FirebaseFirestore.instance
                          .collection('user_messages')
                          .doc(docs[index].id)
                          .update({
                        'deletedBySender': user.uid,
                        'deletedBySenderAt': FieldValue.serverTimestamp(),
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Eliminado.')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  }
                },
              ),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Para: ${data['toName'] ?? data['toEmail'] ?? 'Usuario'}'),
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
                      TextButton(
                        child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: ctx,
                            builder: (ctx2) => AlertDialog(
                              title: const Text('Confirmar'),
                              content: const Text('¿Eliminar este mensaje?'),
                              actions: [
                                TextButton(
                                  child: const Text('Cancelar'),
                                  onPressed: () => Navigator.of(ctx2).pop(false),
                                ),
                                TextButton(
                                  child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                                  onPressed: () => Navigator.of(ctx2).pop(true),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            try {
                              // Soft-delete sender copy so recipient/admin copies remain
                              await FirebaseFirestore.instance
                                  .collection('user_messages')
                                  .doc(docs[index].id)
                                  .update({
                                'deletedBySender': user.uid,
                                'deletedBySenderAt': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                Navigator.of(ctx).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Eliminado.'), backgroundColor: Colors.green),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error: $e')),
                                );
                              }
                            }
                          }
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
