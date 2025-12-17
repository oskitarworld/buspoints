import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserMessagesScreen extends StatelessWidget {
  const UserMessagesScreen({super.key});

  String _formatTimestamp(dynamic timestamp) {
    try {
      DateTime date;
      if (timestamp is Timestamp) {
        date = timestamp.toDate();
      } else if (timestamp is int) {
        date = DateTime.fromMillisecondsSinceEpoch(timestamp);
      } else {
        return '';
      }
      final localDate = date.toLocal();
      return '${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  void _showMessagePopup(BuildContext context, String message, dynamic timestamp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mensaje completo'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 16),
              Text(
                'Enviado: ${_formatTimestamp(timestamp)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Cerrar'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
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
        title: const Text('Mis mensajes enviados'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('contact_messages')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Error cargando mensajes.'));
          }
          
          // Filtrar mensajes del usuario actual y ordenar por timestamp
          final allDocs = snapshot.data!.docs;
          final userMessages = allDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['email'] == user.email;
          }).toList();
          
          // Ordenar por timestamp descendente
          userMessages.sort((a, b) {
            final aTimestamp = (a.data() as Map<String, dynamic>)['timestamp'];
            final bTimestamp = (b.data() as Map<String, dynamic>)['timestamp'];
            
            // Convertir Timestamp a DateTime si es necesario
            DateTime aDate;
            DateTime bDate;
            
            if (aTimestamp is Timestamp) {
              aDate = aTimestamp.toDate();
            } else if (aTimestamp is int) {
              aDate = DateTime.fromMillisecondsSinceEpoch(aTimestamp);
            } else {
              aDate = DateTime(1970);
            }
            
            if (bTimestamp is Timestamp) {
              bDate = bTimestamp.toDate();
            } else if (bTimestamp is int) {
              bDate = DateTime.fromMillisecondsSinceEpoch(bTimestamp);
            } else {
              bDate = DateTime(1970);
            }
            
            return bDate.compareTo(aDate);
          });
          
          if (userMessages.isEmpty) {
            return const Center(child: Text('No has enviado mensajes.'));
          }
          
          final docs = userMessages;
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final docId = docs[index].id;
              final message = data['message'] ?? '';
              final truncatedMessage = message.length > 50
                  ? '${message.substring(0, 50)}...'
                  : message;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: GestureDetector(
                  onTap: () => _showMessagePopup(context, message, data['timestamp']),
                  child: ListTile(
                    title: Text(truncatedMessage),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Hora: ${_formatTimestamp(data['timestamp'])}'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Eliminar mensaje'),
                          content: const Text('¿Seguro que quieres eliminar este mensaje?'),
                          actions: [
                            TextButton(
                              child: const Text('Cancelar'),
                              onPressed: () => Navigator.of(ctx).pop(false),
                            ),
                            TextButton(
                              child: const Text('Eliminar'),
                              onPressed: () => Navigator.of(ctx).pop(true),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await FirebaseFirestore.instance.collection('contact_messages').doc(docId).delete();
                      }
                    },
                  ),
                ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
