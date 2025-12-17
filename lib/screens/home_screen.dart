import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myapp/models/place.dart';
import 'package:myapp/widgets/app_drawer.dart';
import 'package:myapp/screens/add_poi_screen.dart';
import 'package:myapp/services/google_places_service.dart';
import 'package:myapp/services/firestore_service.dart';
// ...existing code...
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:myapp/services/web_places_autocomplete.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

// Prepare marker descriptors in a background isolate.
List<Map<String, dynamic>> _prepareMarkerDescriptors(List<Map<String, dynamic>> items) {
  // items are simple maps with primitive types (safe to send to compute)
  return items.map((m) {
    return {
      'id': m['id'],
      'lat': m['lat'],
      'lng': m['lng'],
      'name': m['name'],
      'category': m['category'],
    };
  }).toList();
}

// Google Places API Key
const String _googleApiKey = 'AIzaSyBtEYqVfNtm14WstANwadcr7SRLyhc_wCk';

class PlacePrediction {
  final String description;
  final String placeId;
  PlacePrediction({required this.description, required this.placeId});
  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      description: json['description'] as String,
      placeId: json['place_id'] as String,
    );
  }
}

// PRINCIPAL: HomeScreen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final GooglePlacesService _placesService;
  final FirestoreService _firestoreService = FirestoreService();
  List<Place> _allPlaces = [];

  String _sanitizeId(String s) {
    var out = s.replaceAll(RegExp(r"[^A-Za-z0-9_\-]"), '_');
    out = out.replaceAll(RegExp(r'_+'), '_');
    out = out.trim();
    if (out.startsWith('_')) out = out.substring(1);
    if (out.endsWith('_')) out = out.substring(0, out.length - 1);
    return out;
  }

  void _hideCategoryList() {
    setState(() {
      _isCategoryListVisible = false;
    });
  }

  void _toggleCategoryList() {
    setState(() {
      _isCategoryListVisible = !_isCategoryListVisible;
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!_mapController.isCompleted) {
      _mapController.complete(controller);
    }
  }

  void _onSearchChanged(String value) {
    if (value.isEmpty) {
      setState(() => _predictions = []);
      return;
    }
    if (kIsWeb) {
      WebPlacesAutocomplete.getSuggestions(value).then((results) {
        setState(() {
          // results ahora son Map con description y place_id
          _predictions = results
              .map((r) => PlacePrediction(description: r['description'] as String, placeId: r['place_id'] as String))
              .toList();
        });
      });
    } else {
      _placesService.autocomplete(value).then((results) {
        setState(() {
          _predictions = results.map((e) => PlacePrediction(
            description: e['description'],
            placeId: e['place_id'],
          )).toList();
        });
      });
    }
  }

  void _onCategorySelected(String category) {
    // When a category is selected, query Firestore for that category and
    // update markers with the resulting POIs. This ensures we show all
    // documents (not only those already loaded into _allPlaces).
    _loadPlacesByCategory(category).then((_) {
      _hideCategoryList();
    });
  }

  Future<void> _loadPlacesByCategory(String categoryKey) async {
    try {
      // Normalize the incoming category key to match Firestore normalization
      final normalizedCategoryKey = categoryKey.toLowerCase().replaceAll(RegExp(r"[\s-]+"), '_');

      // Some UI category keys are short (e.g. 'parking', 'parada_bus') but
      // the Firestore documents use different normalized categories
      // (e.g. 'parking_de_pago', 'parada_de_bus'). Use an alias map so the
      // client queries the correct category in the database.
      const Map<String, String> _categoryAliases = {
        'parking': 'parking_de_pago',
        'parada_bus': 'parada_de_bus',
        'zona_espera': 'zonas_de_espera_o_autocares',
        'hotel': 'hoteles_y_restaurantes',
        'restaurante': 'hoteles_y_restaurantes',
        // keep a few helpful aliases
        'bus_stop': 'bus_stops',
        // UI uses singular 'gasolinera' but Firestore stores 'gasolineras'
        'gasolinera': 'gasolineras',
      };

      final effectiveCategoryKey = _categoryAliases[normalizedCategoryKey] ?? normalizedCategoryKey;
      developer.log('[HomeScreen] Loading POIs for category: $categoryKey (normalized: $normalizedCategoryKey, effective: $effectiveCategoryKey)', name: 'HomeScreen');
      final List<Place> places = [];

      // Query the canonical pdis collection where category == categoryKey
      // Special-case: for 'lista_gold' prefer documents in `pdis_v2` that
      // contain 'lista_gold' in `specialCategories`. Also fall back to the
      // historical `pdis` collection in case some docs still live there.
      List<QueryDocumentSnapshot<Map<String, dynamic>>> pdisDocs = [];
      if (effectiveCategoryKey == 'lista_gold') {
        try {
          final snapV2 = await FirebaseFirestore.instance
              .collection('pdis_v2')
              .where('specialCategories', arrayContains: 'lista_gold')
              .get();
          developer.log('[HomeScreen] pdis_v2(lista_gold) returned ${snapV2.docs.length} docs', name: 'HomeScreen');
          pdisDocs.addAll(snapV2.docs);
        } catch (e, s) {
          developer.log('Error querying pdis_v2 for lista_gold: $e', name: 'HomeScreen', error: e, stackTrace: s);
        }

        try {
          final snapOld = await FirebaseFirestore.instance
              .collection('pdis')
              .where('category', isEqualTo: effectiveCategoryKey)
              .limit(2000)
              .get();
          developer.log('[HomeScreen] pdis(lista_gold fallback) returned ${snapOld.docs.length} docs', name: 'HomeScreen');
          pdisDocs.addAll(snapOld.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>());
        } catch (e, s) {
          developer.log('Error querying pdis fallback for lista_gold: $e', name: 'HomeScreen', error: e, stackTrace: s);
        }
      } else {
        final q = FirebaseFirestore.instance
            .collection('pdis')
            .where('category', isEqualTo: effectiveCategoryKey)
            .limit(2000);
        final snap = await q.get();
        developer.log('[HomeScreen] pdis query returned ${snap.docs.length} docs', name: 'HomeScreen');
        pdisDocs.addAll(snap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>());
      }

      for (final doc in pdisDocs) {
        final data = doc.data();

        double? lat;
        double? lng;

        // latitude/longitude fields
        if (data.containsKey('latitude') && data.containsKey('longitude')) {
          final rawLat = data['latitude'];
          final rawLng = data['longitude'];
          lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
          lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
        }

        // position map { lat, lng } or {latitude, longitude}
        if ((lat == null || lng == null) && data['position'] is Map) {
          final pos = Map<String, dynamic>.from(data['position'] as Map);
          final rawLat = pos['lat'] ?? pos['latitude'];
          final rawLng = pos['lng'] ?? pos['longitude'];
          lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
          lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
        }

        // geopoint stored as a GeoPoint object or as a map
        if ((lat == null || lng == null) && data['geopoint'] != null) {
          final gp = data['geopoint'];
          if (gp is GeoPoint) {
            lat = gp.latitude;
            lng = gp.longitude;
          } else if (gp is Map) {
            final rawLat = gp['latitude'] ?? gp['lat'];
            final rawLng = gp['longitude'] ?? gp['lng'];
            lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
            lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
          }
        }

        // geometry coordinates (GeoJSON style): { geometry: { coordinates: [lng, lat], type: 'Point' } }
        if ((lat == null || lng == null) && data['geometry'] is Map) {
          try {
            final geom = Map<String, dynamic>.from(data['geometry'] as Map);
            final coords = geom['coordinates'];
            if (coords is List && coords.length >= 2) {
              final rawLng = coords[0];
              final rawLat = coords[1];
              lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
              lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
              developer.log('[HomeScreen] used geometry.coordinates for ${doc.id}', name: 'HomeScreen');
            }
          } catch (e, s) {
            developer.log('Error reading geometry.coordinates: $e', name: 'HomeScreen', error: e, stackTrace: s);
          }
        }

        // nested geo formats (geo.geopoint)
        if ((lat == null || lng == null) && data['geo'] is Map) {
          final geo = Map<String, dynamic>.from(data['geo'] as Map);
          final maybeGp = geo['geopoint'];
          if (maybeGp is GeoPoint) {
            lat = maybeGp.latitude;
            lng = maybeGp.longitude;
          } else if (maybeGp is Map) {
            final rawLat = maybeGp['latitude'] ?? maybeGp['lat'];
            final rawLng = maybeGp['longitude'] ?? maybeGp['lng'];
            lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
            lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
          }
        }

        if (lat == null || lng == null) {
          // skip docs without usable coordinates
          continue;
        }

        final place = Place(
          name: (data['name'] ?? '') as String,
          category: (data['category'] ?? categoryKey) as String,
          position: LatLng(lat, lng),
          description: data['description'] as String?,
        );
        places.add(place);
      }

      // Also include approved user-submitted POIs from `user_pois` that match
      // the category. These are merged with canonical `pdis` results and
      // deduplicated by rounded coordinates + name to avoid duplicates.
      try {
        final userQ = FirebaseFirestore.instance
            .collection('user_pois')
            .where('status', isEqualTo: 'approved')
            .where('category', isEqualTo: normalizedCategoryKey)
            .limit(500);
        final userSnap = await userQ.get();
        developer.log('[HomeScreen] user_pois query returned ${userSnap.docs.length} docs', name: 'HomeScreen');
        for (final doc in userSnap.docs) {
          final data = doc.data();
          double? lat;
          double? lng;
          if (data.containsKey('latitude') && data.containsKey('longitude')) {
            final rawLat = data['latitude'];
            final rawLng = data['longitude'];
            lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
            lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
          }
          if ((lat == null || lng == null) && data['position'] is Map) {
            final pos = Map<String, dynamic>.from(data['position'] as Map);
            final rawLat = pos['lat'] ?? pos['latitude'];
            final rawLng = pos['lng'] ?? pos['longitude'];
            lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
            lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
          }
          // geometry coordinates for user_pois as well
          if ((lat == null || lng == null) && data['geometry'] is Map) {
            try {
              final geom = Map<String, dynamic>.from(data['geometry'] as Map);
              final coords = geom['coordinates'];
              if (coords is List && coords.length >= 2) {
                final rawLng = coords[0];
                final rawLat = coords[1];
                lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
                lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
                developer.log('[HomeScreen] used geometry.coordinates for user_pois doc ${doc.id}', name: 'HomeScreen');
              }
            } catch (e, s) {
              developer.log('Error reading geometry.coordinates (user_pois): $e', name: 'HomeScreen', error: e, stackTrace: s);
            }
          }
          if ((lat == null || lng == null) && data['geopoint'] != null) {
            final gp = data['geopoint'];
            if (gp is GeoPoint) {
              lat = gp.latitude;
              lng = gp.longitude;
            } else if (gp is Map) {
              final rawLat = gp['latitude'] ?? gp['lat'];
              final rawLng = gp['longitude'] ?? gp['lng'];
              lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
              lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
            }
          }
          if (lat == null || lng == null) continue;
          final place = Place(
            name: (data['name'] ?? '') as String,
            category: (data['category'] ?? categoryKey) as String,
            position: LatLng(lat, lng),
            description: data['description'] as String?,
          );
          places.add(place);
        }
      } catch (e, s) {
        developer.log('Error loading user_pois for category: $e', name: 'HomeScreen', error: e, stackTrace: s);
      }

      // Deduplicate by rounded coords + name (same logic as FirestoreService)
      final Map<String, Place> merged = {};
      String keyOf(Place p) => '${p.position.latitude.toStringAsFixed(6)}:${p.position.longitude.toStringAsFixed(6)}:${p.name.toLowerCase()}';
      for (final p in places) {
        final k = keyOf(p);
        if (!merged.containsKey(k)) merged[k] = p;
      }
      final finalPlaces = merged.values.toList();
      developer.log('[HomeScreen] final places after dedupe: ${finalPlaces.length}', name: 'HomeScreen');

      // Removed quick SnackBar feedback for category selection per UX preference.

      if (finalPlaces.isNotEmpty) {
        await _updateMarkersFromPlaces(finalPlaces);
      } else {
        setState(() {
          _markers.clear();
        });
      }
    } catch (e, s) {
      developer.log('Error loading POIs by category: $e', name: 'HomeScreen', error: e, stackTrace: s);
    }
  }

  void _onSelectAll() {
    // Implementa la lógica para mostrar todos
    setState(() {
      _updateMarkersFromPlaces(_allPlaces);
    });
    _hideCategoryList();
  }

  void _onDeselectAll() {
    // Implementa la lógica para ocultar todos
    setState(() {
      _markers.clear();
    });
    _hideCategoryList();
  }

  Future<void> _moveToPlace(String placeId) async {
      if (kIsWeb) {
        // En web, placeId contiene el place_id devuelto por la función
        final pid = placeId;
        if (pid.isNotEmpty) {
          try {
            final url = Uri.parse('https://us-central1-buspoint-49ea0.cloudfunctions.net/getPlaceDetails?place_id=$pid');
            final resp = await http.get(url);
            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body) as Map<String, dynamic>;
              // Esperamos {lat: .., lng: ..} o la estructura similar
              double? lat;
              double? lng;
              if (data.containsKey('lat') && data.containsKey('lng')) {
                lat = (data['lat'] as num).toDouble();
                lng = (data['lng'] as num).toDouble();
              } else if (data.containsKey('result')) {
                final loc = data['result']?['geometry']?['location'];
                if (loc != null) {
                  lat = (loc['lat'] as num).toDouble();
                  lng = (loc['lng'] as num).toDouble();
                }
              }
              if (lat != null && lng != null) {
                final controller = await _mapController.future;
                controller.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16));
              }
            }
          } catch (e, s) {
            developer.log('Error obteniendo place details', name: 'HomeScreen', error: e, stackTrace: s);
          } finally {
            if (mounted) {
              setState(() => _predictions = []);
              _searchController.clear();
              _hideCategoryList();
              _searchFocusNode.unfocus();
            }
          }
        }
      } else {
      _placesService.getPlaceLatLng(placeId).then((latLng) async {
        if (latLng != null) {
          final controller = await _mapController.future;
          controller.animateCamera(CameraUpdate.newLatLngZoom(latLng, 16));
        }
        setState(() => _predictions = []);
        _searchController.clear();
        _hideCategoryList();
        _searchFocusNode.unfocus();
      });
    }
  }
  final Completer<GoogleMapController> _mapController = Completer();
  final List<String> _orderedCategories = [
    'parada_bus', 'parking', 'carga_y_descarga', 'zona_espera', 'gasolinera', 'hotel', 'restaurante', 'otros',
  ];
  final List<String> _specialCategories = [
    'lista_blanca', 'lista_negra', 'lista_gold',
  ];
  List<String> _assetCategories = [];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<PlacePrediction> _predictions = [];
  final CameraPosition _initialCameraPosition = const CameraPosition(target: LatLng(40.4168, -3.7038), zoom: 12);
  LatLng? _startingPosition;
  final Set<Marker> _markers = {};
  bool _isCategoryListVisible = false;

  Future<void> _goToMyLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Servicios de ubicación desactivados. Por favor activa tu GPS.')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permiso de ubicación denegado. No se puede centrar en tu ubicación.')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado permanentemente. Activa los permisos en ajustes.')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final controller = await _mapController.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: LatLng(pos.latitude, pos.longitude),
        zoom: 15.0,
      )));
    } catch (e, s) {
      developer.log(
        'Failed to get current location',
        name: 'HomeScreen',
        error: e,
        stackTrace: s,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener la ubicación: ${e.toString()}')),
        );
      }
    }
  }

  // _onAddPoiPressed removed: use long-press on the map to add a POI.

  @override
  void initState() {
    super.initState();
    _placesService = GooglePlacesService(_googleApiKey);
    // Try to determine the device start position early so the map can
    // initialize centered on the user's location.
    _determineStartPosition();
    // Cargar categorías desde assets y POIs aprobados
    _loadAssetCategories().then((_) {
      _loadPois();
      _showAddPoiTipIfNeeded();
    });
  }

  Future<void> _determineStartPosition() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _startingPosition = LatLng(pos.latitude, pos.longitude);
      });

      // If the map is already created, move camera to start position.
      if (_mapController.isCompleted) {
        final controller = await _mapController.future;
        controller.animateCamera(CameraUpdate.newLatLngZoom(_startingPosition!, 15));
      }
    } catch (e, s) {
      developer.log('Could not determine start position: $e', name: 'HomeScreen', error: e, stackTrace: s);
    }
  }

  Future<void> _showAddPoiTipIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getBool('seen_add_poi_tip') ?? false;
      if (!seen && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Para añadir un PDI: mantén pulsado el mapa.'),
                duration: Duration(seconds: 6),
              ),
            );
        });
        await prefs.setBool('seen_add_poi_tip', true);
      }
    } catch (e, s) {
      developer.log('Failed to show add POI tip: $e', name: 'HomeScreen', error: e, stackTrace: s);
    }
  }

  // Adding POIs is done via long-press on the map. The previous helper that
  // opened the AddPoiScreen from a FAB was removed to avoid duplicate entry
  // points in the UI.

  Future<void> _loadAssetCategories() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifest = json.decode(manifestContent);
      final keys = manifest.keys.where((k) => k.startsWith('assets/icons/') && (k.endsWith('.png') || k.endsWith('.svg') || k.endsWith('.jpg'))).toList();
      final List<String> cats = keys.map((k) {
        final filename = k.split('/').last; // e.g. 'parking.png'
        final name = filename.split('.').first;
        final normalized = name.trim().toLowerCase().replaceAll(RegExp(r"[\s-]+"), '_');
        return normalized;
      }).toList();
      setState(() {
        _assetCategories = cats;
      });
      developer.log('[HomeScreen] Asset categories loaded: $_assetCategories', name: 'HomeScreen');
    } catch (e, s) {
      developer.log('Error cargando AssetManifest.json: $e', name: 'HomeScreen', error: e, stackTrace: s);
    }
  }

  Future<void> _loadPois() async {
    try {
      final places = await _firestoreService.getApprovedPois();
      if (!mounted) return;
      // Debug: print loaded places count and categories to help diagnose filtering issues
      developer.log('[HomeScreen] Loaded places count: ${places.length}', name: 'HomeScreen');
      developer.log('[HomeScreen] Categories: ${places.map((p) => p.category).toList()}', name: 'HomeScreen');
      setState(() {
        _allPlaces = places;
      });
      await _updateMarkersFromPlaces(_allPlaces);
    } catch (e, s) {
      developer.log('Error cargando POIs: $e', name: 'HomeScreen', error: e, stackTrace: s);
    }
  }

  Future<void> _updateMarkersFromPlaces(List<Place> places) async {
    // Prepare lightweight marker descriptors in a background isolate to avoid
    // doing heavy string/ID work on the UI thread. Then create real Marker
    // objects on the main isolate in small batches so the map can render
    // progressively without long frames.
    const int batchSize = 20; // smaller batches
    const int batchDelayMs = 50; // give more time between batches

    // Clear existing markers first so the map can render progressively.
    developer.log('[HomeScreen] Preparing to add ${places.length} markers', name: 'HomeScreen');
    setState(() {
      _markers.clear();
    });

    // Build a serializable list for the isolate and a map to lookup Place by id.
    final List<Map<String, dynamic>> placeMaps = <Map<String, dynamic>>[];
    final Map<String, Place> idToPlace = {};
    for (final place in places) {
      final id = _sanitizeId('${place.name}_${place.category}');
      placeMaps.add({
        'id': id,
        'lat': place.position.latitude,
        'lng': place.position.longitude,
        'name': place.name,
        'category': place.category,
        'isGold': (place.specialCategories ?? []).contains('lista_gold'),
      });
      idToPlace[id] = place;
    }

    // Offload descriptor preparation to a background isolate. If compute
    // fails for any reason (isolate spawn error on some devices), fall
    // back to a synchronous preparation so the UI still shows markers.
    List<Map<String, dynamic>> descriptors;
    try {
      descriptors = await compute(_prepareMarkerDescriptors, placeMaps);
    } catch (e, s) {
      developer.log('compute() failed, falling back to main-thread descriptor preparation', name: 'HomeScreen', error: e, stackTrace: s);
      descriptors = _prepareMarkerDescriptors(placeMaps);
    }

      developer.log('[HomeScreen] Prepared ${descriptors.length} marker descriptors', name: 'HomeScreen');
      // If compute returned an empty list for some reason but we have places,
      // fall back to using the original placeMaps so markers still show.
      if (descriptors.isEmpty && placeMaps.isNotEmpty) {
        developer.log('[HomeScreen] compute returned empty descriptors; falling back to placeMaps', name: 'HomeScreen');
        descriptors = placeMaps;
      }
  for (var i = 0; i < descriptors.length; i += batchSize) {
      final end = (i + batchSize) > descriptors.length ? descriptors.length : i + batchSize;
      final sub = descriptors.sublist(i, end);

      final batchMarkers = <Marker>{};
      for (final d in sub) {
        final markerId = MarkerId(d['id'] as String);
        final bool isGold = (d['isGold'] as bool?) ?? false;
        final marker = Marker(
          markerId: markerId,
          position: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
          icon: isGold
              ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow)
              : BitmapDescriptor.defaultMarker,
          infoWindow: InfoWindow(title: d['name'] as String, snippet: (d['category'] as String).replaceAll('_', ' ')),
          onTap: () {
            final place = idToPlace[d['id'] as String];
            if (place != null) _onMarkerTapped(place);
          },
        );
        batchMarkers.add(marker);
      }

      // Add this batch to the existing markers and allow the map to render.
      setState(() {
        _markers.addAll(batchMarkers);
      });

      // Yield to the event loop / UI thread so the map can paint.
      await Future.delayed(Duration(milliseconds: batchDelayMs));
    }
  }

  // Zoom helper methods removed; zoom controls were removed from the UI.

  Future<void> _onMarkerTapped(Place place) async {
    final user = FirebaseAuth.instance.currentUser;
    int userRating = 0;
    String userComment = '';
    List<Map<String, dynamic>> comments = [];
    double avgRating = 0;
    // Usar como ID del PDI: name_category (sin espacios)
    final pdiDocId = _sanitizeId('${place.name}_${place.category}');
    bool isGold = (place.specialCategories ?? []).contains('lista_gold');
    try {
      final reviewsSnap = await FirebaseFirestore.instance
          .collection('pdis_v2')
          .doc(pdiDocId)
          .collection('reviews')
          .where('status', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .get();
        if (reviewsSnap.docs.isNotEmpty) {
          comments = reviewsSnap.docs.map((doc) => doc.data()).toList();
          if (comments.isNotEmpty) {
            avgRating = comments.map((c) => (c['rating'] ?? 0) as num).reduce((a, b) => a + b) / comments.length;
          }
        }
      } catch (e, s) {
        developer.log('Failed to load reviews for $pdiDocId', name: 'HomeScreen', error: e, stackTrace: s);
        // keep UI responsive even if reviews fail
      }
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Expanded(child: Text(place.name)),
                  if (isGold)
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Chip(
                        label: const Text('Lista Gold', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                        backgroundColor: Colors.amberAccent,
                        avatar: const Icon(Icons.star, color: Colors.white, size: 18),
                      ),
                    ),
                  if (user != null)
                    FutureBuilder<QuerySnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('favorite_places')
                          .where('name', isEqualTo: place.name)
                          .where('category', isEqualTo: place.category)
                          .get(),
                      builder: (context, snapshot) {
                        bool isFavorite = false;
                        String? favoriteDocId;
                        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                          isFavorite = true;
                          favoriteDocId = snapshot.data!.docs.first.id;
                        }
                        return IconButton(
                          icon: Icon(
                            isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: Colors.redAccent,
                          ),
                          tooltip: isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
                          onPressed: () async {
                            if (isFavorite && favoriteDocId != null) {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .collection('favorite_places')
                                  .doc(favoriteDocId)
                                  .delete();
                            } else {
                              await FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(user.uid)
                                  .collection('favorite_places')
                                  .add({
                                ...place.toMap(),
                                'timestamp': FieldValue.serverTimestamp(),
                              });
                            }
                            Navigator.of(context).pop();
                            _onMarkerTapped(place); // Refresca el popup
                          },
                        );
                      },
                    ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Categoría: ${place.category.replaceAll('_', ' ')}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    if (place.description != null && place.description!.isNotEmpty)
                      Text(place.description!),
                    const SizedBox(height: 20),
                    if (avgRating > 0)
                      Row(
                        children: [
                          const Text('Valoración media: ', style: TextStyle(fontWeight: FontWeight.bold)),
                          ...List.generate(5, (i) => Icon(i < avgRating.round() ? Icons.star : Icons.star_border, color: Colors.amber, size: 20)),
                          Text(' (${avgRating.toStringAsFixed(1)})'),
                        ],
                      ),
                    const SizedBox(height: 10),
                    if (user != null) ...[
                      const Text('Valora este lugar:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: List.generate(5, (i) => GestureDetector(
                          onTap: () => setState(() => userRating = i + 1),
                          child: Icon(i < userRating ? Icons.star : Icons.star_border, color: Colors.amber, size: 32),
                        )),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        decoration: const InputDecoration(
                          labelText: 'Comentario',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 1,
                        maxLines: 3,
                        onChanged: (v) => userComment = v,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: userRating > 0
                            ? () async {
                                // Sanitize doc ID to avoid invalid path characters
                                final pdiDocId = _sanitizeId('${place.name}_${place.category}');
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('pdis_v2')
                                      .doc(pdiDocId)
                                      .collection('reviews')
                                      .add({
                                    'comment': userComment,
                                    'rating': userRating,
                                    'userId': user.uid,
                                    'status': 'pending',
                                    'createdAt': FieldValue.serverTimestamp(),
                                  });
                                } catch (e, s) {
                                  developer.log('Failed to add review for $pdiDocId', name: 'HomeScreen', error: e, stackTrace: s);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('No se pudo enviar la valoración. Intenta de nuevo.'), backgroundColor: Colors.red),
                                    );
                                  }
                                  return;
                                }
                                setState(() {
                                  userRating = 0;
                                  userComment = '';
                                });
                                Navigator.of(context).pop();
                                _onMarkerTapped(place); // Refresca el popup
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('¡Comentario enviado! Será visible tras aprobación.'), backgroundColor: Colors.green),
                                );
                              }
                            : null,
                        child: const Text('Enviar valoración'),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (comments.isNotEmpty) ...[
                      const Text('Últimos comentarios:', style: TextStyle(fontWeight: FontWeight.bold)),
                      ...comments.take(3).map((c) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ...List.generate(5, (i) => Icon(i < (c['rating'] ?? 0) ? Icons.star : Icons.star_border, color: Colors.amber, size: 16)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(c['comment'] ?? '', style: const TextStyle(fontStyle: FontStyle.italic))),
                          ],
                        ),
                      )),
                      const SizedBox(height: 20),
                    ],
                    const Text('¿Obtener indicaciones para llegar a este lugar?'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cerrar'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('Obtener Indicaciones'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        String selectedApp = 'Google Maps';
                        return StatefulBuilder(
                          builder: (context, setState) {
                            return AlertDialog(
                              title: const Text('Selecciona app de navegación'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  RadioListTile<String>(
                                    title: const Text('Google Maps'),
                                    value: 'Google Maps',
                                    groupValue: selectedApp,
                                    onChanged: (v) => setState(() => selectedApp = v!),
                                  ),
                                  RadioListTile<String>(
                                    title: const Text('Apple Maps'),
                                    value: 'Apple Maps',
                                    groupValue: selectedApp,
                                    onChanged: (v) => setState(() => selectedApp = v!),
                                  ),
                                  RadioListTile<String>(
                                    title: const Text('Waze'),
                                    value: 'Waze',
                                    groupValue: selectedApp,
                                    onChanged: (v) => setState(() => selectedApp = v!),
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  child: const Text('Cancelar'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                ElevatedButton(
                                  child: const Text('Abrir navegación'),
                                  onPressed: () async {
                                    final lat = place.position.latitude;
                                    final lon = place.position.longitude;
                                    String url = '';
                                    if (selectedApp == 'Google Maps') {
                                      url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon';
                                    } else if (selectedApp == 'Apple Maps') {
                                      url = 'http://maps.apple.com/?daddr=$lat,$lon';
                                    } else if (selectedApp == 'Waze') {
                                      url = 'https://waze.com/ul?ll=$lat,$lon&navigate=yes';
                                    }
                                    final uri = Uri.tryParse(url);
                                    if (uri != null) {
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri);
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('No se pudo abrir la app de navegación.')),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
                TextButton(
                  child: const Text('Guardar'),
                  onPressed: () async {
                    if (user != null) {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('saved_places')
                          .add(place.toMap());
                      if (mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Lugar guardado correctamente.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                ),
                TextButton(
                  child: const Text('Reportar incidencia'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) {
                        String motivo = '';
                        String comentario = '';
                        return StatefulBuilder(
                          builder: (context, setState) {
                            return AlertDialog(
                              title: const Text('Reportar incidencia'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(labelText: 'Motivo'),
                                    items: [
                                      'Información incorrecta',
                                      'Lugar cerrado',
                                      'No existe',
                                      'Otro',
                                    ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                    onChanged: (v) => setState(() => motivo = v ?? ''),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    decoration: const InputDecoration(labelText: 'Comentario (opcional)'),
                                    minLines: 1,
                                    maxLines: 3,
                                    onChanged: (v) => comentario = v,
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  child: const Text('Cancelar'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                ElevatedButton(
                                  onPressed: motivo.isNotEmpty ? () async {
                                    await FirebaseFirestore.instance.collection('users').doc(user?.uid).collection('reports').add({
                                      'name': place.name,
                                      'category': place.category,
                                      'motivo': motivo,
                                      'comentario': comentario,
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });
                                    Navigator.of(context).pop();
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Reporte enviado. ¡Gracias!'), backgroundColor: Colors.orange),
                                    );
                                  } : null,
                                  child: const Text('Enviar reporte'),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onMapLongPress(LatLng position) {
    // Open AddPoiScreen to let the user submit a POI at the pressed location
    // Build categories so they appear in the same order as the main "lupa" menu.
    // Exclude the 'lista_gold' category from the Add POI dropdown.
    final specialFiltered = _specialCategories.where((c) => c != 'lista_gold').toList();
    final assetExtras = _assetCategories.where((c) => !_orderedCategories.contains(c) && !specialFiltered.contains(c)).toList();
    final allCategories = [..._orderedCategories, ...specialFiltered, ...assetExtras];

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddPoiScreen(
          initialPosition: position,
          categories: allCategories,
        ),
      ),
    );
  }

  // ...existing code...

  Widget _buildDrawerMenuWithBadge() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => Scaffold.of(context).openDrawer(),
      );
    }

    // StreamBuilder para contact_messages
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('contact_messages')
          .snapshots(),
      builder: (context, contactSnapshot) {
        // StreamBuilder para user_messages
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('user_messages')
              .snapshots(),
          builder: (context, userSnapshot) {
            int unreadCount = 0;
            
            // Contar no leídos de contact_messages
            if (contactSnapshot.hasData) {
              unreadCount += contactSnapshot.data!.docs
                  .where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['toUid'] == user.uid && data['read'] != true;
                  })
                  .length;
            }
            
            // Contar no leídos de user_messages
            if (userSnapshot.hasData) {
              unreadCount += userSnapshot.data!.docs
                  .where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return data['toUid'] == user.uid && data['read'] != true;
                  })
                  .length;
            }
            
            return Badge(
              isLabelVisible: unreadCount > 0,
              label: Text(
                unreadCount > 9 ? '9+' : '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: Colors.red,
              child: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: _buildDrawerMenuWithBadge(),
        title: const Row(
          children: [
            Icon(Icons.directions_bus, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text('Bus Points', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _goToMyLocation,
            tooltip: 'Mi Ubicación',
          ),
        ],
      ),
      body: Stack(
              children: [
                GestureDetector(
                  onTap: _hideCategoryList,
                  child: GoogleMap(
                    mapType: MapType.normal,
          initialCameraPosition: _startingPosition != null
            ? CameraPosition(target: _startingPosition!, zoom: 15)
            : _initialCameraPosition,
                    markers: _markers,
                    onMapCreated: _onMapCreated,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    padding: const EdgeInsets.only(top: 80.0, bottom: 20.0),
                    onTap: (_) {
                      _searchFocusNode.unfocus();
                      _hideCategoryList();
                    },
                    onLongPress: _onMapLongPress,
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: _buildSearchCard(),
                ),
                if (_predictions.isNotEmpty)
                  Positioned(
                    top: 80,
                    left: 10,
                    right: 10,
                    child: _buildSuggestionsList(),
                  ),
                if (_isCategoryListVisible)
                  Center(
                    child: _buildCategoryList(),
                  ),
                // The add-POI FAB was removed: adding POIs is done via long-press on the map.
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleCategoryList,
        backgroundColor: Colors.blueAccent,
        child: const Icon(
          Icons.search,
          color: Colors.white,
          size: 32,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

   Widget _buildCategoryList() {
    Widget buildCategoryTile(String category) {
    final label = category
      .replaceAll('_', ' ')
      .split(' ')
      .map((word) =>
        word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
      .join(' ');
      return ListTile(
        title: Text(label, textAlign: TextAlign.center),
        onTap: () => _onCategorySelected(category),
      );
    }

    return Card(
      elevation: 8.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Mostrar Todos',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: _onSelectAll,
            ),
            ListTile(
              title: const Text('Ocultar Todos',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: _onDeselectAll,
            ),
            const Divider(),
            ..._orderedCategories.map(buildCategoryTile),
            const Divider(),
            ..._specialCategories.map(buildCategoryTile),
            const Divider(),
          ],
        ),
      ),
    );
  }

  // Zoom buttons removed from UI.

  Widget _buildSearchCard() {
    return Card(
      elevation: 4.0,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Buscar una dirección...',
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _predictions = []);
                    _searchFocusNode.unfocus();
                  },
                )
              : null,
        ),
      ),
    );
  }
  Widget _buildSuggestionsList() {
    return Card(
      elevation: 4.0,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: _predictions.length,
        itemBuilder: (context, index) {
          final prediction = _predictions[index];
          return ListTile(
            leading: const Icon(Icons.location_on_outlined, color: Colors.grey),
            title: Text(prediction.description),
            onTap: () {
              // En web, pasamos la dirección directamente
              if (kIsWeb) {
                _moveToPlace(prediction.description);
              } else {
                _moveToPlace(prediction.placeId);
              }
            },
          );
        },
      ),
    );
  }

} // <-- Cierre de la clase _HomeScreenState

// (Opcionalmente, si hay código fuera de la clase, puede ir aquí)
