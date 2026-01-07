import 'package:flutter/material.dart';
import 'package:myapp/services/route_service.dart';
import 'package:myapp/models/user_route.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:myapp/screens/create_route_screen.dart';
import 'package:myapp/utils/marker_utils.dart';

class CommunityRoutesScreen extends StatefulWidget {
  final String? companyId;
  final String? companyName;
  const CommunityRoutesScreen({super.key, this.companyId, this.companyName});

  @override
  State<CommunityRoutesScreen> createState() => _CommunityRoutesScreenState();
}

class _CommunityRoutesScreenState extends State<CommunityRoutesScreen> {
  final RouteService _routeService = RouteService();
  String _uid = '';
  List<String> _myCompanyIds = [];
  // _myCompanyIds removed: we rely on company owner mapping to decide permissions
  final Map<String, String?> _companyOwners = {}; // companyId -> ownerUid (null if unknown)

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _uid = user?.uid ?? '';
    // preload user's companyIds from their user document asynchronously
    if (_uid.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final udoc = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
          if (udoc.exists) {
            final data = udoc.data() ?? {};
            if (data['companyIds'] is List) {
              _myCompanyIds = (data['companyIds'] as List).map((e) => e.toString()).toList();
            } else if (data['companyId'] != null) {
              _myCompanyIds = [data['companyId'].toString()];
            } else if (data['role'] == 'company') {
              // user is a company account represented by their uid
              _myCompanyIds = [_uid];
            }
            if (mounted) setState(() {});
          }
        } catch (_) {}
      });
    }
    // we do not preload user's companyIds here; permissions are derived from company owner mapping
  }

  Future<List<UserRoute>> _loadRoutesForCurrentUser() async {
    // If a specific companyId was provided, fetch routes for that company only.
    if (widget.companyId != null) {
      try {
        final routes = await _routeService.fetchRoutesForCompany(widget.companyId!);
        // Ensure we know the company owner for this companyId
        await _ensureCompanyOwner(widget.companyId!);
        return routes;
      } catch (_) {
        return [];
      }
    }
    // No companyId -> this screen is the public community routes view.
    // Only show public approved routes here.
    try {
      final routes = await _routeService.fetchPublicRoutes();
      // Preload owners for any team routes we will display so we can decide
      // whether to show edit/delete buttons client-side.
      final companyIds = <String>{};
      for (final r in routes) {
        final cid = r.toMap()['ownerCompanyId']?.toString();
        if (cid != null && cid.isNotEmpty) companyIds.add(cid);
      }
      for (final cid in companyIds) {
        await _ensureCompanyOwner(cid);
      }
      return routes;
    } catch (_) {
      return [];
    }
  }

  Future<void> _ensureCompanyOwner(String companyId) async {
    if (_companyOwners.containsKey(companyId)) return;
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getCompanyOwners');
      final res = await callable.call({'companyIds': [companyId]});
      final data = res.data as Map<String, dynamic>? ?? {};
      final owners = data['owners'] as Map<String, dynamic>? ?? {};
      final owner = owners[companyId];
      _companyOwners[companyId] = owner?.toString();
      return;
    } catch (_) {
      // fallback: try users/{companyId} if callable failed
      try {
        final userSnap = await FirebaseFirestore.instance.collection('users').doc(companyId).get();
        if (userSnap.exists) {
          final ud = userSnap.data() ?? {};
          if ((ud['role'] ?? '') == 'company') {
            _companyOwners[companyId] = companyId;
            return;
          }
        }
      } catch (_) {}
    }
    _companyOwners[companyId] = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
  appBar: AppBar(title: Text(widget.companyName != null ? 'Rutas de ${widget.companyName}' : 'Rutas de la comunidad')),
      body: FutureBuilder<List<UserRoute>>(
        future: _loadRoutesForCurrentUser(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final routes = snap.data ?? [];
          if (routes.isEmpty) return const Center(child: Text('No hay rutas publicadas aún'));
          return ListView.builder(
            itemCount: routes.length,
            itemBuilder: (ctx, i) {
              final r = routes[i];
              final ownerCompanyId = r.toMap()['ownerCompanyId']?.toString();
              final bool isTeamRoute = ownerCompanyId != null && ownerCompanyId.isNotEmpty;
              // Only allow edit/delete when the current user is the company owner
              // (company account ownerUid) — employees (workers) must not be able to edit/delete.
              final ownerUid = isTeamRoute ? _companyOwners[ownerCompanyId] : null;
              final bool isCompanyMember = ownerCompanyId != null && _myCompanyIds.contains(ownerCompanyId);
              // Allow management if current user is resolved owner, or if user's
              // account represents the company (company profile) or is tied to the company
              final bool canManage = _uid.isNotEmpty && isTeamRoute && ((ownerUid != null && ownerUid == _uid) || isCompanyMember);

              if (canManage) {
                return ListTile(
                  title: Text(r.name),
                  subtitle: Text('${r.pdis.length} puntos • ${r.description}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        tooltip: 'Editar',
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          final res = await nav.push<bool?>(MaterialPageRoute(builder: (ctx) => CreateRouteScreen(routeToEdit: r)));
                          if (res == true) {
                            if (!mounted) return;
                            messenger.showSnackBar(const SnackBar(content: Text('Ruta actualizada')));
                            setState(() {});
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Eliminar',
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
                            title: const Text('Eliminar ruta'),
                            content: const Text('¿Eliminar esta ruta de la empresa? Esta acción no se puede deshacer.'),
                            actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Eliminar'))],
                          ));
                          if (ok == true) {
                            try {
                              await _routeService.deleteRoute(r.id, ownerCompanyId: ownerCompanyId);
                              if (!mounted) return;
                              messenger.showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
                              setState(() {});
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(SnackBar(content: Text('No se pudo eliminar la ruta: $e')));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () => _showPreview(r),
                );
              }

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
  final ownerCompanyId = r.toMap()['ownerCompanyId']?.toString();
  final ownerUid = ownerCompanyId != null ? _companyOwners[ownerCompanyId] : null;
  final bool isCompanyMember = ownerCompanyId != null && _myCompanyIds.contains(ownerCompanyId);
  final bool canManage = _uid.isNotEmpty && ownerCompanyId != null && ((ownerUid != null && ownerUid == _uid) || isCompanyMember);

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
              if (canManage)
                TextButton(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final res = await Navigator.of(context).push<bool?>(MaterialPageRoute(builder: (ctx2) => CreateRouteScreen(routeToEdit: r)));
                    if (res == true && mounted) setState(() {});
                  },
                  child: const Text('Editar'),
                ),
              if (canManage)
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
                          title: const Text('Eliminar ruta'),
                          content: const Text('¿Eliminar esta ruta de la empresa? Esta acción no se puede deshacer.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
                            ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Eliminar')),
                          ],
                        ));
                    if (ok == true) {
                      try {
                        await _routeService.deleteRoute(r.id, ownerCompanyId: ownerCompanyId);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
                        Navigator.of(ctx).pop();
                        setState(() {});
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo eliminar la ruta: $e')));
                      }
                    }
                  },
                  child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
                ),
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
