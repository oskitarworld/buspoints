import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/utils/marker_utils.dart';
import 'package:myapp/models/user_route.dart';
import 'package:myapp/screens/profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class UserRoutesScreen extends StatefulWidget {
  const UserRoutesScreen({super.key});

  @override
  State<UserRoutesScreen> createState() => _UserRoutesScreenState();
}

class _UserRoutesScreenState extends State<UserRoutesScreen> {
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(appBar: AppBar(title: const Text('Mis rutas')), body: const Center(child: Text('No has iniciado sesión.')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Mis rutas')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('user_routes').where('createdBy', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) return const Center(child: Text('No has creado rutas aún.'));

          final privateDocs = docs.where((d) => (d.data()['isPrivate'] ?? false) == true).toList();
          final publicDocs = docs.where((d) => (d.data()['isPrivate'] ?? false) != true).toList();

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Text('Rutas privadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (privateDocs.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('No tienes rutas privadas.'))
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: privateDocs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _buildRouteTile(privateDocs[i]),
                  ),
                const Divider(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Text('Rutas públicas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                if (publicDocs.isEmpty)
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('No tienes rutas públicas.'))
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: publicDocs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) => _buildRouteTile(publicDocs[i]),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showRoutePreview(UserRoute r) async {
    // Capture a stable NavigatorState before awaiting to avoid using the
    // StatefulWidget's BuildContext across async gaps.
    final nav = Navigator.of(context);

    final Set<Marker> markers = {};
    for (var i = 0; i < r.pdis.length; i++) {
      try {
        final bmp = await createNumberedMarker(i + 1, size: 100, color: Colors.teal);
        markers.add(Marker(markerId: MarkerId(i.toString()), position: LatLng(r.pdis[i].lat, r.pdis[i].lng), icon: bmp, infoWindow: InfoWindow(title: 'Punto ${i + 1}')));
      } catch (_) {
        markers.add(Marker(markerId: MarkerId(i.toString()), position: LatLng(r.pdis[i].lat, r.pdis[i].lng), infoWindow: InfoWindow(title: 'Punto ${i + 1}')));
      }
    }

  // Guard against the widget being disposed while we awaited creating markers.
  if (!mounted) return;

  showDialog(
    context: nav.context,
        builder: (ctx) => AlertDialog(
              title: Text(r.name),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: LatLng(r.pdis.first.lat, r.pdis.first.lng), zoom: 13),
                    markers: markers,
                    polylines: {
                      Polyline(polylineId: const PolylineId('route'), points: r.pdis.map((p) => LatLng(p.lat, p.lng)).toList())
                    },
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                ElevatedButton(onPressed: () => _openInGoogleMaps(r), child: const Text('Navegar')),
              ],
            ));
  }

  Future<void> _openInGoogleMaps(UserRoute r) async {
    // Small helper to open Google Maps via url launcher; keep simple here.
    final waypoints = r.pdis.map((p) => '${p.lat},${p.lng}').join('/');
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&travelmode=driving&waypoints=${Uri.encodeComponent(waypoints)}');
    // Capture messenger before awaiting to avoid using BuildContext after an async gap.
    final messenger = ScaffoldMessenger.of(context);
    try {
      // ignore: avoid_dynamic_calls
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('No se pudo abrir Google Maps: $e')));
    }
  }

  Future<void> _deleteRoute(String docId, Map<String, dynamic> data) async {
    final owner = data['createdBy'] ?? '';
    // Capture messenger before awaiting dialogs or network calls to avoid
    // referencing BuildContext across async gaps.
    final messenger = ScaffoldMessenger.of(context);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != owner) {
      messenger.showSnackBar(const SnackBar(content: Text('No tienes permiso para eliminar esta ruta')));
      return;
    }
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eliminar ruta'),
      content: const Text('¿Seguro que deseas eliminar esta ruta? Esta acción es irreversible.'),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar'))],
    ));
    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('user_routes').doc(docId).delete();
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('Error eliminando ruta: $e')));
      }
    }
  }

  Future<void> _editRouteMetadata(String docId, Map<String, dynamic> data) async {
    final nameController = TextEditingController(text: data['name'] ?? '');
    final descController = TextEditingController(text: data['description'] ?? '');
    bool isPublic = data['isPublic'] == true;
    // Capture messenger before awaiting so we can use it after network calls.
    final messenger = ScaffoldMessenger.of(context);
    final res = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Editar ruta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre')),
          TextFormField(controller: descController, decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 12),
          Row(children: [const Text('Ruta pública'), const Spacer(), StatefulBuilder(builder: (c, setState) { return Switch(value: isPublic, onChanged: (v) => setState(() => isPublic = v)); })])
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar'))],
    ));
    if (res == true) {
      try {
        await FirebaseFirestore.instance.collection('user_routes').doc(docId).update({
          'name': nameController.text.trim(),
          'description': descController.text.trim(),
          // Don't directly flip 'approved' here — if making public, mark needsApproval true and isPrivate false.
          'isPrivate': !isPublic,
          'needsApproval': isPublic,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Ruta actualizada')));
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(SnackBar(content: Text('Error actualizando ruta: $e')));
      }
    }
  }

  Widget _buildRouteTile(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final name = data['name'] ?? '(sin nombre)';
    final desc = data['description'] ?? '';
  final approved = data['approved'] == true;
  final isPrivate = data['isPrivate'] == true;
    final pdis = (data['pdis'] as List? ?? []).length;
    return ListTile(
      title: Text(name),
      subtitle: Text('$pdis puntos • ${approved ? 'Aprobada' : 'Pendiente'}\n$desc'),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit, color: Colors.orange), tooltip: 'Editar ruta', onPressed: () => _editRouteMetadata(d.id, data)),
          IconButton(icon: const Icon(Icons.format_list_numbered, color: Colors.blue), tooltip: 'Editar puntos', onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen(initialInnerTabIndex: 3)));
          }),
          IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), tooltip: 'Eliminar ruta', onPressed: () => _deleteRoute(d.id, data)),
      // For private routes always show a green tick. Public routes show
      // a green tick if approved or an hourglass if pending approval.
      isPrivate
        ? const Icon(Icons.check_circle, color: Colors.green)
        : (approved ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.hourglass_top, color: Colors.orange)),
        ],
      ),
      onTap: () {
        try {
          final userRoute = UserRoute.fromDoc(d);
          _showRoutePreview(userRoute);
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se puede mostrar la vista previa de la ruta')));
        }
      },
    );
  }
}
