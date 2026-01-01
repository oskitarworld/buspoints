// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/models/user_route.dart';
import 'package:myapp/services/route_service.dart';
import 'package:myapp/utils/marker_utils.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:myapp/firebase_options.dart';

class CreateRouteScreen extends StatefulWidget {
  const CreateRouteScreen({super.key});

  @override
  State<CreateRouteScreen> createState() => _CreateRouteScreenState();
}

class _CreateRouteScreenState extends State<CreateRouteScreen> {
  final RouteService _routeService = RouteService();
  final List<UserRoutePoint> _points = [];
  final Map<MarkerId, Marker> _markers = {};
  final Completer<GoogleMapController> _controller = Completer();
  bool _saving = false;
  MapType _mapType = MapType.normal;
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  static const CameraPosition _initial = CameraPosition(target: LatLng(-34.0, -58.0), zoom: 12);

  void _onMapTap(LatLng latLng) {
    // Prompt for a name when adding a new point. Default value is the
    // next point number (important requirement).
    _promptAndAddPoint(latLng);
  }

  Future<void> _promptAndAddPoint(LatLng latLng) async {
    if (_points.length >= 20) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Máximo 20 puntos por ruta')));
      return;
    }

  final defaultName = 'Punto ${_points.length + 1}';
  final nameController = TextEditingController(text: defaultName);

    // Capture a NavigatorState before awaiting to avoid using the BuildContext
    // across async gaps (use_build_context_synchronously).
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: nav.context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nombre del punto'),
        content: TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre del punto')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar')),
        ],
      ),
    );

    if (ok != true) return;

    final name = nameController.text.trim();
    final p = UserRoutePoint(lat: latLng.latitude, lng: latLng.longitude, name: name.isEmpty ? defaultName : name);
    setState(() {
      _points.add(p);
    });
    await _rebuildMarkers();
  }

  Future<void> _moveCamera(LatLng target, {double zoom = 16}) async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: zoom)));
  }

  Future<void> _locateMe() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Servicios de ubicación desactivados')));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permiso de ubicación denegado')));
        return;
      }

      // Use the newer locationSettings parameter instead of desiredAccuracy (deprecated)
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final target = LatLng(pos.latitude, pos.longitude);
      await _moveCamera(target, zoom: 16);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo obtener la ubicación: $e')));
    }
  }

  Future<void> _centerToUserOnStart() async {
    // Wait until the map controller is ready, then try to center on user location.
    try {
      await _controller.future;
      await Future.delayed(const Duration(milliseconds: 250));
      await _locateMe();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searchResults = [];
    });
    try {
      final apiKey = DefaultFirebaseOptions.currentPlatform.apiKey;
      final encoded = Uri.encodeComponent(query);
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=$encoded&key=$apiKey');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        final results = (data['results'] as List<dynamic>? ?? []).take(5).map((r) => {
              'formatted_address': r['formatted_address'],
              'location': r['geometry']['location']
            }).toList();
        setState(() {
          _searchResults = List<Map<String, dynamic>>.from(results);
        });
      } else {
        // ignore
      }
    } catch (e) {
      // ignore
    } finally {
      // no-op: we don't currently read a searching flag in the UI
    }
  }

  Future<void> _rebuildMarkers() async {
    final Map<MarkerId, Marker> newMarkers = {};
    for (var i = 0; i < _points.length; i++) {
      final point = _points[i];
      final id = MarkerId('p_$i');
      try {
        final bmp = await createNumberedMarker(i + 1, size: 120, color: Colors.blue);
        final marker = Marker(
          markerId: id,
          position: LatLng(point.lat, point.lng),
          icon: bmp,
          infoWindow: InfoWindow(title: 'Punto ${i + 1}', snippet: point.name),
          onTap: () => _onMarkerTap(i),
        );
        newMarkers[id] = marker;
      } catch (e) {
        // Fallback: marker without custom icon
        final marker = Marker(
          markerId: id,
          position: LatLng(point.lat, point.lng),
          infoWindow: InfoWindow(title: 'Punto ${i + 1}', snippet: point.name),
          onTap: () => _onMarkerTap(i),
        );
        newMarkers[id] = marker;
      }
    }
    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });
  }

  void _removePoint(int index) {
    setState(() {
      _points.removeAt(index);
    });
    _rebuildMarkers();
  }

  void _onMarkerTap(int index) async {
    // Capture NavigatorState early so we can use a stable context across awaits
    final nav = Navigator.of(context);
    final choice = await showModalBottomSheet<String>(
      context: nav.context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text('Punto ${index + 1}')),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Eliminar punto'),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Editar nombre'),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cerrar'),
                onTap: () => Navigator.of(ctx).pop('close'),
              ),
            ],
          ),
        );
      },
    );

    if (choice == 'delete') {
      _removePoint(index);
    } else if (choice == 'edit') {
      final nameCtrl = TextEditingController(text: _points[index].name ?? '');
      final ok = await showDialog<bool>(
        context: nav.context,
        builder: (dctx) => AlertDialog(
          title: const Text('Editar nombre'),
          content: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
          actions: [
            TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Guardar')),
          ],
        ),
      );
      if (ok == true) {
        setState(() {
          _points[index] = UserRoutePoint(lat: _points[index].lat, lng: _points[index].lng, name: nameCtrl.text.trim());
        });
        await _rebuildMarkers();
      }
    }
  }

  Future<void> _saveRoute() async {
    if (_points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Debes seleccionar al menos 2 puntos')));
      return;
    }

    final nameController = TextEditingController();
    final descController = TextEditingController();

    bool isPublicChoice = true;
    // Capture messenger/navigator before any awaits to avoid using BuildContext
    // across async gaps (use_build_context_synchronously).
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setState) => AlertDialog(
        title: const Text('Guardar ruta'),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx2).size.height * 0.6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre')),
                TextField(controller: descController, decoration: const InputDecoration(labelText: 'Descripción')),
                const SizedBox(height: 8),
                // Use SegmentedButton (single-selection) instead of deprecated RadioListTile API.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(value: true, label: Text('Pública')),
                        ButtonSegment<bool>(value: false, label: Text('Privada')),
                      ],
                      selected: <bool>{isPublicChoice},
                      onSelectionChanged: (Set<bool> newSelection) {
                        final val = newSelection.isNotEmpty ? newSelection.first : true;
                        setState(() => isPublicChoice = val);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isPublicChoice
                          ? 'Ruta pública: será revisada por administración y, si se aprueba, se mostrará públicamente.'
                          : 'Ruta privada: no necesita aprobación y solo será visible para ti.',
                      style: Theme.of(ctx2).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx2).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(ctx2).pop(true), child: const Text('Guardar')),
        ],
      )),
    );

  if (ok != true) return;

    // Require non-empty name
    final name = nameController.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('La ruta necesita un nombre (por ejemplo: "Visita Barcelona")')));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Debes iniciar sesión para guardar rutas')));
      return;
    }

  setState(() => _saving = true);
    try {
      final id = await _routeService.createRoute(name: name, description: descController.text.trim(), uid: uid, pdis: _points, isPublicChoice: isPublicChoice);
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Ruta guardada: $id')));
      navigator.pop();
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Error guardando ruta: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _rebuildMarkers();
    // Try to center map on user's current location once the map is ready.
    _centerToUserOnStart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear ruta'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saving ? null : _saveRoute),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initial,
            onMapCreated: (c) => _controller.complete(c),
            onTap: _onMapTap,
            mapType: _mapType,
            markers: Set<Marker>.of(_markers.values),
            polylines: {
              Polyline(polylineId: const PolylineId('route'), points: _points.map((p) => LatLng(p.lat, p.lng)).toList(), color: Colors.blue)
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),
          // Search bar
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(hintText: 'Buscar lugar...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                      onSubmitted: (v) => _performSearch(v),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.search), onPressed: () => _performSearch(_searchCtrl.text)),
                ],
              ),
            ),
          ),
          if (_searchResults.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              top: 68,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final r = _searchResults[i];
                    return ListTile(
                      title: Text(r['formatted_address'] ?? ''),
                      onTap: () async {
                        final loc = r['location'];
                        final lat = (loc['lat'] as num).toDouble();
                        final lng = (loc['lng'] as num).toDouble();
                        // Ask for a name before adding the point (same flow as tapping the map)
                        await _promptAndAddPoint(LatLng(lat, lng));
                        setState(() {
                          _searchResults = [];
                          _searchCtrl.clear();
                        });
                        await _moveCamera(LatLng(lat, lng), zoom: 16);
                      },
                    );
                  },
                ),
              ),
            ),
          if (_points.isNotEmpty)
            Positioned(
              right: 12,
              bottom: 120,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text('Puntos: ${_points.length}'),
                ),
              ),
            ),
          // Small aesthetic banner at bottom
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withAlpha((0.95 * 255).round()), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)]),
                child: const Text('Toca el mapa para añadir puntos • Mantén pulsado un marcador para más opciones', style: TextStyle(fontSize: 13), textAlign: TextAlign.center),
              ),
            ),
          ),
          // Floating action buttons: save (icon-only), locate and satellite toggle.
          // Positioned to avoid overlapping the bottom banner and points card.
          Positioned(
            right: 16,
            bottom: 80,
            child: FloatingActionButton(
              heroTag: 'save_route',
              onPressed: _saving ? null : _saveRoute,
              tooltip: 'Guardar ruta',
              child: const Icon(Icons.check),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 80,
            child: FloatingActionButton(
              heroTag: 'locate',
              onPressed: _locateMe,
              tooltip: 'Mi ubicación',
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 150,
            child: FloatingActionButton(
              heroTag: 'maptype',
              onPressed: () {
                setState(() {
                  _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal;
                });
              },
              tooltip: 'Cambiar vista',
              child: Icon(_mapType == MapType.normal ? Icons.satellite : Icons.map),
            ),
          ),
          if (_saving)
            const Center(
              child: CircularProgressIndicator(),
            )
        ],
      ),
      // Replace the previous FAB layout with three floating circular buttons
      // placed over the map: save (icon-only), locate, and satellite toggle.
      // They are positioned so they don't overlap the bottom banner and the
      // points card.
    );
  }
}
