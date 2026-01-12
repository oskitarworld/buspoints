// ignore_for_file: use_build_context_synchronously

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:myapp/models/user_route.dart';
import 'package:myapp/services/route_service.dart';
import 'package:myapp/utils/marker_utils.dart';
import 'package:myapp/screens/community_routes_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:myapp/firebase_options.dart';

class CreateRouteScreen extends StatefulWidget {
  final UserRoute? routeToEdit;
  const CreateRouteScreen({super.key, this.routeToEdit});

  @override
  State<CreateRouteScreen> createState() => _CreateRouteScreenState();
}

class _CreateRouteScreenState extends State<CreateRouteScreen> {
  final RouteService _routeService = RouteService();
  final List<UserRoutePoint> _points = [];
  final Map<MarkerId, Marker> _markers = {};
  final Map<MarkerId, Marker> _pdiMarkers = {};
  final Completer<GoogleMapController> _controller = Completer();
  bool _saving = false;
  MapType _mapType = MapType.normal;
  final TextEditingController _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];

  static const CameraPosition _initial = CameraPosition(target: LatLng(-34.0, -58.0), zoom: 12);
  late CameraPosition _cameraInitial;

  void _onMapTap(LatLng latLng) {
    // Prompt for a name when adding a new point. Default value is the
    // next point number (important requirement).
    _promptAndAddPoint(latLng);
  }

  Future<void> _promptAndAddPoint(LatLng latLng) async {
    if (_points.length >= 20) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Máximo 20 puntos por ruta')));
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
    final bmp = await createNumberedMarker(i + 1, size: 44, color: Colors.blue);
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
    // keep PDI markers as well (they live in _pdiMarkers)
  }

  Future<void> _loadNearbyPdis(LatLng center, {double delta = 0.05}) async {
    // delta ~ degrees latitude/longitude (~0.05 ≈ 5km); conservative default
    try {
      final minLat = center.latitude - delta;
      final maxLat = center.latitude + delta;
      final minLng = center.longitude - delta;
      final maxLng = center.longitude + delta;

      final Map<MarkerId, Marker> pdis = {};

      // Helper to query a collection reference and add markers. This is
      // flexible about coordinate fields (position, latitude/longitude,
      // geometry.coordinates, geopoint, nested geo) to match canonical
      // POI document shapes.
      Future<void> queryRefAndAdd(CollectionReference colRef, String tag, {int limit = 500}) async {
        try {
          // try bounding queries when possible (position.latitude exists)
          Query q = colRef;
          try {
            q = colRef.where('position.latitude', isGreaterThanOrEqualTo: minLat).where('position.latitude', isLessThanOrEqualTo: maxLat).limit(limit);
          } catch (_) {
            // if the composite index doesn't exist or field missing, fall back
            q = colRef.limit(limit);
          }
          final snap = await q.get();
          for (final doc in snap.docs) {
            final data = doc.data() as Map<String, dynamic>;
            double? lat;
            double? lng;
            try {
              // Common shapes
              if (data['position'] != null && data['position'] is Map) {
                final pos = Map<String, dynamic>.from(data['position'] as Map);
                final rawLat = pos['latitude'] ?? pos['lat'];
                final rawLng = pos['longitude'] ?? pos['lng'];
                if (rawLat != null && rawLng != null) {
                  lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString());
                  lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString());
                }
              }
              if ((lat == null || lng == null) && data['latitude'] != null && data['longitude'] != null) {
                final rawLat = data['latitude'];
                final rawLng = data['longitude'];
                lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString());
                lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString());
              }
              // GeoJSON geometry.coordinates: [lng, lat]
              if ((lat == null || lng == null) && data['geometry'] is Map) {
                try {
                  final geom = Map<String, dynamic>.from(data['geometry'] as Map);
                  final coords = geom['coordinates'];
                  if (coords is List && coords.length >= 2) {
                    final rawLng = coords[0];
                    final rawLat = coords[1];
                    lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString());
                    lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString());
                  }
                } catch (_) {}
              }
              // geopoint objects
              if ((lat == null || lng == null) && data['geopoint'] != null) {
                final gp = data['geopoint'];
                if (gp is GeoPoint) {
                  lat = gp.latitude;
                  lng = gp.longitude;
                } else if (gp is Map) {
                  final rawLat = gp['latitude'] ?? gp['lat'];
                  final rawLng = gp['longitude'] ?? gp['lng'];
                  lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString());
                  lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString());
                }
              }
              // nested geo fields (geo.geopoint etc)
              if ((lat == null || lng == null) && data['geo'] is Map) {
                try {
                  final geo = Map<String, dynamic>.from(data['geo'] as Map);
                  final maybeGp = geo['geopoint'] ?? geo['position'] ?? geo['location'];
                  if (maybeGp is GeoPoint) {
                    lat = maybeGp.latitude;
                    lng = maybeGp.longitude;
                  } else if (maybeGp is Map) {
                    final rawLat = maybeGp['latitude'] ?? maybeGp['lat'];
                    final rawLng = maybeGp['longitude'] ?? maybeGp['lng'];
                    lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat.toString());
                    lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng.toString());
                  }
                } catch (_) {}
              }
            } catch (_) {}
            if (lat == null || lng == null) continue;
            if (lng < minLng || lng > maxLng) continue; // client-side lng filter

            final id = MarkerId('pdi_${tag}_${doc.id}');
            if (pdis.containsKey(id)) continue;
            final title = (data['name'] ?? data['title'] ?? doc.id).toString();
            final marker = Marker(
              markerId: id,
              position: LatLng(lat, lng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: InfoWindow(title: title),
            );
            pdis[id] = marker;
          }
        } catch (e) {
          // ignore collection errors (security rules / missing fields)
        }
      }

      // Query canonical collections and also a potential nested path where
      // some imports store PDIs under firestore/database/pdis_v2
      await queryRefAndAdd(FirebaseFirestore.instance.collection('pdis_v2'), 'pdis_v2');
      await queryRefAndAdd(FirebaseFirestore.instance.collection('Pdis_full'), 'Pdis_full');
      await queryRefAndAdd(FirebaseFirestore.instance.collection('pois'), 'pois');
      // Also try nested path: collection('firestore').doc('database').collection('pdis_v2')
      try {
        final nested = FirebaseFirestore.instance.collection('firestore').doc('database').collection('pdis_v2');
        await queryRefAndAdd(nested, 'firestore_database_pdis_v2');
      } catch (_) {}

      setState(() {
        _pdiMarkers
          ..clear()
          ..addAll(pdis);
      });
    } catch (_) {}
  }

  // _togglePdis removed: PDI markers are always shown in create-route mode.

  // _togglePdis removed: PDI markers are always shown in create-route mode.

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
                title: const Text('🗑 Eliminar punto'),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('✏️ Editar nombre'),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('❌ Cerrar'),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Debes seleccionar al menos 2 puntos (una ruta con uno no es ruta, es un sitio 😅)')));
      return;
    }

    // Prepare controllers and prefill when editing an existing route.
    final nameController = TextEditingController(text: widget.routeToEdit?.name ?? '');
    final descController = TextEditingController(text: widget.routeToEdit?.description ?? '');

    String visibilityChoice = widget.routeToEdit != null
        ? (widget.routeToEdit!.isPublic ? 'public' : 'private')
        : 'public'; // 'public' | 'private' | 'team'
    // Load user's companies (may belong to multiple). We'll present a selector
    // when the user chooses the 'team' visibility so they can pick which
    // company the route belongs to.
    List<String> myCompanyIds = [];
    final List<Map<String, String>> myCompanies = []; // {id,name}
    String? selectedCompanyId;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      Map<String, dynamic>? userData;
      if (uid != null) {
        final udoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (udoc.exists) {
          userData = udoc.data();
          if (userData != null) {
            if (userData['companyIds'] != null && userData['companyIds'] is List) {
              myCompanyIds = List<String>.from((userData['companyIds'] as List).map((e) => e.toString()));
            } else if (userData['companyId'] != null) {
              myCompanyIds = [(userData['companyId'] as String).toString()];
            }
            // If this account itself is a company account (role == 'company'),
            // allow creating routes for the company represented by this user.
            // Some company accounts don't populate companyIds; treat uid as companyId.
            try {
              final role = (userData['role'] ?? '').toString();
              if ((myCompanyIds.isEmpty) && role == 'company') {
                myCompanyIds = [uid];
              }
            } catch (_) {}
          }
        }
      }

  // Try to resolve human-readable names using data already available in
  // the current user's document to avoid additional reads that may be
  // blocked by security rules (and that produce PERMISSION_DENIED logs).
      for (final cid in myCompanyIds) {
        String cname = cid;
        try {
          if (userData != null) {
            // Prefer a mapping like companyNames:{cid: name}
            if (userData['companyNames'] is Map && (userData['companyNames'] as Map)[cid] != null) {
              cname = ((userData['companyNames'] as Map)[cid]).toString();
            } else if (userData['companies'] is List) {
              // Maybe companies is a list of objects with id/name
              try {
                for (final item in (userData['companies'] as List)) {
                  if (item is Map && (item['id']?.toString() == cid || item['companyId']?.toString() == cid)) {
                    final cand = item['name'] ?? item['companyName'] ?? item['displayName'];
                    if (cand != null) { cname = cand.toString(); break; }
                  }
                }
              } catch (_) {}
            } else if ((userData['companyName'] ?? userData['company']) != null && myCompanyIds.length == 1) {
              cname = (userData['companyName'] ?? userData['company']).toString();
            }
          }
        } catch (_) {}
        // Ensure name is a plain String (no widgets or maps). Trim whitespace.
        final safeName = cname.toString().trim();
        myCompanies.add({'id': cid, 'name': safeName.isNotEmpty ? safeName : cid});
      }

      // If we still don't have friendly names (or to ensure authoritative
      // names), ask the server-side callable which can read company/user
      // docs using admin privileges. This helps when client-side rules
      // prevent direct reads of companies/{id}.
      if (myCompanyIds.isNotEmpty) {
        try {
          final callable = FirebaseFunctions.instance.httpsCallable('getCompanyNames');
          final res = await callable.call({'companyIds': myCompanyIds});
          final data = res.data;
          if (data != null && data is Map && data['names'] is Map) {
            final Map names = data['names'];
            for (var i = 0; i < myCompanies.length; i++) {
              final cid = myCompanies[i]['id'];
              if (cid != null && names[cid] != null) {
                myCompanies[i]['name'] = names[cid].toString();
              }
            }
          }
        } catch (e) {
          // ignore network/callable errors and keep local fallbacks
        }
      }
      if (myCompanies.isNotEmpty) selectedCompanyId = myCompanies.first['id'];
    } catch (_) {}
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
                // Visibility selector. If the current user belongs to a company,
                // allow 'Team' visibility. Otherwise the options are public/private.
                    Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: visibilityChoice,
                      // Use selectedItemBuilder to ensure the displayed selected
                      // value reflects the currently chosen company name and
                      // updates when the company selector changes.
                      selectedItemBuilder: (ctx) {
                        final List<Widget> widgets = [];
                        widgets.add(const Text('🌍 Pública'));
                        widgets.add(const Text('🔒 Privada (solo yo)'));
                        if (myCompanies.isNotEmpty) {
                          final cname = selectedCompanyId != null
                              ? myCompanies.firstWhere((m) => m['id'] == selectedCompanyId, orElse: () => myCompanies.first)['name']
                              : null;
                          widgets.add(Text(cname != null ? '🏢 Rutas de $cname' : '🏢 Rutas de la empresa'));
                        }
                        return widgets;
                      },
                      items: <DropdownMenuItem<String>>[
                        const DropdownMenuItem(value: 'public', child: Text('🌍 Pública')),
                        DropdownMenuItem(value: 'private', child: Text('🔒 Privada (solo yo)')),
                        if (myCompanies.isNotEmpty)
                          DropdownMenuItem(value: 'team', child: const Text('🏢 Rutas de la empresa')),
                      ],
                      onChanged: (v) {
                        setState(() => visibilityChoice = v ?? 'public');
                      },
                      decoration: const InputDecoration(labelText: 'Visibilidad'),
                    ),
                    const SizedBox(height: 6),
                    // Explicit plain-text label mirroring the selected visibility.
                    // This ensures we always show a simple String (no embedded UI)
                    // even if the Dropdown rendering behaves unexpectedly.
                    Builder(builder: (labelCtx) {
                      String selLabel;
                      if (visibilityChoice == 'public') {
                        selLabel = '🌍 Pública';
                      } else if (visibilityChoice == 'private') {
                        selLabel = '🔒 Privada (solo yo)';
                      } else {
                        String cname = selectedCompanyId != null && myCompanies.isNotEmpty
                            ? myCompanies.firstWhere((m) => m['id'] == selectedCompanyId, orElse: () => myCompanies.first)['name'] ?? 'la empresa'
                            : 'la empresa seleccionada';
                        // Force a safe, short string to avoid UI embedding
                        if (cname.length > 40) cname = '${cname.substring(0, 37)}...';
                        selLabel = '🏢 Rutas de $cname';
                      }
                      return Text(selLabel, style: Theme.of(labelCtx).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600));
                    }),
                    const SizedBox(height: 8),
                    // If team/company visibility selected and user has multiple
                    // companies, allow selecting which company this route belongs to.
                    if (visibilityChoice == 'team' && myCompanies.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCompanyId,
                        items: myCompanies.map((m) => DropdownMenuItem(value: m['id'], child: Text(m['name'] ?? m['id'] ?? ''))).toList(),
                        onChanged: (v) => setState(() => selectedCompanyId = v),
                        decoration: const InputDecoration(labelText: 'Empresa'),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Builder(builder: (tCtx) {
                      String desc;
                      if (visibilityChoice == 'public') {
                        desc = '🌍 Pública: se revisa y, si pasa el filtro, se publica.';
                      } else if (visibilityChoice == 'private') {
                        desc = '🔒 Privada: solo la verás tú.';
                      } else {
                        // When company info is available, include the company name in the description
                        String cname = selectedCompanyId != null && myCompanies.isNotEmpty
                            ? myCompanies.firstWhere((m) => m['id'] == selectedCompanyId, orElse: () => myCompanies.first)['name'] ?? 'la empresa'
                            : 'la empresa seleccionada';
                        desc = '🏢 Rutas de $cname: solo los miembros de $cname podrán ver esta ruta.';
                      }
                      return Text(desc, style: Theme.of(tCtx).textTheme.bodySmall);
                    })
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
      messenger.showSnackBar(const SnackBar(content: Text('La ruta necesita un nombre (obligatorio, sin nombre no hay gloria)')));
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Debes iniciar sesión para guardar rutas')));
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.routeToEdit != null) {
        // Edit existing route: call updateRoute with changed fields.
        await _routeService.updateRoute(
          widget.routeToEdit!.id,
          name: name,
          description: descController.text.trim(),
          pdis: _points.map((p) => p.toMap()).toList(),
        );
        setState(() => _saving = false);
        messenger.showSnackBar(const SnackBar(content: Text('Ruta actualizada')));
        // Return true to indicate the route was updated.
        navigator.pop(true);
        return;
      }

      // Create new route path
      final id = await _routeService.createRoute(
        name: name,
        description: descController.text.trim(),
        uid: uid,
        pdis: _points,
        visibility: visibilityChoice,
        ownerCompanyId: (visibilityChoice == 'team') ? selectedCompanyId : null,
      );
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Ruta guardada: $id')));
      // Close the CreateRouteScreen and, if this was a team route, navigate
      // to the company-specific routes screen so the user lands on the
      // corresponding "Rutas de <Empresa>" view.
      navigator.pop(true);
      if (visibilityChoice == 'team' && selectedCompanyId != null) {
        String cname = selectedCompanyId!;
        for (final m in myCompanies) {
          try {
            if (m['id'] == selectedCompanyId) {
              cname = (m['name'] ?? cname);
              break;
            }
          } catch (_) {}
        }
        Navigator.push(navigator.context, MaterialPageRoute(builder: (context) => CommunityRoutesScreen(companyId: selectedCompanyId, companyName: cname)));
      }
    } catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Error guardando ruta: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    // If opened in edit mode, prefill points and center map
    if (widget.routeToEdit != null) {
      try {
        _points.clear();
        _points.addAll(widget.routeToEdit!.pdis.map((p) => UserRoutePoint(lat: p.lat, lng: p.lng, name: p.name)));
      } catch (_) {}
    }
    _rebuildMarkers();
    // Setup initial camera: center on the route's first point when editing,
    // otherwise use the user-location centering flow.
    if (widget.routeToEdit != null && _points.isNotEmpty) {
      _cameraInitial = CameraPosition(target: LatLng(_points.first.lat, _points.first.lng), zoom: 13);
    } else {
      _cameraInitial = _initial;
      // Try to center map on user's current location once the map is ready.
      _centerToUserOnStart();
    }
    // Show an introductory popup describing how to create a route when
    // opening the screen in "create" mode (not editing). Use a post-frame
    // callback to avoid using BuildContext synchronously during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.routeToEdit == null) {
        _showCreateIntroIfNeeded();
      }
    });
  }

  bool _introShown = false;

  void _showCreateIntroIfNeeded() {
    if (_introShown) return;
    _introShown = true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Crear ruta'),
        content: const Text('Cómo crear una ruta:\n• Toca el mapa para añadir un punto.\n• Puedes buscar una dirección y añadirla.\n• Máximo 20 puntos por ruta.\n• Mantén pulsado un punto para ver más opciones.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.routeToEdit != null ? 'Editar ruta' : 'Crear ruta'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saving ? null : _saveRoute),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _cameraInitial,
            onMapCreated: (c) async {
              // Complete the controller future and, if editing an existing
              // route, ensure the camera is placed over the first point.
              _controller.complete(c);
              if (widget.routeToEdit != null && _points.isNotEmpty) {
                try {
                  await c.animateCamera(CameraUpdate.newLatLng(LatLng(_points.first.lat, _points.first.lng)));
                } catch (_) {}
              }
              // Load PDIs for the current visible region so the user can pick
              // points from nearby POIs while creating the route.
              try {
                final bounds = await c.getVisibleRegion();
                final center = LatLng((bounds.northeast.latitude + bounds.southwest.latitude) / 2,
                    (bounds.northeast.longitude + bounds.southwest.longitude) / 2);
                _loadNearbyPdis(center);
              } catch (_) {}
            },
            onTap: _onMapTap,
            onCameraIdle: () async {
              try {
                final controller = await _controller.future;
                final bounds = await controller.getVisibleRegion();
                final center = LatLng((bounds.northeast.latitude + bounds.southwest.latitude) / 2,
                    (bounds.northeast.longitude + bounds.southwest.longitude) / 2);
                // small debounce not implemented; this runs on camera idle only
                _loadNearbyPdis(center);
              } catch (_) {}
            },
            mapType: _mapType,
            markers: Set<Marker>.of(_markers.values)..addAll(_pdiMarkers.values),
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
                      decoration: const InputDecoration(hintText: 'Buscar lugar…', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14)),
                      onSubmitted: (v) => _performSearch(v),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.search), onPressed: () => _performSearch(_searchCtrl.text)),
                  IconButton(
                    icon: const Icon(Icons.my_location),
                    tooltip: 'Mi ubicación',
                    onPressed: _locateMe,
                  ),
                  IconButton(
                    icon: Icon(Icons.layers),
                    tooltip: 'Cambiar vista',
                    onPressed: () {
                      setState(() {
                        _mapType = _mapType == MapType.normal ? MapType.satellite : MapType.normal;
                      });
                    },
                  ),
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
          // (instructions banner removed; intro dialog is shown on screen open)
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
          // locate FAB moved to top search frame
          // PDI toggle FAB removed (PDIs shown by default)
          // maptype FAB moved to top search frame
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
