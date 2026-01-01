import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_web_compat.dart';

class UserMessagesSentScreen extends StatelessWidget {
  const UserMessagesSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Debes iniciar sesión para ver tus mensajes.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mensajes enviados')),
      body: StreamBuilder<QuerySnapshot>(
        stream: resilientStream(
          FirebaseFirestore.instance.collection('user_messages').where('fromUid', isEqualTo: user.uid).snapshots(),
          name: 'user_messages_sent_stream',
        ),
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
              final concept = data['concept'] ?? '';
              
              // Determinar el ícono según el concepto
              IconData leadingIcon = Icons.mail;
              Color leadingColor = Colors.grey;
              if (concept == 'Propuesta de mejora') {
                leadingIcon = Icons.lightbulb;
                leadingColor = Colors.amber;
              } else if (concept == 'Contacto') {
                leadingIcon = Icons.mail;
                leadingColor = Colors.blue;
              }
              
              return ListTile(
                leading: Icon(leadingIcon, color: leadingColor),
                title: Text(truncated),
                subtitle: Text('Para: ${data['toName'] ?? data['toEmail'] ?? ''}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Eliminar mensaje',
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Eliminar mensaje'),
                        content: const Text('¿Estás seguro de que quieres eliminar este mensaje?'),
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
                        await FirebaseFirestore.instance
                            .collection('user_messages')
                            .doc(docs[index].id)
                            .delete();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Mensaje eliminado.')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error al eliminar: $e')),
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
                      title: Text('Para: ${data['toName'] ?? data['toEmail'] ?? ''}'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (concept.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Text('Concepto: $concept', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
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
                          child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: ctx,
                              builder: (ctx2) => AlertDialog(
                                title: const Text('Confirmar eliminación'),
                                content: const Text('¿Estás seguro de que quieres eliminar este mensaje?'),
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
                                    .doc(docs[index].id)
                                    .delete();
                                if (context.mounted) {
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Mensaje eliminado.')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error al eliminar: $e')),
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
