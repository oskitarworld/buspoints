// Visual editor screen extracted from profile_screen.dart
// Allows editing/renumbering/deleting route points on a map with a reorderable list.
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/utils/marker_utils.dart';
import 'package:myapp/models/user_route.dart';

class EditRoutePointsScreen extends StatefulWidget {
  final UserRoute route;
  const EditRoutePointsScreen({super.key, required this.route});

  @override
  State<EditRoutePointsScreen> createState() => _EditRoutePointsScreenState();
}

class _EditRoutePointsScreenState extends State<EditRoutePointsScreen> {
  late List<UserRoutePoint> points;
  final Map<MarkerId, Marker> _markers = {};
  late GoogleMapController _mapController;

  @override
  void initState() {
    super.initState();
    points = widget.route.pdis.map((p) => UserRoutePoint(lat: p.lat, lng: p.lng, name: p.name)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildMarkers());
  }

  Future<void> _rebuildMarkers() async {
    final Map<MarkerId, Marker> newMarkers = {};
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final id = MarkerId('pt_$i');
      try {
        final bmp = await createNumberedMarker(i + 1, size: 90, color: Colors.blueAccent);
        newMarkers[id] = Marker(markerId: id, position: LatLng(p.lat, p.lng), icon: bmp, draggable: true, infoWindow: InfoWindow(title: p.name ?? 'Punto ${i + 1}'), onDragEnd: (pos) => _onMarkerDragEnd(i, pos));
      } catch (_) {
        newMarkers[id] = Marker(markerId: id, position: LatLng(p.lat, p.lng), draggable: true, infoWindow: InfoWindow(title: p.name ?? 'Punto ${i + 1}'), onDragEnd: (pos) => _onMarkerDragEnd(i, pos));
      }
    }
    setState(() { _markers
      ..clear()
      ..addAll(newMarkers);
    });
  }

  void _onMarkerDragEnd(int index, LatLng pos) {
    setState(() {
      points[index] = UserRoutePoint(lat: pos.latitude, lng: pos.longitude, name: points[index].name);
      _rebuildMarkers();
    });
  }

  Future<void> _editPointName(int index) async {
    final ctrl = TextEditingController(text: points[index].name ?? 'Punto ${index + 1}');
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Editar nombre del punto'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Nombre')),
      actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Guardar'))],
    ));
    if (ok == true) {
      setState(() { points[index] = UserRoutePoint(lat: points[index].lat, lng: points[index].lng, name: ctrl.text.trim()); _rebuildMarkers(); });
    }
  }

  Future<void> _save() async {
    if (points.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Una ruta debe tener al menos 2 puntos')));
      return;
    }
    try {
      final newPdis = points.map((p) => p.toMap()).toList();
      await FirebaseFirestore.instance.collection('user_routes').doc(widget.route.id).update({'pdis': newPdis, 'updatedAt': FieldValue.serverTimestamp()});
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error guardando puntos: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editar puntos - ${widget.route.name}'), actions: [TextButton(onPressed: _save, child: const Text('Guardar', style: TextStyle(color: Colors.white)) )]),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: LatLng(points.first.lat, points.first.lng), zoom: 13),
                  markers: Set<Marker>.of(_markers.values),
                  onMapCreated: (c) { _mapController = c; },
                  onTap: (latLng) async {
                    if (points.length >= 20) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 20 puntos por ruta')));
                      return;
                    }
                    final defaultName = 'Punto ${points.length + 1}';
                    final nameCtrl = TextEditingController(text: defaultName);
                    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
                      title: const Text('Nombre del punto'),
                      content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
                      actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Guardar'))],
                    ));
                    if (ok == true) {
                      setState(() {
                        points.add(UserRoutePoint(lat: latLng.latitude, lng: latLng.longitude, name: nameCtrl.text.trim().isEmpty ? defaultName : nameCtrl.text.trim()));
                        _rebuildMarkers();
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Center(
              child: Text(
                'Toca el mapa para añadir más puntos',
                style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodySmall?.color),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: ReorderableListView(
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = points.removeAt(oldIndex);
                  points.insert(newIndex, item);
                  _rebuildMarkers();
                });
              },
              children: [
                for (var i = 0; i < points.length; i++) _buildPointTile(i),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointTile(int i) {
    final p = points[i];
    return ListTile(
      key: ValueKey('edit_pt_$i'),
      leading: CircleAvatar(child: Text('${i + 1}')),
      title: Text(p.name ?? 'Punto ${i + 1}'),
      subtitle: Text('${p.lat.toStringAsFixed(6)}, ${p.lng.toStringAsFixed(6)}'),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.edit), onPressed: () => _editPointName(i)),
        IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
          final confirm = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
            title: const Text('Eliminar punto'),
            content: const Text('¿Deseas eliminar este punto?'),
            actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Eliminar'))],
          ));
          if (confirm == true) {
            setState(() { points.removeAt(i); _rebuildMarkers(); });
          }
        }),
      ]),
      onTap: () async {
        await _mapController.animateCamera(CameraUpdate.newLatLng(LatLng(p.lat, p.lng)));
      },
    );
  }
}
