import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'package:rxdart/rxdart.dart';
import 'package:myapp/services/map_refresh_service.dart';

class PoiHistoryScreen extends StatelessWidget {
  const PoiHistoryScreen({super.key});

  Future<String> _getUserEmail(String uid) async {
    if (uid.isEmpty) return 'Usuario Desconocido';
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return userDoc.exists ? (userDoc.data()!['email'] ?? 'Email no encontrado') : 'Usuario no encontrado';
    } catch (e) {
      return 'Error cargando email';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de PDIs aprobados'),
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot>>(
        stream: Rx.combineLatest2<QuerySnapshot<Map<String, dynamic>>, QuerySnapshot<Map<String, dynamic>>, List<QueryDocumentSnapshot>>(
          FirebaseFirestore.instance
              .collection('Pdis_full')
              .where('approvedAt', isNotEqualTo: null)
              .orderBy('approvedAt', descending: true)
              .limit(200)
              .snapshots(),
          FirebaseFirestore.instance
              .collection('pois')
              .where('approvedAt', isNotEqualTo: null)
              .orderBy('approvedAt', descending: true)
              .limit(200)
              .snapshots(),
          (snapFull, snapOld) => <QueryDocumentSnapshot>[...snapFull.docs, ...snapOld.docs],
        ).handleError((e) {
          // If both fail, let the stream emit an empty list
          developer.log('Error merging Pdis_full/pois snapshots: $e', name: 'PoiHistoryScreen');
        }),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snapshot.data!;
          if (docs.isEmpty) return const Center(child: Text('No hay PDIs aprobados recientemente.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final title = data['name'] ?? 'Sin nombre';
              final approvedAt = data['approvedAt'] as Timestamp?;
              final submittedBy = (data['submittedBy'] ?? '').toString();

              // Format approvedAt without seconds
              String formattedDate = 'Desconocida';
              if (approvedAt != null) {
                final dt = DateTime.fromMillisecondsSinceEpoch(approvedAt.millisecondsSinceEpoch).toLocal();
                formattedDate = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: ListTile(
                  onTap: () {
                    // Navigate to home map focusing on this POI
                    double? lat;
                    double? lng;
                    try {
                      if (data['latitude'] != null && data['longitude'] != null) {
                        final rawLat = data['latitude'];
                        final rawLng = data['longitude'];
                        lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
                        lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
                      } else if (data['geopoint'] is GeoPoint) {
                        final gp = data['geopoint'] as GeoPoint;
                        lat = gp.latitude;
                        lng = gp.longitude;
                      }
                    } catch (_) { lat = null; lng = null; }
                    Navigator.of(context).pushNamed('/home', arguments: {
                      'focus': {
                        if (lat != null) 'lat': lat,
                        if (lng != null) 'lng': lng,
                        'name': title,
                        'docId': doc.id,
                      }
                    });
                  },
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      FutureBuilder<String>(
                        future: _getUserEmail(submittedBy),
                        builder: (context, snapUser) {
                          final email = snapUser.data ?? (submittedBy.isNotEmpty ? submittedBy : 'Desconocido');
                          return Text('Por: $email');
                        },
                      ),
                      const SizedBox(height: 6),
                      Text('Fecha: $formattedDate'),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    tooltip: 'Eliminar PDI',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Eliminar PDI'),
                          content: const Text('¿Seguro que quieres eliminar este PDI? Esta acción no se puede deshacer.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
                          ],
                        ),
                      );

                      if (confirm == true) {
                              try {
                                // Delete the specific document reference (works whether
                                // it lives in Pdis_full or pois).
                                await doc.reference.delete();
                          // Notify map to refresh so marker disappears immediately
                          try { MapRefreshService.instance.requestRefresh(); } catch (_) {}
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('PDI eliminado'),
                                content: const Text('El PDI ha sido eliminado correctamente.'),
                                actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))],
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Error'),
                                content: Text('Error eliminando PDI: $e'),
                                actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))],
                              ),
                            );
                          }
                        }
                      }
                    },
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
