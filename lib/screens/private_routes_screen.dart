import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/services/route_service.dart';
import 'package:myapp/models/user_route.dart';
import 'package:myapp/screens/create_route_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/utils/marker_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PrivateRoutesScreen extends StatefulWidget {
  const PrivateRoutesScreen({super.key});

  @override
  State<PrivateRoutesScreen> createState() => _PrivateRoutesScreenState();
}

class _PrivateRoutesScreenState extends State<PrivateRoutesScreen> {
  final RouteService _routeService = RouteService();
  late final String _uid;
  Future<List<UserRoute>>? _future;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid ?? '';
  if (_uid.isNotEmpty) _future = _routeService.fetchPrivateRoutesForUser(_uid);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _routeService.fetchPrivateRoutesForUser(_uid);
    });
  }

  // Note: deletion is handled inline in the UI (calls to _routeService.deleteRoute)

  Future<void> _showPreview(UserRoute r) async {
    final Set<Marker> markers = {};
    for (var i = 0; i < r.pdis.length; i++) {
      try {
        final bmp = await createNumberedMarker(i + 1, size: 100, color: Colors.teal);
        markers.add(Marker(markerId: MarkerId(i.toString()), position: LatLng(r.pdis[i].lat, r.pdis[i].lng), icon: bmp, infoWindow: InfoWindow(title: 'Punto ${i + 1}')));
      } catch (_) {
        markers.add(Marker(markerId: MarkerId(i.toString()), position: LatLng(r.pdis[i].lat, r.pdis[i].lng), infoWindow: InfoWindow(title: 'Punto ${i + 1}')));
      }
    }
    if (!mounted) return;

    await showDialog(context: context, builder: (ctx) => AlertDialog(
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
        ElevatedButton(onPressed: () async {
          Navigator.of(ctx).pop();
          await _openInGoogleMaps(r);
        }, child: const Text('Navegar')),
      ],
    ));
  }

  Future<void> _openInGoogleMaps(UserRoute r) async {
    if (r.pdis.isEmpty) return;
    try {
      final coords = r.pdis.map((p) => '${p.lat},${p.lng}').toList();
      final origin = coords.first;
      final destination = coords.last;
      String waypoints = '';
      if (coords.length > 2) {
        waypoints = coords.sublist(1, coords.length - 1).join('|');
      }

      final uriString = 'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}${waypoints.isNotEmpty ? '&waypoints=${Uri.encodeComponent(waypoints)}' : ''}&travelmode=driving';
      final uri = Uri.parse(uriString);
      try {
        if (_uid.isNotEmpty) {
          FirebaseFirestore.instance.collection('users').doc(_uid).collection('history').add({
            'action': 'open_route_navigation',
            'routeId': r.id,
            'routeName': r.name,
            'pointsCount': r.pdis.length,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {}

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir Google Maps')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error abriendo Google Maps: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return Scaffold(appBar: AppBar(title: const Text('Mis Rutas Privadas')), body: const Center(child: Text('Debes iniciar sesión')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Rutas privadas')),
      body: FutureBuilder<List<UserRoute>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final routes = snap.data ?? [];
          if (routes.isEmpty) return const Center(child: Text('No tienes rutas privadas'));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: routes.length,
              itemBuilder: (ctx, i) {
                final r = routes[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            await _showPreview(r);
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 2),
                              Text('${r.pdis.length} puntos • ${r.description}', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          if (!mounted) return;
                          final nav = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final res = await nav.push<bool?>(MaterialPageRoute(builder: (ctx) => CreateRouteScreen(routeToEdit: r)));
                          if (res == true) {
                            await _refresh();
                            if (!mounted) return;
                            messenger.showSnackBar(const SnackBar(content: Text('Ruta actualizada')));
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          if (!mounted) return;
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
                            title: const Text('Eliminar ruta'),
                            content: const Text('¿Eliminar esta ruta privada? Esta acción no se puede deshacer.'),
                            actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Eliminar'))],
                          ));
                          if (ok == true) {
                            try {
                              await _routeService.deleteRoute(r.id);
                              if (!mounted) return;
                              messenger.showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
                              await _refresh();
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(SnackBar(content: Text('No se pudo eliminar la ruta: $e')));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

