import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/map_refresh_service.dart';

class ApprovedPoisScreen extends StatefulWidget {
  final String uid;
  const ApprovedPoisScreen({super.key, required this.uid});

  @override
  State<ApprovedPoisScreen> createState() => _ApprovedPoisScreenState();
}

class _ApprovedPoisScreenState extends State<ApprovedPoisScreen> {
  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('PDIs aprobados')),
      body: StreamBuilder<QuerySnapshot>(
  stream: firestore.collection('users').doc(widget.uid).collection('added_pois').orderBy('approvedAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('No hay PDIs aprobados.'));
          final docs = snap.data!.docs;
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final p = d.data() as Map<String, dynamic>;
              final poiId = (p['poiId'] ?? d.id).toString();
              final name = (p['name'] ?? '').toString();
              final category = (p['category'] ?? '').toString();

              // Extract coordinates if present
              double? lat = (p['latitude'] is num) ? (p['latitude'] as num).toDouble() : null;
              double? lng = (p['longitude'] is num) ? (p['longitude'] as num).toDouble() : null;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(category, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                onTap: () {
                  Navigator.of(context).pushNamed('/home', arguments: {'focus': {if (lat != null) 'lat': lat, if (lng != null) 'lng': lng, 'name': name, 'category': category, 'docId': poiId}});
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.map, color: Colors.blue),
                      tooltip: 'Ver en mapa',
                      onPressed: () {
                        Navigator.of(context).pushNamed('/home', arguments: {'focus': {if (lat != null) 'lat': lat, if (lng != null) 'lng': lng, 'name': name, 'category': category, 'docId': poiId}});
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Eliminar del historial',
                          onPressed: () async {
                            final currentUid = widget.uid;
                            // The dialog uses a nested context; guard with mounted immediately after.
                            // ignore: use_build_context_synchronously
                            final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Eliminar del historial'), content: const Text('¿Eliminar este PDI del historial? (no se eliminará el PDI canónico)'), actions: [TextButton(onPressed: () => Navigator.of(c).pop(false), child: Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(c).pop(true), child: Text('Eliminar'))]));
                            if (!mounted) return;
                            if (confirm != true) return;
                            try {
                              final histRef = firestore.collection('users').doc(currentUid).collection('history_places');
                              final addedRef = firestore.collection('users').doc(currentUid).collection('added_pois');
                              final toDelete = <DocumentReference>[];
                              final q1 = await histRef.where('poiId', isEqualTo: poiId).get();
                              if (!mounted) return;
                              for (final doc in q1.docs) {
                                toDelete.add(doc.reference);
                              }
                              final q2 = await histRef.where('sourceId', isEqualTo: poiId).get();
                              if (!mounted) return;
                              for (final doc in q2.docs) {
                                if (!toDelete.contains(doc.reference)) {
                                  toDelete.add(doc.reference);
                                }
                              }
                              final maybe = await histRef.doc(poiId).get();
                              if (!mounted) return;
                              if (maybe.exists && !toDelete.contains(maybe.reference)) {
                                toDelete.add(maybe.reference);
                              }
                              final addedDoc = await addedRef.doc(poiId).get();
                              if (!mounted) return;
                              if (addedDoc.exists && !toDelete.contains(addedDoc.reference)) {
                                toDelete.add(addedDoc.reference);
                              }
                              if (toDelete.isEmpty) {
                                if (!mounted) return;
                                // ignore: use_build_context_synchronously
                                showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Nada que eliminar'), content: const Text('No se encontró entrada de historial asociada.'), actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cerrar'))]));
                                return;
                              }
                              final batch = firestore.batch();
                              for (final r in toDelete) {
                                batch.delete(r);
                              }
                              await batch.commit();
                              if (!mounted) return;
                              // Request the map to refresh so deleted POIs disappear immediately
                              try { MapRefreshService.instance.requestRefresh(); } catch (_) {}
                              if (!mounted) return;
                              // ignore: use_build_context_synchronously
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrada del historial eliminada.'), backgroundColor: Colors.green));
                            } catch (e) {
                              if (!mounted) return;
                              // ignore: use_build_context_synchronously
                              showDialog(context: context, builder: (c) => AlertDialog(title: const Text('Error'), content: Text('No se pudo eliminar: $e'), actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cerrar'))]));
                            }
                          },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
