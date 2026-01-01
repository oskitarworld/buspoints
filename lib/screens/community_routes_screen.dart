import 'package:flutter/material.dart';
import 'package:myapp/services/route_service.dart';
import 'package:myapp/models/user_route.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/utils/marker_utils.dart';

class CommunityRoutesScreen extends StatefulWidget {
  const CommunityRoutesScreen({super.key});

  @override
  State<CommunityRoutesScreen> createState() => _CommunityRoutesScreenState();
}

class _CommunityRoutesScreenState extends State<CommunityRoutesScreen> {
  final RouteService _routeService = RouteService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rutas de la comunidad')),
      body: FutureBuilder<List<UserRoute>>(
        future: _routeService.fetchPublicRoutes(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final routes = snap.data ?? [];
          if (routes.isEmpty) return const Center(child: Text('No hay rutas publicadas aún'));
          return ListView.builder(
            itemCount: routes.length,
            itemBuilder: (ctx, i) {
              final r = routes[i];
              return ListTile(
                title: Text(r.name),
                subtitle: Text('${r.pdis.length} puntos • ${r.description}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showPreview(r),
              );
            },
          );
        },
      ),
    );
  }

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

  // Guard against widget disposal while we awaited marker creation.
  if (!mounted) return;

  showDialog(
        context: context,
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
    if (r.pdis.isEmpty) return;
    try {
      final coords = r.pdis.map((p) => '${p.lat},${p.lng}').toList();
      final origin = coords.first;
      final destination = coords.last;
      String waypoints = '';
      if (coords.length > 2) {
        // waypoints are the middle points (excluding origin and destination)
        waypoints = coords.sublist(1, coords.length - 1).join('|');
      }

      final uriString = 'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}${waypoints.isNotEmpty ? '&waypoints=${Uri.encodeComponent(waypoints)}' : ''}&travelmode=driving';
      final uri = Uri.parse(uriString);
      // Record navigation in the user's history (fire-and-forget)
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final first = r.pdis.first;
          FirebaseFirestore.instance.collection('users').doc(uid).collection('history').add({
            'action': 'open_route_navigation',
            'routeId': r.id,
            'routeName': r.name,
            'pointsCount': r.pdis.length,
            'timestamp': FieldValue.serverTimestamp(),
          });
          FirebaseFirestore.instance.collection('users').doc(uid).collection('history_places').add({
            'name': r.name,
            'category': 'route',
            'latitude': first.lat,
            'longitude': first.lng,
            'source': 'route_navigation',
            'sourceId': r.id,
            'poiId': null,
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
}
