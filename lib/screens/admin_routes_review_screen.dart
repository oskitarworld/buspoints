import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/utils/marker_utils.dart';
// Note: route_service is not imported here because admin actions call the
// server-side callable. Keep code minimal.

class AdminRoutesReviewScreen extends StatefulWidget {
  const AdminRoutesReviewScreen({super.key});

  @override
  State<AdminRoutesReviewScreen> createState() => _AdminRoutesReviewScreenState();
}

class _AdminRoutesReviewScreenState extends State<AdminRoutesReviewScreen> {
  // No local RouteService usage currently; approvals are handled server-side
  // via the callable `adminApproveRoute` to avoid client-side privileged writes.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Revisión de rutas')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    // Only show pending submissions that require approval (public submissions).
    stream: FirebaseFirestore.instance.collection('user_routes')
      .where('approved', isEqualTo: false)
      .where('needsApproval', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) {
            // Show the error (e.g. permission denied) so admins can diagnose issues.
            return Center(child: Text('Error al cargar rutas: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No hay rutas pendientes.'));
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final d = docs[i];
              return RouteListItem(routeDoc: d, onEdit: (data) => _editRoute(d.id, data), onPreview: () => _showPreview(d.id, d.data(), d.data()['name'] ?? '(sin nombre)'));
            },
          );
        },
      ),
    );
  }

  Future<void> _showPreview(String routeId, Map<String, dynamic> data, String title) async {
    // Capture messenger before any awaits in this method to avoid using
    // BuildContext after async gaps (we create markers below which await).
    final messenger = ScaffoldMessenger.of(context);
    final List<dynamic> pdis = data['pdis'] as List<dynamic>? ?? [];
    if (pdis.isEmpty) {
      showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: const Text('La ruta no tiene puntos')));
      return;
    }

  // Capture NavigatorState before awaiting marker creation so we can safely
  // show dialogs after async work without referencing the original BuildContext.
  final nav = Navigator.of(context);
  final Set<Marker> markers = {};
    for (var i = 0; i < pdis.length; i++) {
      final p = pdis[i] as Map<String, dynamic>;
      final lat = (p['lat'] as num).toDouble();
      final lng = (p['lng'] as num).toDouble();
      try {
        final bmp = await createNumberedMarker(i + 1, size: 100, color: Colors.teal);
        markers.add(Marker(markerId: MarkerId('p_$i'), position: LatLng(lat, lng), icon: bmp, infoWindow: InfoWindow(title: 'Punto ${i + 1}', snippet: p['name'] ?? '')));
      } catch (_) {
        markers.add(Marker(markerId: MarkerId('p_$i'), position: LatLng(lat, lng), infoWindow: InfoWindow(title: 'Punto ${i + 1}', snippet: p['name'] ?? '')));
      }
    }

  // Guard against the widget being disposed while we awaited marker creation.
  if (!mounted) return;

  showDialog(
    context: nav.context,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                height: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(target: LatLng((pdis.first['lat'] as num).toDouble(), (pdis.first['lng'] as num).toDouble()), zoom: 13),
                          markers: markers,
                          polylines: {
                            Polyline(polylineId: const PolylineId('route'), points: pdis.map((p) => LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble())).toList())
                          },
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(data['description'] ?? '', style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                    ElevatedButton(onPressed: () async {
                      try {
                        final functions = FirebaseFunctions.instance;
                        final callable = functions.httpsCallable('adminApproveRoute');
                        // Capture the preview dialog's NavigatorState before awaiting
                        final navBtn = Navigator.of(ctx);
                        await callable.call(<String, dynamic>{'routeId': routeId, 'makePublic': true});
                        // Close the preview dialog using the captured NavigatorState
                        navBtn.pop();
                        messenger.showSnackBar(const SnackBar(content: Text('Ruta aprobada')));
                      } catch (e) {
                        messenger.showSnackBar(SnackBar(content: Text('Error aprobando ruta: $e')));
                      }
                    }, child: const Text('Aprobar')),
              ],
            ));
  }

  Future<void> _editRoute(String routeId, Map<String, dynamic> data) async {
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final descCtrl = TextEditingController(text: data['description'] ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar ruta'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
          TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descripción')),
          // Note: admin edit dialog no longer exposes a public/private switch.
          // Approval (making public) should happen via the 'Aprobar' action.
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('user_routes').doc(routeId).update({
        'name': nameCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta actualizada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error actualizando ruta: $e')));
    }
  }
}

// Top-level widget for displaying a single route in the admin list. Kept
// as a top-level type so it doesn't accidentally capture the admin screen's
// State and to keep lifecycle boundaries clear.
class RouteListItem extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> routeDoc;
  final void Function(Map<String, dynamic> data) onEdit;
  final VoidCallback onPreview;
  const RouteListItem({super.key, required this.routeDoc, required this.onEdit, required this.onPreview});

  @override
  State<RouteListItem> createState() => _RouteListItemState();
}

class _RouteListItemState extends State<RouteListItem> {
  String? _creatorName;

  @override
  void initState() {
    super.initState();
    _resolveCreatorName();
  }

  Future<void> _resolveCreatorName() async {
    final data = widget.routeDoc.data();
    // Check common fields first
    final raw = (data['createdByName'] ?? data['createdByDisplayName'] ?? data['createdBy'] ?? data['authorName'] ?? data['displayName'])?.toString();
    if (raw != null && raw.isNotEmpty && !_looksLikeUid(raw)) {
      _creatorName = raw;
      if (mounted) setState(() {});
      return;
    }
    final userId = (data['createdBy'] ?? '')?.toString();
    if (userId == null || userId.isEmpty) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final udata = doc.data();
      final candidate = udata != null ? (udata['displayName'] ?? udata['name'] ?? udata['username'] ?? '')?.toString() : '';
      if (candidate != null && candidate.isNotEmpty) {
        _creatorName = candidate;
        if (mounted) setState(() {});
      } else {
        // fallback to showing userId if nothing else
        _creatorName = userId;
        if (mounted) setState(() {});
      }
    } catch (_) {
      // ignore
      if (mounted) setState(() { _creatorName = userId; });
    }
  }

  bool _looksLikeUid(String s) {
    // crude check: Firestore UIDs are typically long alphanumeric strings
    return RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(s);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.routeDoc.data();
    final name = data['name'] ?? '(sin nombre)';
    final desc = data['description'] ?? '';
    final pdis = (data['pdis'] as List? ?? []).length;
    final creator = _creatorName ?? (data['createdBy'] ?? '');
    return ListTile(
      title: Text(name),
      subtitle: Text('$pdis puntos • $desc\nCreada por: $creator'),
      isThreeLine: true,
      onTap: widget.onPreview,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.orange),
            tooltip: 'Editar',
            onPressed: () => widget.onEdit(data),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final functions = FirebaseFunctions.instance;
                final callable = functions.httpsCallable('adminApproveRoute');
                await callable.call(<String, dynamic>{'routeId': widget.routeDoc.id, 'makePublic': true});
                messenger.showSnackBar(const SnackBar(content: Text('Ruta aprobada')));
              } catch (e) {
                messenger.showSnackBar(SnackBar(content: Text('Error aprobando ruta: $e')));
              }
            },
            child: const Text('Aprobar'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
                title: const Text('Rechazar ruta'),
                content: const Text('¿Deseas eliminar esta ruta? Esta acción no se puede deshacer.'),
                actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar'))],
              ));
              if (confirm == true) {
                await FirebaseFirestore.instance.collection('user_routes').doc(widget.routeDoc.id).delete();
                messenger.showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
