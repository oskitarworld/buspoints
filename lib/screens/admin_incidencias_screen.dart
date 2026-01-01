import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// no external deps required; use simple timestamp formatting

class AdminIncidenciasScreen extends StatefulWidget {
  const AdminIncidenciasScreen({super.key});

  @override
  State<AdminIncidenciasScreen> createState() => _AdminIncidenciasScreenState();
}

class _AdminIncidenciasScreenState extends State<AdminIncidenciasScreen> {
  bool _loadedAdminCheck = false;
  bool _canReadIncidencias = false;
  String _adminCheckInfo = '';

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loadedAdminCheck = true;
          _canReadIncidencias = false;
          _adminCheckInfo = 'No hay usuario autenticado';
        });
        return;
      }

      String info = 'UID: ${user.uid}\n';

      final idToken = await user.getIdTokenResult(true);
      final claims = idToken.claims ?? {};
      info += 'Token claims: ${claims.toString()}\n';

      // Read users/{uid} doc if exists
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          info += 'users/{uid} doc: ${data?.toString() ?? '{}'}\n';
          final role = data?['role'];
          final isAdminField = data?['isAdmin'];
          if (role == 'admin' || isAdminField == true) {
            setState(() {
              _loadedAdminCheck = true;
              _canReadIncidencias = true;
              _adminCheckInfo = info;
            });
            return;
          }
        } else {
          info += 'users/{uid} doc: (no existe)\n';
        }
      } catch (e) {
        info += 'Error leyendo users/{uid}: $e\n';
      }

      // Fallback to token claim check
      if (claims['admin'] == true) {
        setState(() {
          _loadedAdminCheck = true;
          _canReadIncidencias = true;
          _adminCheckInfo = info;
        });
        return;
      }

      setState(() {
        _loadedAdminCheck = true;
        _canReadIncidencias = false;
        _adminCheckInfo = info;
      });
    } catch (e) {
      setState(() {
        _loadedAdminCheck = true;
        _canReadIncidencias = false;
        _adminCheckInfo = 'Error comprobando admin status: $e';
      });
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
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _setRead(String id, bool read) async {
    try {
      await FirebaseFirestore.instance.collection('incidencias').doc(id).update({'read': read});
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _delete(String id) async {
    try {
      await FirebaseFirestore.instance.collection('incidencias').doc(id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Incidencia eliminada'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Incidencias')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_loadedAdminCheck) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_canReadIncidencias) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No tienes permisos para ver incidencias.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_adminCheckInfo, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => _loadAdminStatus(),
                child: const Text('Recomprobar permisos'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('incidencias').orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Center(child: Text('No hay incidencias'));
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (c, i) {
            final d = docs[i];
            final m = d.data() as Map<String, dynamic>;
            final id = d.id;
            final title = (m['motivo'] ?? m['message'] ?? m['name'] ?? '').toString();
            final subtitle = (m['comentario'] ?? m['message'] ?? '').toString();
            final pdi = (m['pdiId'] ?? m['placeId'] ?? m['poiId'] ?? '').toString();
            final fromName = (m['fromName'] ?? m['name'] ?? '').toString();
            final isRead = m['read'] == true;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ListTile(
                title: Text(title.isNotEmpty ? title : fromName),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 6), Text(_formatTimestamp(m['timestamp']), style: const TextStyle(fontSize: 12, color: Colors.grey))]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(isRead ? Icons.check_circle : Icons.radio_button_unchecked), onPressed: () => _setRead(id, !isRead)),
                  if (pdi.isNotEmpty)
                    IconButton(icon: const Icon(Icons.place, color: Colors.blueAccent), onPressed: () {
                      Navigator.of(context).pushNamed('/home', arguments: {
                        'focus': {
                          if (pdi.isNotEmpty) 'docId': pdi,
                        }
                      });
                    }),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
                    final confirm = await showDialog<bool>(context: context, builder: (d) => AlertDialog(title: const Text('Eliminar incidencia'), content: const Text('¿Eliminar esta incidencia?'), actions: [TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('No')), TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Sí'))]));
                    if (confirm == true) await _delete(id);
                  }),
                ]),
                onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(fromName.isNotEmpty ? fromName : 'Incidencia'), content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(subtitle), const SizedBox(height: 8), Text(_formatTimestamp(m['timestamp']), style: const TextStyle(fontSize: 12, color: Colors.grey))])), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))])),
              ),
            );
          },
        );
      },
    );
  }
}
