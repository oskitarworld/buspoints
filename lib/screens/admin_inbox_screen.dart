import 'package:flutter/material.dart';
// ...existing imports above...
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:myapp/widgets/firestore_error_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:myapp/screens/admin_incidencias_screen.dart';

class AdminInboxScreen extends StatefulWidget {
  const AdminInboxScreen({super.key});

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
  bool _showDebug = false;
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

  Future<void> _setReadStatus(String docId, bool read, {bool isUserMessage = false, bool isIncidencia = false}) async {
    // Capture ScaffoldMessengerState early to avoid using BuildContext across async gaps
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (isUserMessage) {
        await FirebaseFirestore.instance.collection('user_messages').doc(docId).update({'read': read});
        return;
      }
      if (isIncidencia) {
        await FirebaseFirestore.instance.collection('incidencias').doc(docId).update({'read': read});
        return;
      }
      // default to contact_messages, but try incidencias if contact doc doesn't exist
      final refContact = FirebaseFirestore.instance.collection('contact_messages').doc(docId);
      try {
        final snap = await refContact.get();
        if (snap.exists) {
          await refContact.update({'read': read});
          return;
        }
      } catch (_) {}
      final refInc = FirebaseFirestore.instance.collection('incidencias').doc(docId);
      try {
        final inc = await refInc.get();
        if (inc.exists) {
          await refInc.update({'read': read});
          return;
        }
      } catch (_) {}
      // fallback: try updating contact (may throw)
      await FirebaseFirestore.instance.collection('contact_messages').doc(docId).update({'read': read});
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteMessage(String docId, {bool isUserMessage = false, bool isIncidencia = false}) async {
    // Capture messenger early to avoid BuildContext-after-await issues when
    // showing snackbars later in this async function.
    final messenger = ScaffoldMessenger.of(context);
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      // Soft-delete user_messages so we don't remove the sender's copy.
      if (isUserMessage) {
        await FirebaseFirestore.instance.collection('user_messages').doc(docId).update({
          'deletedByAdmin': currentUid ?? 'admin',
          'deletedByAdminAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('Mensaje eliminado (solo copia admin oculta)'), backgroundColor: Colors.green));
        }
        return;
      }

      // Helper to attempt removing related docs by pdiId or exact message match
  Future<void> deleteRelatedByFields({String? pdiId, String? message, Timestamp? ts}) async {
        final batch = FirebaseFirestore.instance.batch();
        bool hasDeletes = false;
        if (pdiId != null && pdiId.isNotEmpty) {
          final cmSnap = await FirebaseFirestore.instance.collection('contact_messages').where('pdiId', isEqualTo: pdiId).get();
          for (final d in cmSnap.docs) {
            batch.delete(d.reference);
            hasDeletes = true;
          }
          final incSnap = await FirebaseFirestore.instance.collection('incidencias').where('pdiId', isEqualTo: pdiId).get();
          for (final d in incSnap.docs) {
            batch.delete(d.reference);
            hasDeletes = true;
          }
        }
        if (!hasDeletes && message != null && message.isNotEmpty) {
          // Best-effort: delete exact message matches if pdiId not available
          final cmSnapMsg = await FirebaseFirestore.instance.collection('contact_messages').where('message', isEqualTo: message).get();
          for (final d in cmSnapMsg.docs) {
            // optionally check timestamp proximity
            batch.delete(d.reference);
            hasDeletes = true;
          }
          final incSnapMsg = await FirebaseFirestore.instance.collection('incidencias').where('message', isEqualTo: message).get();
          for (final d in incSnapMsg.docs) {
            batch.delete(d.reference);
            hasDeletes = true;
          }
        }
        if (hasDeletes) await batch.commit();
      }

      // If the caller indicates this is an incidencia, delete it and any related docs.
      if (isIncidencia) {
        final incRef = FirebaseFirestore.instance.collection('incidencias').doc(docId);
        final incSnap = await incRef.get();
        String? pdiId;
        String? message;
        Timestamp? ts;
        if (incSnap.exists) {
          final data = incSnap.data();
          pdiId = data?['pdiId']?.toString();
          message = data?['message']?.toString() ?? data?['comentario']?.toString();
          ts = data?['timestamp'] as Timestamp?;
          await incRef.delete();
        }
  await deleteRelatedByFields(pdiId: pdiId, message: message, ts: ts);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('Mensaje eliminado'), backgroundColor: Colors.green));
        }
        return;
      }

      // Default: try to find the document in contact_messages first and delete it,
      // then attempt to remove related incidencias (and viceversa).
      final contactRef = FirebaseFirestore.instance.collection('contact_messages').doc(docId);
      final contactSnap = await contactRef.get();
      if (contactSnap.exists) {
        final data = contactSnap.data();
        final pdiId = data?['pdiId']?.toString();
        final message = data?['message']?.toString();
        await contactRef.delete();
  await deleteRelatedByFields(pdiId: pdiId, message: message);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('Mensaje eliminado'), backgroundColor: Colors.green));
        }
        return;
      }

      // Fallback: try incidencias by id (maybe the UI showed an incidencia id)
      final incRef2 = FirebaseFirestore.instance.collection('incidencias').doc(docId);
      final incSnap2 = await incRef2.get();
      if (incSnap2.exists) {
        final data = incSnap2.data();
        final pdiId = data?['pdiId']?.toString();
        final message = data?['message']?.toString() ?? data?['comentario']?.toString();
        await incRef2.delete();
  await deleteRelatedByFields(pdiId: pdiId, message: message);
        if (mounted) {
          messenger.showSnackBar(const SnackBar(content: Text('Mensaje eliminado'), backgroundColor: Colors.green));
        }
        return;
      }

      // If nothing found, attempt to delete contact_messages doc as last resort
      await FirebaseFirestore.instance.collection('contact_messages').doc(docId).delete();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('Mensaje eliminado'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteThread(List<Map<String, dynamic>> msgs) async {
    final contactRefs = <DocumentReference>[];
    final userRefs = <DocumentReference>[];
    final incRefs = <DocumentReference>[];
    for (final m in msgs) {
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) continue;
  final src = (m['sourceCollection'] ?? '').toString();
  final srcKnown = src.isNotEmpty;
  final isUserMessage = srcKnown ? (src == 'user_messages') : (m.containsKey('fromUid') || m.containsKey('toUid'));
  final isIncidencia = srcKnown ? (src == 'incidencias') : (m.containsKey('motivo') || m.containsKey('pdiId'));
      if (isUserMessage) {
        userRefs.add(FirebaseFirestore.instance.collection('user_messages').doc(id));
      } else if (isIncidencia) {
        incRefs.add(FirebaseFirestore.instance.collection('incidencias').doc(id));
      } else {
        contactRefs.add(FirebaseFirestore.instance.collection('contact_messages').doc(id));
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      // Commit contact messages
      if (contactRefs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final r in contactRefs) {
          batch.delete(r);
        }
        await batch.commit();
      }
      // Commit incidencias
      if (incRefs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final r in incRefs) {
          batch.delete(r);
        }
        await batch.commit();
      }
      // Soft-delete user messages (don't remove sender copies). Update a
      // deletedByAdmin flag instead of deleting the document.
      if (userRefs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        for (final r in userRefs) {
          batch.update(r, {'deletedByAdmin': currentUid ?? 'admin', 'deletedByAdminAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
      }
  messenger.showSnackBar(const SnackBar(content: Text('Hilo eliminado (copias de usuario preservadas)'), backgroundColor: Colors.green));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error eliminando hilo: $e'), backgroundColor: Colors.red));
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

  Future<void> _openMassEmailDialog(BuildContext ctx) async {
    final functions = FirebaseFunctions.instance;
    String subject = '';
    String body = '';
  bool isHtml = true;

    // Capture the messenger before any awaits so inner async callbacks
    // can use it safely without referencing BuildContext across await gaps.
    final messenger = ScaffoldMessenger.of(ctx);

    String targetMode = 'all'; // 'all' | 'subscribers' | 'admins' | 'manual'
    String manualEmailsText = '';

    await showDialog<void>(context: ctx, builder: (dctx) {
      return StatefulBuilder(builder: (c, setStateDialog) {
        return AlertDialog(
          title: const Text('Enviar email masivo a usuarios'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Asunto'),
                onChanged: (v) => subject = v,
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(labelText: 'Cuerpo (HTML soportado)'),
                maxLines: 6,
                onChanged: (v) => body = v,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Checkbox(value: isHtml, onChanged: (v) => setStateDialog(() => isHtml = v ?? true)),
                const SizedBox(width: 8),
                const Text('Enviar como HTML')
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Enviar a:'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: targetMode,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Todos')),
                    DropdownMenuItem(value: 'subscribers', child: Text('Suscriptores')),
                    DropdownMenuItem(value: 'admins', child: Text('Admins')),
                    DropdownMenuItem(value: 'manual', child: Text('Seleccionar emails')),
                  ],
                  onChanged: (v) => setStateDialog(() => targetMode = v ?? 'all'),
                ),
              ]),
              if (targetMode == 'manual') ...[
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(labelText: 'Emails (separados por coma)'),
                  maxLines: 3,
                  onChanged: (v) => manualEmailsText = v,
                ),
              ]
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            TextButton(onPressed: () async {
              // Preview: call function with preview=true
              if (subject.trim().isEmpty || body.trim().isEmpty) {
                messenger.showSnackBar(const SnackBar(content: Text('Asunto y cuerpo son necesarios'), backgroundColor: Colors.red));
                return;
              }
              try {
                final callable = functions.httpsCallable('adminSendMassEmail');
                final payload = <String, dynamic>{'subject': subject.trim(), isHtml ? 'html' : 'text': body, 'preview': true, 'limit': 500};
                if (targetMode == 'manual') {
                  final emails = manualEmailsText.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  payload['mode'] = 'manual';
                  payload['manualEmails'] = emails;
                } else if (targetMode == 'subscribers' || targetMode == 'admins') {
                  payload['mode'] = 'segment';
                  payload['segment'] = targetMode;
                } else {
                  payload['mode'] = 'all';
                }

                final res = await callable.call(payload);
                final data = res.data as Map<String, dynamic>;
                final count = data['count'] ?? 0;
                final sample = (data['sample'] as List<dynamic>?)?.cast<String>() ?? <String>[];
                // Use the original outer context (ctx) when opening the nested
                // preview/confirm dialogs because `dctx` (the dialog builder
                // context) may not be safe to reference after awaiting network
                // calls. Using `ctx` (captured before awaits) avoids the
                // use_build_context_synchronously warning.
                // ignore: use_build_context_synchronously
                await showDialog<void>(context: ctx, builder: (confirmCtx) {
                  return AlertDialog(
                    title: const Text('Vista previa'),
                    content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Se enviará a $count usuarios.'), const SizedBox(height: 8), const Text('Ejemplos:'), const SizedBox(height: 6), ...sample.map((e) => Text(e)) ])),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Volver')),
                      TextButton(onPressed: () async {
                        // Capture the navigator for the confirm dialog before awaiting.
                        // Use the outer 'ctx' (captured before awaits) rather than
                        // the builder-local 'confirmCtx' to avoid holding a
                        // BuildContext across async gaps.
                        final navConfirm = Navigator.of(ctx);
                        // Ask for a final confirmation
                        final ok = await showDialog<bool>(context: ctx, builder: (c2) => AlertDialog(
                          title: const Text('Confirmar envío'),
                          content: Text('¿Confirmas enviar el correo a $count usuarios? Esto no se puede deshacer.'),
                          actions: [TextButton(onPressed: () => Navigator.of(c2).pop(false), child: const Text('No')), TextButton(onPressed: () => Navigator.of(c2).pop(true), child: const Text('Sí, enviar'))],
                        ));
                        if (ok != true) return;
                        // Close the preview dialog using the captured NavigatorState
                        navConfirm.pop();
                        // Send
                        try {
                          final sendPayload = <String, dynamic>{'subject': subject.trim(), isHtml ? 'html' : 'text': body, 'preview': false, 'limit': 0};
                          if (targetMode == 'manual') {
                            final emails = manualEmailsText.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                            sendPayload['mode'] = 'manual';
                            sendPayload['manualEmails'] = emails;
                          } else if (targetMode == 'subscribers' || targetMode == 'admins') {
                            sendPayload['mode'] = 'segment';
                            sendPayload['segment'] = targetMode;
                          } else {
                            sendPayload['mode'] = 'all';
                          }

                          // Capture the compose dialog's NavigatorState (use the
                          // original outer context 'ctx' which was captured
                          // before awaiting) to safely pop the compose dialog
                          // after the async call completes.
                          // ignore: use_build_context_synchronously
                          final navCompose = Navigator.of(ctx);
                          final sendRes = await functions.httpsCallable('adminSendMassEmail').call(sendPayload);
                          final sendData = sendRes.data as Map<String, dynamic>;
                          final sent = sendData['sent'] ?? 0;
                          final failed = sendData['failed'] ?? 0;
                          messenger.showSnackBar(SnackBar(content: Text('Envío terminado. Enviados: $sent, Fallidos: $failed'), backgroundColor: Colors.green));
                          // Close the compose dialog using the captured NavigatorState
                          navCompose.pop();
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(content: Text('Error enviando: $e'), backgroundColor: Colors.red));
                        } finally {
                          // no-op: removed unused 'sending' flag
                        }
                      }, child: const Text('Enviar')),
                    ],
                  );
                });
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Error en vista previa: $e'), backgroundColor: Colors.red));
              }
            }, child: const Text('Vista previa')),
          ],
        );
      });
    });
  }

  void _openMessageDialog(BuildContext ctx, Map<String, dynamic> data, bool isUserMessage, bool isIncidencia) {
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
          TextButton(onPressed: () async {
            // Capture NavigatorState before awaiting to avoid using BuildContext
            // across async gaps (use_build_context_synchronously).
            final nav = Navigator.of(dialogCtx);
            nav.pop();
            await _setReadStatus(docId, !isRead, isUserMessage: isUserMessage);
            if (!mounted) return;
            setState(() {});
          }, child: Text(isRead ? 'Marcar no leído' : 'Marcar leído')),
          TextButton(onPressed: () async {
            // Use the dialog's NavigatorState to avoid retaining the BuildContext
            // across the await below (prevents use_build_context_synchronously).
            final nav = Navigator.of(dialogCtx);
            // Ask for confirmation using the same dialog context.
            final confirmed = await showDialog<bool>(
              context: dialogCtx,
              builder: (c) => AlertDialog(
                title: const Text('Confirmar'),
                content: const Text('Eliminar mensaje?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('No')),
                  TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Si')),
                ],
              ),
            );
            if (confirmed == true) {
              // Pop the original message dialog using the previously captured NavigatorState
              nav.pop();
              await _deleteMessage(docId, isUserMessage: isUserMessage, isIncidencia: isIncidencia);
              if (!mounted) return;
              setState(() {});
            }
          }, child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
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
      appBar: AppBar(
        title: const Text('Bandeja de entrada'),
        actions: [
          // Incidencias unread count badge
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('incidencias').where('read', isEqualTo: false).snapshots(),
            builder: (context, snap) {
              final int count = snap.hasData ? snap.data!.docs.length : 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.report_problem_outlined),
                    tooltip: 'Incidencias',
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminIncidenciasScreen()));
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 18),
                        child: Text(
                          count > 99 ? '99+' : count.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (kDebugMode)
            IconButton(
              icon: Icon(_showDebug ? Icons.bug_report : Icons.bug_report_outlined),
              tooltip: 'Toggle inbox debug',
              onPressed: () => setState(() => _showDebug = !_showDebug),
            ),
          // Mass email to all users (admin only) - opens compose dialog (uses Cloud Functions)
          IconButton(
            icon: const Icon(Icons.mark_email_unread_outlined),
            tooltip: 'Enviar email masivo',
            onPressed: () => _openMassEmailDialog(context),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _fetchInbox(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return firestoreErrorWidget(context, snapshot.error);

          final data = snapshot.data ?? {};
          final List<dynamic> contactList = data['contact_messages'] ?? [];
          final List<dynamic> userList = data['user_messages'] ?? [];

          // NOTE: incidencias are intentionally NOT merged into the main
          // inbox. They have their own admin mailbox (AdminIncidenciasScreen).
          final List<Map<String, dynamic>> all = [];
          all.addAll(contactList.map((e) => Map<String, dynamic>.from(e as Map)));
          all.addAll(userList.map((e) => Map<String, dynamic>.from(e as Map)));

          // Filter out messages that have been soft-deleted by an admin so
          // they no longer appear in the admin inbox.
          all.removeWhere((m) => m['deletedByAdmin'] != null);

          // Also exclude messages that were sent by the current admin (outgoing copies),
          // since the admin inbox should show incoming messages and originals, not the
          // admin's own sent documents which would create redundant threads.
          final currentAdminUid = FirebaseAuth.instance.currentUser?.uid;
          if (currentAdminUid != null && currentAdminUid.isNotEmpty) {
            all.removeWhere((m) {
              final src = (m['sourceCollection'] ?? '').toString();
              final fromUid = (m['fromUid'] ?? '').toString();
              return src == 'user_messages' && fromUid == currentAdminUid;
            });
          }

          // Compute a normalized PDI id for each message to help deduplication
          String normalizePdiFor(Map<String, dynamic> m) {
            try {
              final pdi = (m['pdiId'] ?? m['poiId'] ?? m['poi_id'] ?? m['placeId'] ?? '').toString();
              if (pdi.isNotEmpty) return pdi.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
              final pname = (m['placeName'] ?? m['name'] ?? '').toString();
              final pcat = (m['placeCategory'] ?? m['category'] ?? '').toString();
              final derived = '${pname}_$pcat'.toLowerCase();
              return derived.replaceAll(RegExp(r'[^a-z0-9]'), '');
            } catch (_) {
              return '';
            }
          }

          String normalizeMsgText(String? t) {
            if (t == null) return '';
            return t.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
          }

          for (final m in all) {
            m['__normPdi'] = normalizePdiFor(m);
            m['__normMsg'] = normalizeMsgText((m['message'] ?? m['comentario'] ?? '').toString());
            // normalize timestamp to milliseconds for quick comparisons
            try {
              final ts = m['timestamp'];
              if (ts is Timestamp) {
                m['__tsMillis'] = ts.millisecondsSinceEpoch;
              } else if (ts is int) {
                m['__tsMillis'] = ts;
              } else {
                m['__tsMillis'] = null;
              }
            } catch (_) {
              m['__tsMillis'] = null;
            }
          }

          // Build set of normalized PDIs and message hashes from original (non-user_messages) docs
          final Set<String> originalsNormPdi = {};
          final List<Map<String, dynamic>> originals = [];
          for (final o in all) {
            final src = (o['sourceCollection'] ?? '').toString();
            if (src == 'user_messages') continue;
            originalsNormPdi.add((o['__normPdi'] ?? '').toString());
            originals.add(o);
          }

          // Remove user_messages that are mirrors (isContact) when there's an original with same normalized PDI
          // or when the normalized message text matches an original within a small time window (10s).
          all.removeWhere((m) {
            final src = (m['sourceCollection'] ?? '').toString();
            final isUserMsg = src == 'user_messages' || (m.containsKey('fromUid') && m.containsKey('toUid') && (m['isContact'] == true || m['isContact'] == 'true'));
            if (!isUserMsg) return false;
            final norm = (m['__normPdi'] ?? '').toString();
            final normMsg = (m['__normMsg'] ?? '').toString();
            if (norm.isNotEmpty && originalsNormPdi.contains(norm)) return true;
            if (normMsg.isNotEmpty) {
              // find originals with same normMsg and close timestamp
              final int? ts = m['__tsMillis'] as int?;
              for (final o in originals) {
                if ((o['__normMsg'] ?? '') == normMsg) {
                  final int? ots = o['__tsMillis'] as int?;
                  if (ots != null && ts != null && (ots - ts).abs() <= 10000) return true;
                }
              }
            }
            return false;
          });

          if (all.isEmpty) return const Center(child: Text('No hay mensajes'));

          // Group messages into threads. Prefer grouping by PDI when a pdiId is
          // present so that multiple documents created for the same report
          // (contact_messages + incidencias + user_messages copy) are merged.
          // Fallback to sender-based grouping when no pdiId is available.
          final Map<String, List<Map<String, dynamic>>> grouped = {};
          for (final m in all) {
            // Normalize sender identity: prefer explicit email fields, fall back to fromName
            String sender = (m['email'] ?? m['fromEmail'] ?? m['toEmail'] ?? '').toString().trim();
            if (sender.contains(',') || sender.contains(';')) {
              sender = sender.split(RegExp(r'[;,]')).first.trim();
            }
            if (sender.isEmpty) sender = (m['name'] ?? m['fromName'] ?? '').toString().trim();
            if (sender.isEmpty) sender = '(Sin remitente)';

            // Try to get a pdi identifier from known fields. If present, include it
            // in the grouping key so reports about the same POI are merged.
            String pdi = (m['pdiId'] ?? m['poiId'] ?? m['poi_id'] ?? m['placeId'] ?? '').toString().trim();

            // Normalize the PDI identifier to avoid small variations causing
            // duplicate threads. Remove non-alphanumeric chars and lowercase.
            String normalizedPdi = '';
            try {
              if (pdi.isNotEmpty) {
                normalizedPdi = pdi.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
              }
            } catch (_) {
              normalizedPdi = pdi;
            }

            // If pdi is empty or normalization yielded nothing, try to derive
            // a stable id from placeName + category (this mirrors _sanitizeId)
            if (normalizedPdi.isEmpty) {
              final pname = (m['placeName'] ?? m['name'] ?? '').toString();
              final pcat = (m['placeCategory'] ?? m['category'] ?? '').toString();
              final derived = '${pname}_$pcat'.toLowerCase();
              normalizedPdi = derived.replaceAll(RegExp(r'[^a-z0-9]'), '');
            }

            // Build a participant-based key for direct chats when possible
            String participantKey = '';
            try {
              final fromUid = (m['fromUid'] ?? '').toString().trim();
              final toUid = (m['toUid'] ?? '').toString().trim();
              if (fromUid.isNotEmpty && toUid.isNotEmpty) {
                final pair = [fromUid, toUid]..sort();
                participantKey = 'chat:${pair[0]}|${pair[1]}';
              } else {
                // fallback to emails when uids are not present
                final fromEmail = (m['fromEmail'] ?? '').toString().trim();
                final toEmail = (m['toEmail'] ?? '').toString().trim();
                if (fromEmail.isNotEmpty && toEmail.isNotEmpty) {
                  final pair = [fromEmail.toLowerCase(), toEmail.toLowerCase()]..sort();
                  participantKey = 'chat:${pair[0]}|${pair[1]}';
                }
              }
            } catch (_) {
              participantKey = '';
            }

            // Use pdi-first grouping for reports, otherwise use participantKey
            final key = normalizedPdi.isNotEmpty ? 'pdi:$normalizedPdi' : (participantKey.isNotEmpty ? participantKey : 'sender:$sender');
            grouped.putIfAbsent(key, () => []).add(m);
          }

          // Convert grouped map to a list of entries sorted by most-recent message
          final entries = grouped.entries.toList()
            ..sort((a, b) {
              DateTime ta = DateTime.fromMillisecondsSinceEpoch(0);
              DateTime tb = DateTime.fromMillisecondsSinceEpoch(0);
              try {
                final aLast = a.value.firstWhere((m) => m['timestamp'] != null, orElse: () => a.value.first)['timestamp'];
                if (aLast is Timestamp) {
                  ta = aLast.toDate();
                } else if (aLast is int) {
                  ta = DateTime.fromMillisecondsSinceEpoch(aLast);
                }
              } catch (_) {}
              try {
                final bLast = b.value.firstWhere((m) => m['timestamp'] != null, orElse: () => b.value.first)['timestamp'];
                if (bLast is Timestamp) {
                  tb = bLast.toDate();
                } else if (bLast is int) {
                  tb = DateTime.fromMillisecondsSinceEpoch(bLast);
                }
              } catch (_) {}
              return tb.compareTo(ta);
            });

          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (c, i) {
              final msgs = entries[i].value;
              final unread = msgs.where((m) => m['read'] != true).length;
              final firstMsg = msgs.first;

              // Build a sensible reply email: prefer the non-admin participant email from the first message
              final currentAdminEmail = FirebaseAuth.instance.currentUser?.email ?? '';
              String recipientEmail = (firstMsg['fromEmail'] ?? firstMsg['email'] ?? '').toString();
              if (recipientEmail.isEmpty) recipientEmail = (firstMsg['toEmail'] ?? '').toString();
              if (recipientEmail == currentAdminEmail) recipientEmail = (firstMsg['toEmail'] ?? firstMsg['email'] ?? '').toString();
              final email = recipientEmail;

              final name = (firstMsg['name'] ?? firstMsg['fromName'] ?? email).toString();

              // Each card represents a thread (may include multiple related docs)
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ExpansionTile(
                  title: Row(children: [
                    Expanded(child: Text(name.isNotEmpty ? name : '(Sin remitente)')),
                    if (unread > 0)
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)), child: Text('$unread', style: const TextStyle(color: Colors.white))),
                    // (Open PDI action moved to individual message rows so the
                    // admin can open the exact reported point.)
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                      tooltip: 'Eliminar hilo',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Eliminar hilo'),
                            content: const Text('¿Estás seguro de que quieres eliminar todos los mensajes de este remitente?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('No')),
                              TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Sí')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await _deleteThread(msgs);
                          if (!mounted) return;
                          setState(() {});
                        }
                      },
                    ),
                  ]),
                  children: msgs.map((m) {
                    // detect source collection if server provided it
                    final src = (m['sourceCollection'] ?? '').toString();
                    final srcKnown = src.isNotEmpty;
                    final isUserMessage = srcKnown ? (src == 'user_messages') : (m.containsKey('fromUid') || m.containsKey('toUid'));
                    final isIncidencia = srcKnown ? (src == 'incidencias') : (m.containsKey('motivo') || m.containsKey('pdiId'));
                    final id = (m['id'] ?? '') as String;
                    final msgPdi = (m['pdiId'] ?? m['poiId'] ?? m['poi_id'] ?? m['placeId'] ?? '').toString();
                    return ListTile(
                      title: Text((m['message'] ?? m['comentario'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_formatTimestamp(m['timestamp'])),
                            if (_showDebug)
                              Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Text(
                                  'src=${m['sourceCollection'] ?? '-'} | rawPdi=${m['pdiId'] ?? m['poiId'] ?? m['poi_id'] ?? m['placeId'] ?? '-'} | normPdi=${((m['pdiId'] ?? m['poiId'] ?? m['poi_id'] ?? m['placeId'] ?? '')).toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')} | id=${m['id'] ?? '-'} | read=${m['read'] == true}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ),
                          ],
                        ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.reply), onPressed: () async {
                          final scaffold = ScaffoldMessenger.of(context);
                          final String senderName = (m['fromName'] ?? m['name'] ?? '').toString();
                          final String senderEmail = (m['fromEmail'] ?? m['email'] ?? '').toString();
                          final TextEditingController replyCtrl = TextEditingController();

                          await showDialog<void>(
                            context: context,
                            builder: (d) {
                              return Dialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: LinearGradient(colors: [Colors.blue[50]!, Colors.blue[100]!]),
                                  ),
                                  padding: const EdgeInsets.all(0),
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(colors: [Colors.blue[600]!, Colors.blue[400]!]),
                                            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 24,
                                                backgroundColor: Colors.white.withAlpha((0.3 * 255).round()),
                                                child: Text(
                                                  senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                                                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  Text(senderName.isNotEmpty ? senderName : senderEmail, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 4),
                                                  Text(senderEmail, style: TextStyle(color: Colors.white.withAlpha((0.9 * 255).round()), fontSize: 12)),
                                                ]),
                                              ),
                                              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(d).pop()),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              TextField(
                                                controller: replyCtrl,
                                                maxLines: 5,
                                                decoration: const InputDecoration(
                                                  hintText: 'Escribe tu respuesta...',
                                                  border: OutlineInputBorder(),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              Row(children: [
                                                Expanded(
                                                  child: ElevatedButton(
                                                    onPressed: () => Navigator.of(d).pop(),
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black),
                                                    child: const Text('Cancelar'),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: ElevatedButton.icon(
                                                    onPressed: () async {
                                                      final text = replyCtrl.text.trim();
                                                      if (text.isEmpty) {
                                                        scaffold.showSnackBar(const SnackBar(content: Text('✋ Por favor escribe una respuesta'), backgroundColor: Colors.orange));
                                                        return;
                                                      }
                                                      // Close the dialog first (use dialog's context `d`), then perform async work.
                                                      Navigator.of(d).pop();
                                                      final ok = await _replyToUser(email, text);
                                                      if (!mounted) return;
                                                      if (ok) {
                                                        scaffold.showSnackBar(const SnackBar(content: Text('✅ ¡Respuesta enviada!'), backgroundColor: Colors.green));
                                                        setState(() {});
                                                      } else {
                                                        scaffold.showSnackBar(const SnackBar(content: Text('❌ Error al enviar la respuesta'), backgroundColor: Colors.red));
                                                      }
                                                    },
                                                    icon: const Icon(Icons.send_outlined),
                                                    label: const Text('Responder'),
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white),
                                                  ),
                                                ),
                                              ]),
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
                        }),
                        // Open PDI for this specific message (only show when available)
                        if (msgPdi.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.place, color: Colors.blueAccent),
                            tooltip: 'Abrir PDI',
                            onPressed: () {
                              Navigator.of(context).pushNamed('/home', arguments: {
                                'focus': {
                                  if (msgPdi.isNotEmpty) 'docId': msgPdi,
                                  if ((m['placeName'] ?? m['name']) != null) 'name': (m['placeName'] ?? m['name']),
                                  if ((m['placeCategory'] ?? m['category']) != null) 'category': (m['placeCategory'] ?? m['category']),
                                }
                              });
                            },
                          ),
                        IconButton(icon: Icon(m['read'] == true ? Icons.check_circle : Icons.radio_button_unchecked), onPressed: () async { await _setReadStatus(id, !(m['read'] == true), isUserMessage: isUserMessage, isIncidencia: isIncidencia); if (!mounted) return; setState(() {}); }),
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
                            await _deleteMessage(id, isUserMessage: isUserMessage, isIncidencia: isIncidencia);
                            if (!mounted) return;
                            setState(() {});
                          }
                        }),
                      ]),
                      onTap: () => _openMessageDialog(context, m, isUserMessage, isIncidencia),
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
