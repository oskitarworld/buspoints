import 'package:flutter/material.dart';
// ...existing imports above...
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/widgets/firestore_error_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminInboxScreen extends StatefulWidget {
  const AdminInboxScreen({super.key});

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
  Future<Map<String, dynamic>> _fetchInbox() async {
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getAdminInbox');
      final result = await callable.call();
      if (result.data is Map) return Map<String, dynamic>.from(result.data as Map);
    } catch (_) {}
    return {};
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
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _setReadStatus(String docId, bool read, {bool isUserMessage = false}) async {
    try {
      if (isUserMessage) {
        await FirebaseFirestore.instance.collection('user_messages').doc(docId).update({'read': read});
      } else {
        await FirebaseFirestore.instance.collection('contact_messages').doc(docId).update({'read': read});
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteMessage(String docId, {bool isUserMessage = false}) async {
    try {
      final ref = isUserMessage
          ? FirebaseFirestore.instance.collection('user_messages').doc(docId)
          : FirebaseFirestore.instance.collection('contact_messages').doc(docId);
      await ref.delete();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  /// Send a reply message to the user. Returns true on success, false on error.
  Future<bool> _replyToUser(String recipientEmail, String message) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return false;

    try {
      final userQuery = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: recipientEmail).limit(1).get();
      if (userQuery.docs.isEmpty) throw Exception('Usuario no encontrado');
      final recipientUid = userQuery.docs.first.id;

      await FirebaseFirestore.instance.collection('user_messages').add({
        'fromUid': currentUser.uid,
        'toUid': recipientUid,
        'fromName': currentUser.displayName ?? '',
        'fromEmail': currentUser.email ?? '',
        'toEmail': recipientEmail,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'fromAdmin': true,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  void _openMessageDialog(BuildContext ctx, Map<String, dynamic> data, bool isUserMessage) {
    final docId = (data['id'] ?? '') as String;
    final senderName = (data['name'] ?? data['fromName'] ?? '') as String;
    final senderEmail = (data['email'] ?? data['fromEmail'] ?? data['toEmail'] ?? '') as String;
    final message = (data['message'] ?? '') as String;
    final timestamp = data['timestamp'];
    final isRead = data['read'] == true;

    showDialog<void>(context: ctx, builder: (dialogCtx) {
      return AlertDialog(
        title: Text(senderName.isNotEmpty ? senderName : senderEmail),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(message), const SizedBox(height: 8), Text(_formatTimestamp(timestamp), style: const TextStyle(fontSize: 12, color: Colors.grey))],)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Cerrar')),
          TextButton(onPressed: () async { Navigator.of(dialogCtx).pop(); await _setReadStatus(docId, !isRead, isUserMessage: isUserMessage); setState(() {}); }, child: Text(isRead ? 'Marcar no leído' : 'Marcar leído')),
          TextButton(onPressed: () async { Navigator.of(dialogCtx).pop(); final confirmed = await showDialog<bool>(context: ctx, builder: (c) => AlertDialog(title: const Text('Confirmar'), content: const Text('Eliminar mensaje?'), actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('No')), TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Si'))],)); if (confirmed == true) { await _deleteMessage(docId, isUserMessage: isUserMessage); setState(() {}); } }, child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      );
    });

    if (!isRead) {
      _setReadStatus(docId, true, isUserMessage: isUserMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bandeja de entrada')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchInbox(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return firestoreErrorWidget(context, snapshot.error);

          final data = snapshot.data ?? {};
          final List<dynamic> contactList = data['contact_messages'] ?? [];
          final List<dynamic> userList = data['user_messages'] ?? [];

          final List<Map<String, dynamic>> all = [];
          all.addAll(contactList.map((e) => Map<String, dynamic>.from(e as Map)));
          all.addAll(userList.map((e) => Map<String, dynamic>.from(e as Map)));

          if (all.isEmpty) return const Center(child: Text('No hay mensajes'));

          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final m in all) {
            final email = (m['email'] ?? m['fromEmail'] ?? m['toEmail'] ?? '').toString();
            if (email.isEmpty) continue;
            grouped.putIfAbsent(email, () => []).add(m);
          }

          final entries = grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (c, i) {
              final email = entries[i].key;
              final msgs = entries[i].value;
              final unread = msgs.where((m) => m['read'] != true).length;
              final first = msgs.first;
              final name = (first['name'] ?? first['fromName'] ?? email).toString();

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ExpansionTile(
                  title: Row(children: [Expanded(child: Text(name)), if (unread > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)), child: Text('$unread', style: const TextStyle(color: Colors.white)))]),
                  children: msgs.map((m) {
                    final isUserMessage = m.containsKey('fromUid') || m.containsKey('toUid');
                    final id = (m['id'] ?? '') as String;
                    return ListTile(
                      title: Text((m['message'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_formatTimestamp(m['timestamp'])),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.reply), onPressed: () async {
                          final scaffold = ScaffoldMessenger.of(context);
                          final reply = await showDialog<String>(
                            context: context,
                            builder: (d) {
                              final ctrl = TextEditingController();
                              return AlertDialog(
                                title: const Text('Responder'),
                                content: TextField(controller: ctrl, maxLines: 4),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(d).pop(), child: const Text('Cancelar')),
                                  TextButton(onPressed: () => Navigator.of(d).pop(ctrl.text), child: const Text('Enviar')),
                                ],
                              );
                            },
                          );
                          if (reply != null && reply.trim().isNotEmpty) {
                            if (!mounted) return;
                            final sent = await _replyToUser(email, reply.trim());
                            if (!mounted) return;
                            if (sent) {
                              scaffold.showSnackBar(const SnackBar(content: Text('Mensaje enviado'), backgroundColor: Colors.green));
                              setState(() {});
                            } else {
                              scaffold.showSnackBar(const SnackBar(content: Text('Error al enviar el mensaje'), backgroundColor: Colors.red));
                            }
                          }
                        }),
                        IconButton(icon: Icon(m['read'] == true ? Icons.check_circle : Icons.radio_button_unchecked), onPressed: () async { await _setReadStatus(id, !(m['read'] == true), isUserMessage: isUserMessage); if (!mounted) return; setState(() {}); }),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: const Text('Confirmar'),
                              content: const Text('Eliminar mensaje?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('No')),
                                TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Si')),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _deleteMessage(id, isUserMessage: isUserMessage);
                            if (!mounted) return;
                            setState(() {});
                          }
                        }),
                      ]),
                      onTap: () => _openMessageDialog(context, m, isUserMessage),
                    );
                  }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
