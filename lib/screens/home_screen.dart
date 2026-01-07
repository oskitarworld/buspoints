// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:developer' as developer;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
// dart:convert already imported later in the file; remove duplicate import
import 'package:webview_flutter/webview_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:myapp/models/place.dart';
import 'package:myapp/widgets/app_drawer.dart';
import 'package:myapp/screens/add_poi_screen.dart';
import 'package:myapp/services/google_places_service.dart';
import 'package:myapp/services/firestore_service.dart';
// ...existing code...
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:myapp/widgets/native_streetview.dart';
import 'package:myapp/services/web_places_autocomplete.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:ui' as ui;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart' as fc;

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

// Google Places / Maps API Key
// NOTE: this key is used by the embedded Street View HTML loaded in a WebView.
// Make sure the key has appropriate restrictions (Android/iOS app restrictions) to avoid exposure.
const String googleApiKey = 'AIzaSyBtEYqVfNtm14WstANwadcr7SRLyhc_wCk';

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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final GooglePlacesService _placesService;
  final FirestoreService _firestoreService = FirestoreService();
  List<Place> _allPlaces = [];
  late final AnimationController _loadingIconController;
  // Cache of network-loaded BitmapDescriptors keyed by their URL.
  // Cache of BitmapDescriptors keyed by asset path or URL.
  final Map<String, BitmapDescriptor> _iconCache = {};
  bool _isRebuildingMarkers = false;

  // Mapping category (normalized) -> preferred icon filename (user provided).
  // The user requested specific icon filenames (icon-1.png, icon-2.png, ...).
  // We try these first (assets/icons/icon-*.png). If they are not bundled,
  // the asset load will fail gracefully and we fall back to legacy icons
  // already present in `assets/icons/`.
  // Preferred filename in Firebase Storage (pdis_icons/<filename>).
  // Use the simple canonical filenames that actually exist in the bucket
  // (icon-1.png, icon-2.png, ...). This avoids mismatches with display
  // labels that may include spaces or localized text.
  final Map<String, String> _categoryToIcon = {
    'parada_bus': 'icon-1.png',
    // Variants / import slugs (from assets/pdis/*.kml)
    'bus_stops': 'icon-1.png',
    'parada_de_bus': 'icon-1.png',
  'parking': 'icon-2.png',
  'parking_de_pago': 'icon-3.png',
    'carga_y_descarga': 'icon-6.png',
    'zona_espera': 'icon-8.png',
    'zonas_de_espera_o_autocares': 'icon-8.png',
    'gasolinera': 'icon-78.png',
    'gasolineras': 'icon-78.png',
    'hotel': 'icon-11.png',
    'restaurante': 'icon-12.png',
    'hoteles_y_restaurantes': 'icon-11.png',
    'otros': 'icon-82.png',
    // special lists
    'lista_blanca': 'icon-84.png',
    'lista_negra': 'icon-85.png',
    'lista_gold': 'icon-61.png',
  };

// ...existing code...

  // Fallbacks to existing readable asset filenames (present in repo).
  final Map<String, String> _categoryFallbacks = {
    'parada_bus': 'assets/icons/parada_bus.png',
    'parking': 'assets/icons/parking.png',
    'carga_y_descarga': 'assets/icons/carga_y_descarga.png',
    'zona_espera': 'assets/icons/zona_espera.png',
    'gasolinera': 'assets/icons/gasolinera.png',
    'hotel': 'assets/icons/hotel.png',
    'restaurante': 'assets/icons/restaurante.png',
    'otros': 'assets/icons/otros.png',
    'lista_blanca': 'assets/icons/lista_blanca.png',
    'lista_negra': 'assets/icons/lista_negra.png',
  };

  Future<BitmapDescriptor?> _loadAssetIcon(String assetPath) async {
    if (_iconCache.containsKey(assetPath)) return _iconCache[assetPath];
    try {
      // Increase requested asset size so markers are rendered larger on high-DPI devices.
      // Use the newer `asset` constructor instead of the deprecated `fromAssetImage`.
      // Note: BitmapDescriptor.asset may ignore ImageConfiguration; keep a try/catch
      // to fall back gracefully.
    final bd = await BitmapDescriptor.asset(const ImageConfiguration(size: Size(320, 320)), assetPath);
        _iconCache[assetPath] = bd;
        return bd;
      } catch (e) {
      developer.log('[HomeScreen] Failed to load asset icon $assetPath: $e', name: 'HomeScreen');
      return null;
    }
  }

  // Create a BitmapDescriptor from raw image bytes, scaling to [size] px width.
  Future<BitmapDescriptor> _bitmapDescriptorFromBytes(Uint8List data, {int size = 320}) async {
    try {
      final codec = await ui.instantiateImageCodec(data, targetWidth: size);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      // Use new bytes factory
      return BitmapDescriptor.bytes(bytes);
    } catch (e) {
      developer.log('[HomeScreen] _bitmapDescriptorFromBytes failed: $e', name: 'HomeScreen');
      // Fallback: return default marker in a synchronous way by throwing
      // (caller should handle), but here create from original bytes if possible
      return BitmapDescriptor.bytes(data);
    }
  }

  Future<BitmapDescriptor?> _loadStorageIcon(String filename) async {
    final key = 'storage://pdis_icons/$filename';
    if (_iconCache.containsKey(key)) return _iconCache[key];
    // We'll try multiple access strategies and also try an alternate
    // bucket name (some tooling/uploaders used the `*.firebasestorage.app`
    // host while the FirebaseOptions may point to `*.appspot.com`).
    final attempts = <String>[];

    // Quick dev-friendly optimization: if the project bundles the icons
    // under assets/pdis_icons/<filename>, prefer the local asset. This
    // lets you avoid Storage/AppCheck issues during development by
    // downloading the icons once and embedding them in the app.
    try {
      final assetPath = 'assets/pdis_icons/$filename';
      final assetBd = await _loadAssetIcon(assetPath);
      if (assetBd != null) {
        _iconCache[key] = assetBd;
        developer.log('[HomeScreen] loaded icon from bundled asset $assetPath', name: 'HomeScreen');
        return assetBd;
      }
    } catch (e) {
      developer.log('[HomeScreen] asset check failed for $filename: $e', name: 'HomeScreen');
    }
    try {
      // Primary: default configured bucket
      final ref = FirebaseStorage.instance.ref().child('pdis_icons').child(filename);
      developer.log('[HomeScreen] _loadStorageIcon: trying ref.bucket=${ref.bucket} ref.fullPath=${ref.fullPath}', name: 'HomeScreen');
      attempts.add('default');
      // Try lightweight SDK fetch first
      try {
        final bytes = await ref.getData(256 * 1024);
        if (bytes != null && bytes.isNotEmpty) {
          final bd = await _bitmapDescriptorFromBytes(bytes, size: 192);
          _iconCache[key] = bd;
          developer.log('[HomeScreen] loaded storage icon from SDK getData for $filename', name: 'HomeScreen');
          return bd;
        }
      } catch (e) {
        developer.log('[HomeScreen] ref.getData failed for $filename on default bucket: $e', name: 'HomeScreen');
      }

      // SDK getData didn't succeed — try downloadURL -> http.get
      try {
        final url = await ref.getDownloadURL();
        developer.log('[HomeScreen] getDownloadURL (default) for $filename -> $url', name: 'HomeScreen');
        final resp = await http.get(Uri.parse(url));
        developer.log('[HomeScreen] HTTP GET $url returned ${resp.statusCode} for $filename (default)', name: 'HomeScreen');
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          final bd = await _bitmapDescriptorFromBytes(resp.bodyBytes, size: 192);
          _iconCache[key] = bd;
          developer.log('[HomeScreen] loaded storage icon via HTTP fallback for $filename', name: 'HomeScreen');
          return bd;
        }
      } catch (e) {
        developer.log('[HomeScreen] getDownloadURL/http failed for $filename on default bucket: $e', name: 'HomeScreen');
      }

      // If we reached here, try an alternate bucket name (common variant).
      const altBucket = 'buspoint-49ea0.firebasestorage.app';
      attempts.add('alt:$altBucket');
      try {
        final altStorage = FirebaseStorage.instanceFor(bucket: altBucket);
        final altRef = altStorage.ref().child('pdis_icons').child(filename);
        developer.log('[HomeScreen] trying altRef.bucket=${altRef.bucket} altRef.fullPath=${altRef.fullPath}', name: 'HomeScreen');
        try {
          final bytes = await altRef.getData(256 * 1024);
          if (bytes != null && bytes.isNotEmpty) {
            final bd = await _bitmapDescriptorFromBytes(bytes, size: 192);
            _iconCache[key] = bd;
            developer.log('[HomeScreen] loaded storage icon from SDK getData for $filename (alt)', name: 'HomeScreen');
            return bd;
          }
        } catch (e) {
          developer.log('[HomeScreen] altRef.getData failed for $filename: $e', name: 'HomeScreen');
        }
        try {
          final url = await altRef.getDownloadURL();
          developer.log('[HomeScreen] getDownloadURL (alt) for $filename -> $url', name: 'HomeScreen');
          final resp = await http.get(Uri.parse(url));
          developer.log('[HomeScreen] HTTP GET $url returned ${resp.statusCode} for $filename (alt)', name: 'HomeScreen');
          if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
            final bd = await _bitmapDescriptorFromBytes(resp.bodyBytes, size: 192);
            _iconCache[key] = bd;
            developer.log('[HomeScreen] loaded storage icon via HTTP fallback for $filename (alt)', name: 'HomeScreen');
            return bd;
          }
        } catch (e) {
          developer.log('[HomeScreen] getDownloadURL/http failed for $filename on alt bucket: $e', name: 'HomeScreen');
        }
      } catch (e) {
        developer.log('[HomeScreen] Failed to access alt storage instance: $e', name: 'HomeScreen');
      }

      developer.log('[HomeScreen] All storage attempts failed for $filename: tried=${attempts.join(',')}', name: 'HomeScreen');
      // Final fallback: attempt well-known public URL patterns (bypass SDK/getDownloadURL)
      try {
        final encodedPath = Uri.encodeComponent('pdis_icons/$filename');
        final public1 = 'https://firebasestorage.googleapis.com/v0/b/${FirebaseStorage.instance.app.options.storageBucket}/o/$encodedPath?alt=media';
        developer.log('[HomeScreen] Trying public URL (pattern1): $public1', name: 'HomeScreen');
        final r1 = await http.get(Uri.parse(public1));
        developer.log('[HomeScreen] HTTP GET public1 returned ${r1.statusCode} for $filename', name: 'HomeScreen');
        if (r1.statusCode == 200 && r1.bodyBytes.isNotEmpty) {
            final bd = await _bitmapDescriptorFromBytes(r1.bodyBytes, size: 192);
          _iconCache[key] = bd;
          developer.log('[HomeScreen] loaded storage icon via public1 for $filename', name: 'HomeScreen');
          return bd;
        }
      } catch (e) {
        developer.log('[HomeScreen] public1 fetch failed for $filename: $e', name: 'HomeScreen');
      }

      try {
        // alternate public host
        final bucketName = FirebaseStorage.instance.app.options.storageBucket ?? 'buspoint-49ea0.appspot.com';
        final public2 = 'https://storage.googleapis.com/$bucketName/pdis_icons/$filename';
        developer.log('[HomeScreen] Trying public URL (pattern2): $public2', name: 'HomeScreen');
        final r2 = await http.get(Uri.parse(public2));
        developer.log('[HomeScreen] HTTP GET public2 returned ${r2.statusCode} for $filename', name: 'HomeScreen');
        if (r2.statusCode == 200 && r2.bodyBytes.isNotEmpty) {
          final bd = await _bitmapDescriptorFromBytes(r2.bodyBytes, size: 192);
          _iconCache[key] = bd;
          developer.log('[HomeScreen] loaded storage icon via public2 for $filename', name: 'HomeScreen');
          return bd;
        }
      } catch (e) {
        developer.log('[HomeScreen] public2 fetch failed for $filename: $e', name: 'HomeScreen');
      }

      return null;
    } catch (e) {
      developer.log('[HomeScreen] Failed to load storage icon $filename: $e', name: 'HomeScreen');
      return null;
    }
  }

  // When true, force use of default markers and skip fetching custom icons.
  // Set to false in production so category-based icons (Storage/assets) are used.
  final bool _forceDefaultIcons = false;
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

  bool _cameraMoved = false;
  void _onMapCreated(GoogleMapController controller) {
    if (!_mapController.isCompleted) {
      _mapController.complete(controller);
    }
  }

  void _cycleMapType() {
    setState(() {
      if (_mapType == MapType.normal) {
        _mapType = MapType.satellite;
      } else if (_mapType == MapType.satellite) {
        _mapType = MapType.hybrid;
      } else if (_mapType == MapType.hybrid) {
        _mapType = MapType.terrain;
      } else {
        _mapType = MapType.normal;
      }
    });
  }

  // This helper is intentionally retained for on-demand refreshes; keep the
  // analyzer quiet if it's not referenced by build-time camera events.
  // ignore: unused_element
  Future<void> _loadPoisForVisibleRegion({double paddingDegrees = 0.05, int limit = 1000}) async {
    try {
      final controller = await _mapController.future;
      final bounds = await controller.getVisibleRegion();
      developer.log('[HomeScreen] Visible region bounds: SW=${bounds.southwest.latitude},${bounds.southwest.longitude} NE=${bounds.northeast.latitude},${bounds.northeast.longitude}', name: 'HomeScreen');
      // Load POIs in the visible bounds
      final visiblePlaces = await _firestoreService.getPoisInBounds(bounds, paddingDegrees: paddingDegrees, limit: limit);
  // Also load POIs within 100 km of the map center to cover nearby points
  final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2.0;
      double centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2.0;
      // Handle dateline wrap-around approximately
      if ((bounds.northeast.longitude - bounds.southwest.longitude).abs() > 180) {
        centerLng = (bounds.northeast.longitude + bounds.southwest.longitude + 360) / 2.0;
        if (centerLng > 180) centerLng -= 360;
      }
      final center = LatLng(centerLat, centerLng);
  final radiusPlaces = await _firestoreService.getPoisInRadius(center, 100.0, limit: 2000);
  // Also include approved user-submitted POIs in bounds and radius
  final visibleUserPlaces = await _firestoreService.getUserPoisInBounds(bounds, paddingDegrees: paddingDegrees, limit: 500);
  final radiusUserPlaces = await _firestoreService.getUserPoisInRadius(center, 100.0, limit: 1000);

      // Merge and deduplicate by rounded coords + name
      final Map<String, Place> merged = {};
      void addPlace(Place p) {
        final key = '${p.position.latitude.toStringAsFixed(6)}:${p.position.longitude.toStringAsFixed(6)}:${p.name.toLowerCase()}';
        if (!merged.containsKey(key)) merged[key] = p;
      }

  for (final p in visiblePlaces) {
    addPlace(p);
  }
  for (final p in radiusPlaces) {
    addPlace(p);
  }
  for (final p in visibleUserPlaces) {
    addPlace(p);
  }
  for (final p in radiusUserPlaces) {
    addPlace(p);
  }

      final places = merged.values.toList();
      if (!mounted) return;
      developer.log('[HomeScreen] Loaded ${places.length} places for visible region+radius', name: 'HomeScreen');
      setState(() {
        _allPlaces = places;
      });
  await _updateMarkersFromPlaces(_allPlaces, skipIconCacheClear: true);
    } catch (e, s) {
      developer.log('Error cargando POIs por región visible: $e', name: 'HomeScreen', error: e, stackTrace: s);
    }
  }

  /// Load all POIs (on-demand). This is heavy and should be used only when
  /// the user explicitly requests 'Mostrar todos'. We cap the number to avoid
  /// OOM on devices.
  Future<void> _loadPoisAll({int limit = 5000}) async {
    try {
      developer.log('[HomeScreen] User requested load all POIs (map-limited, limit=$limit)', name: 'HomeScreen');
      // Clear markers before loading so UI is responsive.
      if (mounted) setState(() { _markers.clear(); });

      // Compute visible bounds and center, then load POIs within bounds
      // and within 50 km radius of the map center to keep results small.
      final controller = await _mapController.future;
      final bounds = await controller.getVisibleRegion();
      final visiblePlaces = await _firestoreService.getPoisInBounds(bounds, paddingDegrees: 0.05, limit: 1500);

      // center calculation (handle dateline approx)
      final centerLat = (bounds.northeast.latitude + bounds.southwest.latitude) / 2.0;
      double centerLng = (bounds.northeast.longitude + bounds.southwest.longitude) / 2.0;
      if ((bounds.northeast.longitude - bounds.southwest.longitude).abs() > 180) {
        centerLng = (bounds.northeast.longitude + bounds.southwest.longitude + 360) / 2.0;
        if (centerLng > 180) centerLng -= 360;
      }
      final center = LatLng(centerLat, centerLng);
      final radiusPlaces = await _firestoreService.getPoisInRadius(center, 50.0, limit: 2000);

      // Include approved user-submitted POIs in bounds and radius (client normalizes missing lat/lng)
      final visibleUserPlaces = await _firestoreService.getUserPoisInBounds(bounds, paddingDegrees: 0.05, limit: 500);
  final radiusUserPlaces = await _firestoreServiceGetUserPoisInRadiusFallback(center, 50.0, limit: 1000);

      // Merge and dedupe
      final Map<String, Place> merged = {};
      void addPlace(Place p) {
        final key = '${p.position.latitude.toStringAsFixed(6)}:${p.position.longitude.toStringAsFixed(6)}:${p.name.toLowerCase()}';
        if (!merged.containsKey(key)) merged[key] = p;
      }
      for (final p in visiblePlaces) {
        addPlace(p);
      }
      for (final p in radiusPlaces) {
        addPlace(p);
      }
      for (final p in visibleUserPlaces) {
        addPlace(p);
      }
      for (final p in radiusUserPlaces) {
        addPlace(p);
      }

      final places = merged.values.toList();
      if (!mounted) return;
      developer.log('[HomeScreen] Loaded ${places.length} places for map area + 50km', name: 'HomeScreen');
      setState(() { _allPlaces = places; });
      // Preload expected icons (assets first) to avoid a race where the
      // 'Mostrar todos' marker creation runs before _iconCache is populated.
      try {
        final Set<String> preloadAssets = {};
        final Set<String> preloadStorageFiles = {};
        for (final p in places) {
          String? chosenAsset;
          if ((p.specialCategories ?? []).isNotEmpty) {
            for (final sc in p.specialCategories!) {
              final scKey = sc.toString().toLowerCase();
              if (_categoryToIcon.containsKey(scKey)) {
                chosenAsset = _categoryToIcon[scKey];
                break;
              }
            }
          }
          if (chosenAsset == null) {
            final catKey = p.category.toString().trim().toLowerCase();
            if (_categoryToIcon.containsKey(catKey)) chosenAsset = _categoryToIcon[catKey];
            if ((chosenAsset == null || chosenAsset.isEmpty) && _categoryFallbacks.containsKey(catKey)) chosenAsset = _categoryFallbacks[catKey];
          }
          if (chosenAsset != null) {
            if (chosenAsset.startsWith('assets/')) {
              preloadAssets.add(chosenAsset);
            } else {
              preloadAssets.add('assets/pdis_icons/$chosenAsset');
              preloadAssets.add('assets/icons/$chosenAsset');
              preloadStorageFiles.add(chosenAsset);
            }
          }
        }

        // Load a limited number of bundled assets synchronously so cache is
        // populated before markers, but avoid doing too many heavy decodes
        // on the main thread (which can cause frame drops and ImageReader
        // buffer exhaustion). We pick the first N unique assets.
        const int maxPreloads = 24; // tuneable cap
        var count = 0;
        for (final asset in preloadAssets) {
          if (count >= maxPreloads) break;
          if (!_iconCache.containsKey(asset)) {
            await _loadAssetIcon(asset);
            developer.log('[HomeScreen] Preloaded asset $asset', name: 'HomeScreen');
            count++;
            // yield briefly to the event loop so the UI can breathe
            await Future.delayed(const Duration(milliseconds: 8));
          }
        }

        // Kick off storage loads in background (don't block long on network)
        for (final filename in preloadStorageFiles) {
          final key = 'storage://pdis_icons/$filename';
          if (!_iconCache.containsKey(key)) {
            _loadStorageIcon(filename).then((bd) {
              if (bd != null) developer.log('[HomeScreen] Preloaded storage icon $filename', name: 'HomeScreen');
            }).catchError((e) {
              developer.log('[HomeScreen] preload storage icon failed for $filename: $e', name: 'HomeScreen');
            });
          }
        }
      } catch (e, s) {
        developer.log('[HomeScreen] Preload icons failed: $e', name: 'HomeScreen', error: e, stackTrace: s);
      }

      await _updateMarkersFromPlaces(_allPlaces);
    } catch (e, s) {
      developer.log('Error cargando todos los POIs (map-limited): $e', name: 'HomeScreen', error: e, stackTrace: s);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error cargando POIs: ${e.toString()}')));
    }
  }

  // Helper fallback to obtain user POIs in radius using client-side filtering
  // (some user_pois lack top-level lat/lng; FirestoreService has a faster
  // variant but we keep this as a safe fallback path).
  Future<List<Place>> _firestoreServiceGetUserPoisInRadiusFallback(LatLng center, double kmRadius, {int limit = 1000}) async {
    try {
      return await _firestoreService.getUserPoisInRadius(center, kmRadius, limit: limit);
    } catch (e, s) {
      developer.log('[HomeScreen] fallback getUserPoisInRadius failed: $e', name: 'HomeScreen', error: e, stackTrace: s);
      // As a fallback, fetch approved user_pois and filter client-side by distance.
      try {
        final snap = await FirebaseFirestore.instance.collection('user_pois').where('status', isEqualTo: 'approved').limit(limit).get();
        final List<Place> out = [];
        for (final doc in snap.docs) {
          final data = doc.data();
          double? lat; double? lng;
          if (data.containsKey('latitude') && data.containsKey('longitude')) {
            final rawLat = data['latitude']; final rawLng = data['longitude'];
            lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
            lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
          }
          if (lat == null || lng == null) continue;
          final dist = Geolocator.distanceBetween(center.latitude, center.longitude, lat, lng) / 1000.0;
          if (dist <= kmRadius) {
            out.add(Place(name: (data['name'] ?? '') as String, category: (data['category'] ?? '') as String, position: LatLng(lat, lng), description: data['description'] as String?));
          }
        }
        return out;
      } catch (e2, s2) {
        developer.log('[HomeScreen] fallback full user_pois read failed: $e2', name: 'HomeScreen', error: e2, stackTrace: s2);
        return [];
      }
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
    // When a category is selected, close the category list immediately and
    // show a small loading popup while we fetch POIs for that category.
    // This provides clearer feedback to the user that the app is working
    // and avoids leaving the category list open during long queries.
    () async {
      _hideCategoryList();
      _showLoadingDialog();
      try {
        await _loadPlacesByCategory(category);
        // Enable auto-sync after a successful category selection so that
        // subsequent camera moves refresh the visible POIs for that
        // category.
        if (mounted) {
          setState(() {
            _activeCategoryKey = category.toLowerCase().replaceAll(RegExp(r"[\s-]+"), '_');
            _autoSyncAfterCategorySelected = true;
          });
        }
      } finally {
        _hideLoadingDialog();
      }
    }();
  }

  void _showLoadingDialog() {
    // Start the rotating icon animation and show a modal dialog.
    try {
      _loadingIconController.repeat();
    } catch (_) {}
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RotationTransition(
                  turns: _loadingIconController,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.location_on, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Cargando PDIs…', style: TextStyle(fontWeight: FontWeight.w600)),
                    SizedBox(height: 6),
                    SizedBox(width: 160, child: LinearProgressIndicator()),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _hideLoadingDialog() {
    try {
      _loadingIconController.stop();
    } catch (_) {}
    if (Navigator.canPop(context)) Navigator.pop(context);
  }

  Future<void> _loadPlacesByCategory(String categoryKey) async {
    final effectiveCategoryKey = categoryKey.toLowerCase().replaceAll(RegExp(r"[\s-]+"), '_');
    final List<Place> places = [];
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pdisDocs = [];
    try {
      // Query canonical PDIs collection for the requested category.
      // Limit to a reasonable number to avoid overwhelming the client.
      try {
        // Fetch from multiple canonical collections so the category search
        // covers all POI sources (canonical pdis_v2, legacy Pdis_full and
        // the `pois` collection). We append results into pdisDocs.
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> agg = [];
        try {
          final q1 = FirebaseFirestore.instance.collection('pdis_v2').where('category', isEqualTo: effectiveCategoryKey).limit(2000);
          final snap1 = await q1.get();
          agg.addAll(snap1.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>());
          developer.log('[HomeScreen] pdis_v2 fetched: ${snap1.docs.length} docs for category $effectiveCategoryKey', name: 'HomeScreen');
        } catch (e) {
          developer.log('[HomeScreen] Failed to fetch pdis_v2 for category $effectiveCategoryKey: $e', name: 'HomeScreen');
        }
        try {
          final q2 = FirebaseFirestore.instance.collection('Pdis_full').where('category', isEqualTo: effectiveCategoryKey).limit(2000);
          final snap2 = await q2.get();
          agg.addAll(snap2.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>());
          developer.log('[HomeScreen] Pdis_full fetched: ${snap2.docs.length} docs for category $effectiveCategoryKey', name: 'HomeScreen');
        } catch (e) {
          developer.log('[HomeScreen] Failed to fetch Pdis_full for category $effectiveCategoryKey: $e', name: 'HomeScreen');
        }
        try {
          final q3 = FirebaseFirestore.instance.collection('pois').where('category', isEqualTo: effectiveCategoryKey).limit(2000);
          final snap3 = await q3.get();
          agg.addAll(snap3.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>());
          developer.log('[HomeScreen] pois fetched: ${snap3.docs.length} docs for category $effectiveCategoryKey', name: 'HomeScreen');
        } catch (e) {
          developer.log('[HomeScreen] Failed to fetch pois for category $effectiveCategoryKey: $e', name: 'HomeScreen');
        }

        // Deduplicate by document path (collection__id) while preserving list
        final seen = <String>{};
        pdisDocs = [];
        for (final d in agg) {
          final key = d.reference.path;
          if (seen.contains(key)) continue;
          seen.add(key);
          pdisDocs.add(d);
        }
        developer.log('[HomeScreen] aggregated canonical POIs: ${pdisDocs.length} unique docs for category $effectiveCategoryKey', name: 'HomeScreen');
      } catch (e) {
        developer.log('[HomeScreen] Failed to aggregate canonical POIs for category $effectiveCategoryKey: $e', name: 'HomeScreen');
      }

      // Include approved user-submitted POIs for this category. Some user
      // POIs have inconsistent category values or missing fields, so we
      // fetch approved user_pois (bounded) and filter client-side by a
      // normalized category comparison. This ensures uploads are shown
      // even if their `category` value differs in formatting.
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection('user_pois')
            .where('status', isEqualTo: 'approved')
            .limit(2000)
            .get();
  developer.log('[HomeScreen] user_pois fetched for client-side filter: ${userSnap.docs.length} docs (effectiveCategory=$effectiveCategoryKey)', name: 'HomeScreen');

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> userDocs = userSnap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>().toList();
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> matchedByCat = [];
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> potentialMatches = [];

        int idx = 0;
        for (final doc in userDocs) {
          final data = doc.data();
          final rawCat = data['category'];
          final catStr = (rawCat == null) ? '' : rawCat.toString();
          final normalizedUserCat = catStr.toLowerCase().replaceAll(RegExp(r"[\s-]+"), '_');
          final isMatch = (normalizedUserCat == effectiveCategoryKey) ||
              (effectiveCategoryKey == 'otros' && (normalizedUserCat == 'otros' || catStr.isEmpty));
          if (isMatch) {
            matchedByCat.add(doc);
          } else {
            potentialMatches.add(doc);
          }
          // Log a few samples to help debugging category mismatches
          if (idx < 6) {
            developer.log('[HomeScreen] user_poi sample: id=${doc.id} rawCat="$catStr" normalized="$normalizedUserCat" name="${(data['name'] ?? '')}"', name: 'HomeScreen');
          }
          idx++;
        }

        // If no exact category matches, try fuzzy matching by tokens in name/description
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docsToProcess = matchedByCat;
        if (docsToProcess.isEmpty && effectiveCategoryKey != 'otros') {
          final tokens = effectiveCategoryKey.split('_').where((t) => t.isNotEmpty).toList();
          for (final doc in potentialMatches) {
            final d = doc.data();
            final name = (d['name'] ?? '').toString().toLowerCase();
            final desc = (d['description'] ?? '').toString().toLowerCase();
            bool any = false;
            for (final t in tokens) {
              if (name.contains(t) || desc.contains(t)) { any = true; break; }
            }
            if (any) docsToProcess.add(doc);
          }
        }

        for (final doc in docsToProcess) {
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
        developer.log('Error loading user_pois for category (client-filter): $e', name: 'HomeScreen', error: e, stackTrace: s);
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
            .where('category', isEqualTo: effectiveCategoryKey)
            .limit(500);
        final userSnap = await userQ.get();
  developer.log('[HomeScreen] user_pois query returned ${userSnap.docs.length} docs (category eq $effectiveCategoryKey)', name: 'HomeScreen');
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
        // Fallback: try fetching approved POIs (including user_pois) and
        // filter by category more leniently (token match) in case documents
        // had slightly different category strings.
        try {
          final approved = await _firestoreService.getApprovedPois(limit: 2000, includeUserPois: true);
          final tokens = effectiveCategoryKey.split('_').where((t) => t.isNotEmpty).toList();
          final fallback = approved.where((p) {
            final cat = p.category.toLowerCase();
            if (cat == effectiveCategoryKey) return true;
            // token fuzzy match against category, name, description
            for (final t in tokens) {
              if (cat.contains(t)) return true;
              if (p.name.toLowerCase().contains(t)) return true;
              if ((p.description ?? '').toLowerCase().contains(t)) return true;
            }
            return false;
          }).toList();
          developer.log('[HomeScreen] fallbackApproved filtered count=${fallback.length} for category=$effectiveCategoryKey', name: 'HomeScreen');
          if (fallback.isNotEmpty) {
            await _updateMarkersFromPlaces(fallback);
          } else {
            setState(() { _markers.clear(); });
          }
        } catch (e, s) {
          developer.log('[HomeScreen] fallbackApproved failed: $e', name: 'HomeScreen', error: e, stackTrace: s);
          setState(() { _markers.clear(); });
        }
      }
    } catch (e, s) {
      developer.log('Error loading POIs by category: $e', name: 'HomeScreen', error: e, stackTrace: s);
    }
  }

  void _onSelectAll() {
    // Load all POIs from Firestore when the user requests 'Mostrar todos'.
    // This can be heavy, so show the loading dialog while the operation runs.
    () async {
      _hideCategoryList();
      _showLoadingDialog();
      try {
        // Primary load using the existing bounds+radius approach
        await _loadPoisAll();

        // Additionally, ensure we include any approved `user_pois` that
        // might have been missed by the bounds/radius logic by fetching
        // approved POIs (including user-submitted) and merging them.
        try {
          final approved = await _firestoreService.getApprovedPois(limit: 2000, includeUserPois: true);
          // Merge into _allPlaces deduplicating by rounded coords + name
          final Map<String, Place> merged = { for (final p in _allPlaces) '${p.position.latitude.toStringAsFixed(6)}:${p.position.longitude.toStringAsFixed(6)}:${p.name.toLowerCase()}': p };
          for (final p in approved) {
            final key = '${p.position.latitude.toStringAsFixed(6)}:${p.position.longitude.toStringAsFixed(6)}:${p.name.toLowerCase()}';
            if (!merged.containsKey(key)) merged[key] = p;
          }
          final mergedList = merged.values.toList();
          if (mounted) {
            setState(() {
              _allPlaces = mergedList;
              // When showing all POIs, disable category auto-sync.
              _autoSyncAfterCategorySelected = false;
              _activeCategoryKey = null;
            });
            await _updateMarkersFromPlaces(_allPlaces, skipIconCacheClear: true);
          }
        } catch (e, s) {
          developer.log('[HomeScreen] failed to merge approved POIs: $e', name: 'HomeScreen', error: e, stackTrace: s);
        }
      } finally {
        _hideLoadingDialog();
      }
    }();
  }

  void _onDeselectAll() {
    // Implementa la lógica para ocultar todos
    setState(() {
      _markers.clear();
      // Clearing selection disables auto-sync
      _autoSyncAfterCategorySelected = false;
      _activeCategoryKey = null;
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
  // Key to control the Scaffold (used to open the drawer reliably)
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  MapType _mapType = MapType.normal;
  final List<String> _orderedCategories = [
    'parada_bus', 'parking', 'parking_de_pago', 'carga_y_descarga', 'zona_espera', 'gasolinera', 'hotel', 'restaurante', 'otros',
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
  // When true, after the user selects a category the map will auto-refresh
  // POIs on camera movements (onCameraIdle). This is enabled when a
  // category is actively selected and disabled when the user clears selection
  // or requests 'Mostrar todos'.
  bool _autoSyncAfterCategorySelected = false;
  String? _activeCategoryKey;

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

  final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
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
  _placesService = GooglePlacesService(googleApiKey);
    _loadingIconController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    // Try to determine the device start position early so the map can
    // initialize centered on the user's location.
    _determineStartPosition();
    // Cargar categorías desde assets y POIs aprobados
    _loadAssetCategories().then((_) {
      // Do not auto-load POIs on startup. The app will start with an empty
      // map and the user can request POIs by category or load all.
      _showAddPoiTipIfNeeded();
    });
  }

  @override
  void dispose() {
    try {
      _loadingIconController.dispose();
    } catch (_) {}
    super.dispose();
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

  final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
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

  // _loadPois() removed: map-load behavior is handled via _loadPoisForVisibleRegion

  Future<void> _updateMarkersFromPlaces(List<Place> places, {bool skipIconCacheClear = false}) async {
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
      // Clear cached icon bitmaps so the app refetches images from the
      // new `iconPath` values in Firestore. This helps when iconPath was
      // updated remotely but the running app kept old BitmapDescriptors.
          if (!skipIconCacheClear && _iconCache.isNotEmpty) {
            _iconCache.clear();
            developer.log('[HomeScreen] _iconCache cleared to force icon refetch', name: 'HomeScreen');
          }
  for (var i = 0; i < descriptors.length; i += batchSize) {
      final end = (i + batchSize) > descriptors.length ? descriptors.length : i + batchSize;
      final sub = descriptors.sublist(i, end);

      final batchMarkers = <Marker>{};
      // Attempt to use custom icons if the Place contains an `iconPath` URL.
      // We fetch and cache BitmapDescriptors for unique URLs encountered in
      // this batch. Network fetch is asynchronous, so we may first add
      // markers with default icons and then update them once the icons
      // are available.
      final Set<String> urlsToFetch = {};
  final Set<String> assetsToLoad = {};
  final Set<String> storageFilesToLoad = {};
      for (final d in sub) {
        final place = idToPlace[d['id'] as String];
        final ip = place?.iconPath;
        if (!_forceDefaultIcons && ip != null && ip.startsWith('http')) urlsToFetch.add(ip);

        // derive normalized category key and see if we have mapping
        final cat = (place?.category ?? '').toString().trim().toLowerCase();
        String? assetPath;
        if (cat.isNotEmpty && _categoryToIcon.containsKey(cat)) {
          assetPath = _categoryToIcon[cat];
        }
        // if place has specialCategories (lista_gold etc), prefer those icons
        if (place != null && (place.specialCategories ?? []).isNotEmpty) {
          for (final sc in place.specialCategories!) {
            final scKey = sc.toString().toLowerCase();
            if (_categoryToIcon.containsKey(scKey)) {
              assetPath = _categoryToIcon[scKey];
              break;
            }
          }
        }
        // fallback mapping if primary asset not present
        if ((assetPath == null || assetPath.isEmpty) && _categoryFallbacks.containsKey(cat)) {
          assetPath = _categoryFallbacks[cat];
        }
        if (assetPath != null) {
          // assetPath may be a bare filename (icon-1.png) or a full asset path
          if (assetPath.startsWith('assets/')) {
            assetsToLoad.add(assetPath);
          } else {
            // try the dev-friendly pdis_icons folder first, then legacy assets/icons
            assetsToLoad.add('assets/pdis_icons/$assetPath');
            assetsToLoad.add('assets/icons/$assetPath');
          }
        }
        // if we have a storage filename mapping, queue it for load as well
        if (cat.isNotEmpty && _categoryToIcon.containsKey(cat)) {
          storageFilesToLoad.add(_categoryToIcon[cat]!);
        }
      }

      // Fetch network icons (non-blocking) and load asset icons. We do both
      // in parallel but catch errors individually so marker rendering still
      // proceeds with defaults.
      (() async {
        // Load assets first (fast, bundled)
        for (final asset in assetsToLoad) {
          if (!_iconCache.containsKey(asset)) {
            await _loadAssetIcon(asset);
          }
        }

        // Then fetch remote URLs if allowed
        for (final url in urlsToFetch) {
          if (!_iconCache.containsKey(url)) {
            try {
              final resp = await http.get(Uri.parse(url));
              if (resp.statusCode == 200) {
                final bytes = resp.bodyBytes;
                try {
                  final bd = await _bitmapDescriptorFromBytes(bytes, size: 192);
                  _iconCache[url] = bd;
                } catch (e) {
                  developer.log('Failed to create BitmapDescriptor from $url: $e', name: 'HomeScreen');
                }
              }
            } catch (e) {
              developer.log('Failed to fetch icon $url: $e', name: 'HomeScreen');
            }
          }
        }

        // Try loading icons from Firebase Storage (pdis_icons/<filename>) if present
        for (final filename in storageFilesToLoad) {
          final key = 'storage://pdis_icons/$filename';
          if (!_iconCache.containsKey(key)) {
            await _loadStorageIcon(filename);
          }
        }

        // Once loaded, rebuild markers to apply custom icons where available.
        if (mounted) {
          // Trigger a lightweight setState to refresh UI immediately.
          setState(() {});
          // Then schedule a full rebuild of markers using the freshly-loaded
          // icons. Use addPostFrameCallback to avoid re-entrancy issues and
          // a guard flag to prevent repeated rebuild scheduling.
          if (!_isRebuildingMarkers) {
            _isRebuildingMarkers = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                // Rebuild markers using the same places list so icons are
                // applied synchronously from _iconCache on the second pass.
                await _updateMarkersFromPlaces(places);
              } catch (e) {
                developer.log('[HomeScreen] failed scheduled marker rebuild: $e', name: 'HomeScreen');
              } finally {
                _isRebuildingMarkers = false;
              }
            });
          }
        }
      })();

      for (final d in sub) {
        final markerId = MarkerId(d['id'] as String);
        final bool isGold = (d['isGold'] as bool?) ?? false;
        final place = idToPlace[d['id'] as String];
        BitmapDescriptor icon = isGold
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow)
            : BitmapDescriptor.defaultMarker;

        // Prepare some helpers
        final ip = place?.iconPath;
        final catKey = (place?.category ?? '').toString().trim().toLowerCase();

        // Prefer special category icons (lista_gold / lista_blanca / lista_negra)
        String? chosenAsset;
        if (place != null && (place.specialCategories ?? []).isNotEmpty) {
          for (final sc in place.specialCategories!) {
            final scKey = sc.toString().toLowerCase();
            if (_categoryToIcon.containsKey(scKey)) {
              chosenAsset = _categoryToIcon[scKey];
              break;
            }
          }
        }
        // Then category-based asset
        if (chosenAsset == null) {
          if (_categoryToIcon.containsKey(catKey)) chosenAsset = _categoryToIcon[catKey];
          if ((chosenAsset == null || chosenAsset.isEmpty) && _categoryFallbacks.containsKey(catKey)) chosenAsset = _categoryFallbacks[catKey];
        }

        if (chosenAsset != null) {
          // try storage key first
          final storageKey = 'storage://pdis_icons/$chosenAsset';
          final assetKeyPdis = 'assets/pdis_icons/$chosenAsset';
          final assetKeyLegacy = chosenAsset.startsWith('assets/') ? chosenAsset : 'assets/icons/$chosenAsset';
          // Diagnostic log: show which keys we will check and whether they exist
          developer.log('[HomeScreen] Marker diagnostic: catKey=$catKey chosenAsset=$chosenAsset storageKeyPresent=${_iconCache.containsKey(storageKey)} assetKeyPdisPresent=${_iconCache.containsKey(assetKeyPdis)} assetKeyLegacyPresent=${_iconCache.containsKey(assetKeyLegacy)} ipPresent=${ip != null && _iconCache.containsKey(ip)}', name: 'HomeScreen');
          if (_iconCache.containsKey(storageKey)) {
            icon = _iconCache[storageKey]!;
          } else if (_iconCache.containsKey(assetKeyPdis)) {
            icon = _iconCache[assetKeyPdis]!;
          } else if (_iconCache.containsKey(assetKeyLegacy)) {
            icon = _iconCache[assetKeyLegacy]!;
          }
        }
        if (icon == BitmapDescriptor.defaultMarker && place?.iconPath != null && _iconCache.containsKey(place!.iconPath!)) {
          // fallback to remote iconPath if available
          icon = _iconCache[place.iconPath!]!;
        }
        final marker = Marker(
          markerId: markerId,
          position: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
          icon: icon,
          // Anchor the marker so its bottom center corresponds to the geo coordinate
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(title: d['name'] as String, snippet: (d['category'] as String).replaceAll('_', ' ')),
          onTap: () {
            if (place != null) _onMarkerTapped(place);
          },
        );
        batchMarkers.add(marker);
      }

      // Add this batch to the existing markers and allow the map to render.
      setState(() {
        _markers.addAll(batchMarkers);
        developer.log('[HomeScreen] _markers count after adding batch: ${_markers.length}', name: 'HomeScreen');
        if (_markers.isNotEmpty) {
          final sample = _markers.first;
          developer.log('[HomeScreen] Sample marker: id=${sample.markerId.value} pos=${sample.position.latitude},${sample.position.longitude}', name: 'HomeScreen');
        }
      });

      // Yield to the event loop / UI thread so the map can paint.
      await Future.delayed(Duration(milliseconds: batchDelayMs));
    }
  }

  // Zoom helper methods removed; zoom controls were removed from the UI.

  Future<void> _onMarkerTapped(Place place) async {
  final user = FirebaseAuth.instance.currentUser;
  bool isAdminUser = false;
  if (user != null) {
    try {
      final udoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final role = udoc.data()?['role'] as String?;
      if (role != null && role.toLowerCase() == 'admin') isAdminUser = true;
    } catch (_) {}
  }

  // Reusable helper to open Street View (embedded) for a LatLng
  Future<void> openStreetViewDialog(BuildContext ctx, LatLng? pos) async {
    // First, try to open the native StreetView (if platform integration exists).
    if (pos != null) {
      final opened = await NativeStreetView.open(lat: pos.latitude, lng: pos.longitude);
      if (opened) return;

      // Fallback: embedded WebView street view (web version)
      final lat = pos.latitude;
      final lng = pos.longitude;
      await showDialog<void>(
        context: ctx,
        builder: (innerCtx) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Street View'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(innerCtx).pop(),
                  ),
                ],
              ),
              SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.9,
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Builder(builder: (webCtx) {
                  final controller = WebViewController()
                    ..setJavaScriptMode(JavaScriptMode.unrestricted)
                    ..loadRequest(Uri.parse('https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=$lat,$lng'));
                  return WebViewWidget(controller: controller);
                }),
              ),
            ],
          ),
        ),
      );
    } else {
      await showDialog<void>(
        context: ctx,
        builder: (innerCtx) => AlertDialog(
          title: const Text('Sin Street View'),
          content: const Text('Google Street View no ha llegado aquí todavía. Puedes ver la ubicación en el mapa o aportar la información si lo deseas.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(innerCtx).pop(), child: const Text('Cerrar')),
          ],
        ),
      );
    }
  }
    List<Map<String, dynamic>> comments = [];
    double avgRating = 0;
    // Usar como ID del PDI: name_category (sin espacios)
    final pdiDocId = _sanitizeId('${place.name}_${place.category}');
    bool isGold = (place.specialCategories ?? []).contains('lista_gold');
    try {
      // First, try canonical reviews under pdis_v2/<pdiDocId>/reviews
      final reviewsSnap = await FirebaseFirestore.instance
          .collection('pdis_v2')
          .doc(pdiDocId)
          .collection('reviews')
          .where('status', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .get();

      final List<Map<String, dynamic>> loaded = [];
      final Set<String> seenIds = {};
      for (final doc in reviewsSnap.docs) {
        final d = Map<String, dynamic>.from(doc.data());
        d['_docId'] = doc.id;
        loaded.add(d);
        seenIds.add(doc.id);
      }

      // Also query mirrored/other reviews across the DB that include a pdiId
      // field (mirrored copies under users/*/reviews or legacy locations).
      try {
        // Build a small set of plausible pdiId variants to handle legacy
        // casing/normalization differences (some imports used different
        // capitalization when writing pdiId). We'll try an 'in' query
        // against this set so mirrored reviews are found even if the
        // stored pdiId differs only by case.
        final possibleIds = <String>{pdiDocId, pdiDocId.toLowerCase(), pdiDocId.toUpperCase()}.toList();

        // 1) Approved reviews under any reviews subcollection
        final mirrorSnap = await FirebaseFirestore.instance
            .collectionGroup('reviews')
            .where('pdiId', whereIn: possibleIds)
            .where('status', isEqualTo: 'approved')
            .get();
        for (final doc in mirrorSnap.docs) {
          if (seenIds.contains(doc.id)) continue;
          final d = Map<String, dynamic>.from(doc.data());
          d['_docId'] = doc.id;
          loaded.add(d);
          seenIds.add(doc.id);
        }

        // 2) Some codepaths/storage used the singular collection name 'review'
        // for mirrored docs. Try that collectionGroup as well for approved.
        try {
          final singularSnap = await FirebaseFirestore.instance
              .collectionGroup('review')
              .where('pdiId', whereIn: possibleIds)
              .where('status', isEqualTo: 'approved')
              .get();
          for (final doc in singularSnap.docs) {
            if (seenIds.contains(doc.id)) continue;
            final d = Map<String, dynamic>.from(doc.data());
            d['_docId'] = doc.id;
            loaded.add(d);
            seenIds.add(doc.id);
          }
        } catch (_) {
          // ignore singular collectionGroup failures
        }

        // 3) If the current user exists, include their personal review copy
        // even if its status is not 'approved' (so users see their own feedback).
        if (user != null) {
          try {
            final mySnap = await FirebaseFirestore.instance
                .collectionGroup('reviews')
                .where('pdiId', whereIn: possibleIds)
                .where('userId', isEqualTo: user.uid)
                .get();
            for (final doc in mySnap.docs) {
              if (seenIds.contains(doc.id)) continue;
              final d = Map<String, dynamic>.from(doc.data());
              d['_docId'] = doc.id;
              // annotate so the UI may show status
              d['_isMirrorOfUser'] = true;
              loaded.add(d);
              seenIds.add(doc.id);
            }
          } catch (_) {}

          try {
            final mySingular = await FirebaseFirestore.instance
                .collectionGroup('review')
                .where('pdiId', whereIn: possibleIds)
                .where('userId', isEqualTo: user.uid)
                .get();
            for (final doc in mySingular.docs) {
              if (seenIds.contains(doc.id)) continue;
              final d = Map<String, dynamic>.from(doc.data());
              d['_docId'] = doc.id;
              d['_isMirrorOfUser'] = true;
              loaded.add(d);
              seenIds.add(doc.id);
            }
          } catch (_) {}
        }
      } catch (e) {
        // non-fatal: continue with whatever we have but log for debugging
        developer.log('[HomeScreen] collectionGroup reviews pdiId lookup failed: $e', name: 'HomeScreen');
      }

      if (loaded.isNotEmpty) {
        comments = loaded;
        avgRating = 0;
        final ratings = loaded.map((c) => (c['rating'] ?? 0) as num).toList();
        if (ratings.isNotEmpty) {
          avgRating = ratings.reduce((a, b) => a + b) / ratings.length;
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
                            // Close the popup immediately to avoid using the
                            // dialog BuildContext after async operations.
                            Navigator.of(context).pop();
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
                            if (!mounted) return;
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
                      Wrap(
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6.0,
                        children: [
                          // Show average as "4,3" (comma) like Google Maps
                          Text(avgRating.toStringAsFixed(1).replaceAll('.', ','), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          // Render stars with half-star support
                          ...List.generate(5, (i) {
                            final diff = avgRating - i;
                            if (diff >= 0.75) {
                              return const Icon(Icons.star, color: Colors.amber, size: 20);
                            } else if (diff >= 0.25) {
                              return const Icon(Icons.star_half, color: Colors.amber, size: 20);
                            } else {
                              return const Icon(Icons.star_border, color: Colors.amber, size: 20);
                            }
                          }),
                          // Number of reviews
                          Text(' (${comments.length})', style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    const SizedBox(height: 10),
                    if (user != null) ...[
                      ElevatedButton.icon(
                        onPressed: () => _showReviewBottomSheet(context, place, user),
                        icon: const Icon(Icons.rate_review),
                        label: const Text('Valora este lugar'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Street View button: prominent with icon + text
                    ElevatedButton(
                      onPressed: () async {
                        // Try to extract coordinates from Place position
                        final lat = place.position.latitude;
                        final lng = place.position.longitude;
                        final opened = await NativeStreetView.open(lat: lat, lng: lng);
                        if (!opened) {
                          openStreetViewDialog(context, LatLng(lat, lng));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.streetview, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Street View', style: TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                  onPressed: () async {
                    // keep a reference to the dialog context so we can close it later
                    final parentDialogContext = context;

                    // Show bottom sheet with options
                    await showModalBottomSheet(
                      context: context,
                      builder: (ctx) {
                        return SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text('Cómo quieres obtener indicaciones?', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                ListTile(
                                  leading: const Icon(Icons.copy),
                                  title: const Text('Copiar coordenadas'),
                                  subtitle: const Text('Copia latitud,longitud al portapapeles'),
                                  onTap: () async {
                                    final lat = place.position.latitude;
                                    final lon = place.position.longitude;
                                    // Close UI first and show feedback, then perform background work.
                                    final messenger = ScaffoldMessenger.of(parentDialogContext);
                                    Navigator.of(ctx).pop(); // close bottom sheet
                                    Navigator.of(parentDialogContext).pop(); // close place dialog and return to map
                                    messenger.showSnackBar(const SnackBar(content: Text('Coordenadas copiadas al portapapeles')));
                                    // Do clipboard and history writes without touching BuildContext afterwards.
                                    try {
                                      await Clipboard.setData(ClipboardData(text: '$lat,$lon'));
                                    } catch (_) {}
                                    if (user != null) {
                                      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history').add({
                                        'action': 'copy_coordinates',
                                        'placeName': place.name,
                                        'category': place.category,
                                        'coords': {'lat': lat, 'lon': lon},
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                    }
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.map),
                                  title: const Text('Abrir en Google Maps'),
                                  onTap: () async {
                                    final lat = place.position.latitude;
                                    final lon = place.position.longitude;
                                    final webUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon';
                                    final webUri = Uri.parse(webUrl);
                                    // Try the native Google Maps URI first (Android/iOS)
                                    final nativeNav = Uri.tryParse('google.navigation:q=$lat,$lon');
                                    final geoUri = Uri.tryParse('geo:$lat,$lon?q=${Uri.encodeComponent('$lat,$lon (${place.name})')}');
                                    // Close UI and then perform navigation/history actions without using BuildContext after awaits.
                                    Navigator.of(ctx).pop();
                                    Navigator.of(parentDialogContext).pop();
                                    // record history (lightweight log) — fire-and-forget
                                    if (user != null) {
                                      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history').add({
                                        'action': 'open_google_maps',
                                        'placeName': place.name,
                                        'category': place.category,
                                        'coords': {'lat': lat, 'lon': lon},
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                      // Also add a history_places entry so it appears in the user's "Historial"
                                      final pdiId = _sanitizeId('${place.name}_${place.category}');
                                      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history_places').add({
                                        'name': place.name,
                                        'category': place.category,
                                        'latitude': lat,
                                        'longitude': lon,
                                        'source': 'navigation',
                                        'sourceId': null,
                                        'poiId': pdiId,
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                    }
                                    bool launched = false;
                                    final messenger = ScaffoldMessenger.of(parentDialogContext);
                                    try {
                                      if (nativeNav != null && await canLaunchUrl(nativeNav)) {
                                        launched = await launchUrl(nativeNav, mode: LaunchMode.externalApplication);
                                      }
                                      if (!launched && geoUri != null && await canLaunchUrl(geoUri)) {
                                        launched = await launchUrl(geoUri, mode: LaunchMode.externalApplication);
                                      }
                                      if (!launched && await canLaunchUrl(webUri)) {
                                        launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
                                      }
                                      if (!launched) {
                                        messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir Google Maps')));
                                      }
                                    } catch (e) {
                                      messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir Google Maps')));
                                    }
                                  },
                                ),
                                ListTile(
                                  leading: const Icon(Icons.open_in_browser),
                                  title: const Text('Abrir en navegador'),
                                  subtitle: const Text('Se abrirá en el navegador predeterminado'),
                                  onTap: () async {
                                    final lat = place.position.latitude;
                                    final lon = place.position.longitude;
                                    final url = 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
                                    final uri = Uri.parse(url);
                                    Navigator.of(ctx).pop();
                                    Navigator.of(parentDialogContext).pop();
                                    if (user != null) {
                                      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history').add({
                                        'action': 'open_browser',
                                        'placeName': place.name,
                                        'category': place.category,
                                        'coords': {'lat': lat, 'lon': lon},
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                      // add to history_places
                                      final pdiId = _sanitizeId('${place.name}_${place.category}');
                                      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history_places').add({
                                        'name': place.name,
                                        'category': place.category,
                                        'latitude': lat,
                                        'longitude': lon,
                                        'source': 'navigation',
                                        'sourceId': null,
                                        'poiId': pdiId,
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                    }
                                    final messenger = ScaffoldMessenger.of(parentDialogContext);
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                                    } else {
                                      messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir el navegador')));
                                    }
                                  },
                                ),
                                const Divider(),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Text('Abrir con navegador específico (si está instalado):', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                                ),
                                // Detect common browsers and show actions for those that are available
                                FutureBuilder<List<Map<String, String>>>(
                                  future: _detectBrowsers(place),
                                  builder: (context, snap) {
                                    if (!snap.hasData) return const SizedBox.shrink();
                                    final browsers = snap.data!;
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: browsers.map((b) => ListTile(
                                        leading: const Icon(Icons.language),
                                        title: Text('Abrir en ${b['name'] ?? 'Navegador'}'),
                                        onTap: () async {
                                          final lat = place.position.latitude;
                                          final lon = place.position.longitude;
                                          final targetUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
                                          final uri = Uri.parse(targetUrl);
                                          Navigator.of(ctx).pop();
                                          Navigator.of(parentDialogContext).pop();
                                          if (user != null) {
                                            FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history').add({
                                              'action': 'open_browser_specific',
                                              'browser': b['name'],
                                              'placeName': place.name,
                                              'coords': {'lat': lat, 'lon': lon},
                                              'timestamp': FieldValue.serverTimestamp(),
                                            });
                                            // add to history_places
                                            final pdiId = _sanitizeId('${place.name}_${place.category}');
                                            FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history_places').add({
                                              'name': place.name,
                                              'category': place.category,
                                              'latitude': lat,
                                              'longitude': lon,
                                              'source': 'navigation',
                                              'sourceId': null,
                                              'poiId': pdiId,
                                              'timestamp': FieldValue.serverTimestamp(),
                                            });
                                          }
                                          // Try to open using the browser-specific scheme if provided
                                          final scheme = b['scheme'];
                                          if (scheme != null && scheme.isNotEmpty) {
                                            // some schemes expect the URL appended
                                            final specialized = Uri.parse(scheme.replaceAll('{URL}', Uri.encodeFull(targetUrl)));
                                            if (await canLaunchUrl(specialized)) {
                                              await launchUrl(specialized, mode: LaunchMode.externalApplication);
                                              return;
                                            }
                                          }
                                          // fallback to generic
                                          final messenger = ScaffoldMessenger.of(parentDialogContext);
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          } else {
                                            messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir el navegador seleccionado')));
                                          }
                                        },
                                      )).toList(),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
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
                                    // Save a user-local copy of the report so it appears in the user's profile
                                    if (user?.uid != null) {
                                      await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('reports').add({
                                        'name': place.name,
                                        'category': place.category,
                                        'motivo': motivo,
                                        'comentario': comentario,
                                        'timestamp': FieldValue.serverTimestamp(),
                                      });
                                    }

                                    // Try writes and track if any succeeded. If none succeed, show an error instead of success.
                                    // NOTE: we intentionally do NOT create a `contact_messages`
                                    // document for incidencias because these reports are
                                    // handled in the dedicated `incidencias` collection
                                    // and should not appear in the admin inbox.
                                    bool wroteAny = false;

                                    if (user?.uid != null) {
                                      try {
                                        final incRef = await FirebaseFirestore.instance.collection('incidencias').add({
                                          'name': place.name,
                                          'category': place.category,
                                          'motivo': motivo,
                                          'comentario': comentario,
                                          'pdiId': _sanitizeId('${place.name}_${place.category}'),
                                          'fromUid': user!.uid,
                                          'fromName': user.displayName ?? '(Sin remitente)',
                                          'fromEmail': user.email,
                                          'timestamp': FieldValue.serverTimestamp(),
                                          'read': false,
                                        });
                                          if (incRef.id.isNotEmpty) wroteAny = true;
                                      } catch (e) {
                                        developer.log('Failed to write incidencia for admin: $e', name: 'HomeScreen');
                                      }

                                      // NOTE: we do NOT create a user_messages copy for incidencias
                                      // because incidencias are handled in a dedicated admin
                                      // mailbox (`incidencias` collection) and should not
                                      // appear in the admin 'Bandeja de entrada'.
                                    }

                                    // If none of the writes succeeded, show an error dialog instead of success.
                                    if (!wroteAny) {
                                      if (mounted) {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (errCtx) {
                                            return AlertDialog(
                                              title: const Text('Error'),
                                              content: const Text('No se pudo enviar el reporte. Comprueba tu conexión y vuelve a intentarlo.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.of(errCtx).pop(), child: const Text('Cerrar')),
                                              ],
                                            );
                                          },
                                        );
                                      }
                                      return;
                                    }

                                    // Show confirmation dialog (modal) with an Accept button.
                                    // When the user accepts, close the confirmation and the underlying dialogs.
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (confirmCtx) {
                                        return AlertDialog(
                                          title: const Text('¡Reporte enviado!'),
                                          content: const Text('Gracias por tu reporte. Lo revisaremos lo antes posible.'),
                                          actions: [
                                            ElevatedButton(
                                              onPressed: () {
                                                // Close confirmation
                                                Navigator.of(confirmCtx).pop();
                                                // Close the report dialog and the place dialog
                                                Navigator.of(context).pop();
                                                Navigator.of(context).pop();
                                              },
                                              child: const Text('Aceptar'),
                                            ),
                                          ],
                                        );
                                      },
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
                if (isAdminUser) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _showEditPlaceDialog(context, place);
                    },
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  // Show an edit dialog for admins to change name/category/description
  void _showEditPlaceDialog(BuildContext parentContext, Place place) {
    final nameController = TextEditingController(text: place.name);
    final descController = TextEditingController(text: place.description ?? '');
    String selectedCategory = place.category;
    final categoriesSet = <String>{};
    categoriesSet.addAll(_categoryToIcon.keys);
    categoriesSet.addAll(_categoryFallbacks.keys);
    categoriesSet.addAll(_assetCategories);
    final categories = categoriesSet.toList()..sort();

    bool isSaving = false;
    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('Editar PDI (admin)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 8),
                    // Make the dropdown expand to the dialog width and ensure
                    // long category names don't overflow the layout.
                    SizedBox(
                      width: double.infinity,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        isDense: true,
                        initialValue: selectedCategory.isEmpty ? null : selectedCategory,
                        decoration: const InputDecoration(labelText: 'Categoría'),
                        items: categories.map((c) => DropdownMenuItem(
                          value: c,
                          child: Text(
                            c.replaceAll('_', ' '),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )).toList(),
                        onChanged: (v) => setState(() { selectedCategory = v ?? ''; }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(labelText: 'Descripción'),
                      minLines: 2,
                      maxLines: 5,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: isSaving ? null : () async {
                    developer.log('[HomeScreen] Edit PDI Save pressed for ${place.name}', name: 'HomeScreen');
                    final newName = nameController.text.trim();
                    final newCategory = selectedCategory.trim();
                    final newDesc = descController.text.trim();
                    if (newName.isEmpty || newCategory.isEmpty) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(const SnackBar(content: Text('Nombre y categoría son obligatorios')));
                      return;
                    }
                    setState(() { isSaving = true; });
                    // compute old doc id
                    final oldId = _sanitizeId('${place.name}_${place.category}');
                    try {
                      // Prefer server-side callable function to perform admin updates.
                      final functions = fc.FirebaseFunctions.instance;
                      final callable = functions.httpsCallable('adminUpdatePoi');
                      final payload = {
                        'oldId': oldId,
                        'newName': newName,
                        'newCategory': newCategory,
                        'description': newDesc,
                        'position': {'lat': place.position.latitude, 'lng': place.position.longitude},
                        'iconPath': place.iconPath,
                        'specialCategories': place.specialCategories,
                        'deleteOld': true,
                      };
                      developer.log('[HomeScreen] Calling adminUpdatePoi with payload: ${json.encode(payload)}', name: 'HomeScreen');
                      final result = await callable.call(payload);
                      developer.log('[HomeScreen] adminUpdatePoi result: ${result.data}', name: 'HomeScreen');
                      if (mounted) {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDI actualizado')));
                      }
                      final updatedPlace = Place(name: newName, category: newCategory, position: place.position, iconPath: place.iconPath, description: newDesc, specialCategories: place.specialCategories);
                      await Future.delayed(const Duration(milliseconds: 200));
                      _onMarkerTapped(updatedPlace);
                    } on fc.FirebaseFunctionsException catch (fe) {
                      developer.log('[HomeScreen] adminUpdatePoi failed: $fe', name: 'HomeScreen');
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${fe.message}')));
                    } catch (e) {
                      developer.log('[HomeScreen] Failed to call adminUpdatePoi: $e', name: 'HomeScreen');
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error guardando PDI')));
                    } finally {
                      setState(() { isSaving = false; });
                    }
                  },
                  child: isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showReviewBottomSheet(BuildContext parentContext, Place place, User user) async {
    await showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      builder: (ctx) {
        int rating = 0;
        String comment = '';
        final pdiDocId = _sanitizeId('${place.name}_${place.category}');
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx2, setState) {
              return Container(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Valora ${place.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: List.generate(5, (i) => GestureDetector(
                        onTap: () => setState(() => rating = i + 1),
                        child: Icon(i < rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 36),
                      )),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Comentario', border: OutlineInputBorder()),
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (v) => comment = v,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: rating > 0
                          ? () async {
                              try {
                                final ref = await FirebaseFirestore.instance.collection('pdis_v2').doc(pdiDocId).collection('reviews').add({
                                  'comment': comment,
                                  'rating': rating,
                                  'userId': user.uid,
                                  'status': 'pending',
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                                // create mirrored per-user copy so it appears in profile
                                await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('reviews').doc(ref.id).set({
                                  'comment': comment,
                                  'rating': rating,
                                  'userId': user.uid,
                                  'status': 'pending',
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'pdiId': pdiDocId,
                                  'pdiName': place.name,
                                  'pdiCategory': place.category,
                                  'isMirror': true,
                                });
                                // Also add a place-history entry so the place appears in the user's Historial
                                try {
                                  await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history_places').add({
                                    'name': place.name,
                                    'category': place.category,
                                    'latitude': place.position.latitude,
                                    'longitude': place.position.longitude,
                                    'source': 'review',
                                    'sourceId': ref.id,
                                    'poiId': pdiDocId,
                                    'timestamp': FieldValue.serverTimestamp(),
                                  });
                                } catch (e) {
                                  // non-fatal: if history write fails, still proceed
                                  developer.log('Failed to write history_places for user ${user.uid}', name: 'HomeScreen', error: e);
                                }
                              } catch (e, s) {
                                developer.log('Failed to add review for $pdiDocId', name: 'HomeScreen', error: e, stackTrace: s);
                                if (mounted) {
                                  ScaffoldMessenger.of(parentContext).showSnackBar(
                                    const SnackBar(content: Text('No se pudo enviar la valoración. Intenta de nuevo.'), backgroundColor: Colors.red),
                                  );
                                }
                                return;
                              }
                              if (mounted) {
                                Navigator.of(ctx).pop(); // close bottom sheet
                                Navigator.of(parentContext).pop(); // close place dialog
                                _onMarkerTapped(place); // refresh
                                ScaffoldMessenger.of(parentContext).showSnackBar(const SnackBar(content: Text('¡Comentario enviado! Será visible tras aprobación.'), backgroundColor: Colors.green));
                              }
                            }
                          : null,
                      child: const Text('Enviar valoración'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
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

  // Detect common browsers installed on the device. Returns a list of maps
  // with 'name' and optional 'scheme' where {URL} will be replaced by the encoded URL.
  Future<List<Map<String, String>>> _detectBrowsers(Place place) async {
    final List<Map<String, String>> found = [];
    // target test URL
    final testUrl = Uri.parse('https://www.google.com');

    // Candidates with schemes that accept a URL placeholder
    final candidates = [
      {'name': 'Chrome', 'scheme': 'googlechrome://navigate?url={URL}'},
      {'name': 'Firefox', 'scheme': 'firefox://open-url?url={URL}'},
      {'name': 'Edge', 'scheme': 'microsoft-edge:{URL}'},
      {'name': 'Samsung Internet', 'scheme': 'samsungbrowser://{URL}'},
    ];

    for (final c in candidates) {
      final scheme = c['scheme']!.replaceAll('{URL}', Uri.encodeFull(testUrl.toString()));
      try {
        final uri = Uri.parse(scheme);
        if (await canLaunchUrl(uri)) {
          found.add({'name': c['name']!, 'scheme': c['scheme']!});
        }
      } catch (_) {}
    }
    return found;
  }

  // ...existing code...

  Widget _buildDrawerMenuWithBadge() {
    // Use the scaffold key to open the drawer reliably from any context.
    return IconButton(
      icon: const Icon(Icons.menu),
      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: _buildDrawerMenuWithBadge(),
        title: Row(
          children: [
            // White icon with a darker outline behind so it remains visible over light backgrounds.
            Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.directions_bus,
                  size: 28,
                  color: Color.fromRGBO(0,0,0,0.85),
                ),
                Icon(
                  Icons.directions_bus,
                  size: 24,
                  color: Colors.white,
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Stroke (outline)
                  Text(
                    'BusPoints',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      textStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 20, fontWeight: FontWeight.w600)
                          ?? const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w600),
                    ).copyWith(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3
                        ..color = Color.fromRGBO(0,0,0,0.85),
                    ),
                  ),
                  // Fill
                  Text(
                    'BusPoints',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      textStyle: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: 20, fontWeight: FontWeight.w600)
                          ?? const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w600),
                    ).copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
            IconButton(
              icon: const Icon(Icons.legend_toggle),
              onPressed: () => _showLegendDialog(context),
              tooltip: 'Leyenda de iconos',
            ),
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
                    mapType: _mapType,
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
                      onCameraMove: (CameraPosition pos) {
                        _cameraMoved = true;
                      },
                      onCameraIdle: () {
                        if (_cameraMoved) {
                          _cameraMoved = false;
                          if (_autoSyncAfterCategorySelected && _activeCategoryKey != null) {
                            developer.log('[HomeScreen] camera moved, auto-syncing category=$_activeCategoryKey', name: 'HomeScreen');
                            _loadPlacesByCategory(_activeCategoryKey!);
                          } else {
                            // Auto-load disabled: POIs are only loaded on explicit
                            // user actions (selecting a category or tapping 'Mostrar todos').
                            developer.log('[HomeScreen] camera moved but auto-load is disabled', name: 'HomeScreen');
                          }
                        }
                      },
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: _buildSearchCard(),
                ),
                // Map type toggle placed at top-right corner with reasonable margins
                Positioned(
                  top: kToolbarHeight + 12.0,
                  right: 12,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      // Use the app primary color so the control matches branding/emoticon
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withAlpha((0.9 * 255).round()), width: 1),
                      boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withAlpha((0.25 * 255).round()), blurRadius: 4, offset: Offset(0,2))],
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 22,
                      tooltip: 'Cambiar tipo de mapa',
                      icon: Icon(
                        _mapType == MapType.normal
                            ? Icons.map
                            : _mapType == MapType.satellite
                                ? Icons.satellite
                                : _mapType == MapType.hybrid
                                    ? Icons.layers
                                    : Icons.terrain,
                        color: Colors.white,
                      ),
                      onPressed: _cycleMapType,
                    ),
                  ),
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
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'searchFab',
            onPressed: _toggleCategoryList,
            backgroundColor: Colors.blueAccent,
            child: const Icon(
              Icons.search,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _showLegendDialog(BuildContext context) {
    final legend = <Map<String, String>>[
      {'label': 'Parada bus', 'file': 'icon-1.png'},
      {'label': 'Parking', 'file': 'icon-2.png'},
      {'label': 'Parking de pago', 'file': 'icon-3.png'},
      {'label': 'Carga y descarga', 'file': 'icon-6.png'},
      {'label': 'Zona de espera', 'file': 'icon-8.png'},
      {'label': 'Gasolinera', 'file': 'icon-78.png'},
      {'label': 'Hotel', 'file': 'icon-11.png'},
      {'label': 'Restaurantes', 'file': 'icon-12.png'},
      {'label': 'Otros', 'file': 'icon-82.png'},
    ];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leyenda de iconos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: legend.map((entry) {
              final assetPath = 'assets/pdis_icons/${entry['file']}';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Image.asset(
                        assetPath,
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                        errorBuilder: (c, e, s) => Image.asset('assets/icons/${entry['file']}', width: 36, height: 36, fit: BoxFit.contain, errorBuilder: (c2, e2, s2) => const Icon(Icons.place)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(entry['label'] ?? '')),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
        ],
      ),
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
            // Include any additional asset-driven categories that are not
            // in the ordered/special lists so the user can select them.
            ...(_assetCategories.where((c) => !_orderedCategories.contains(c) && !_specialCategories.contains(c)).map(buildCategoryTile)),
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

// Debug panel widget used only in debug builds. Allows quick checks of
// Auth state and a test read against `Pdis_full` so you can diagnose
// permission issues directly on device without the console.
class DebugPdisPanel extends StatefulWidget {
  final Future<void> Function()? onForceReload;
  const DebugPdisPanel({super.key, this.onForceReload});

  @override
  State<DebugPdisPanel> createState() => _DebugPdisPanelState();
}

class _DebugPdisPanelState extends State<DebugPdisPanel> {
  String _output = '';
  bool _loading = false;

  Future<void> _append(String s) async {
    setState(() {
      _output = '$_output\n$s';
    });
  }

  Future<void> _checkPdis() async {
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _append('[Auth] uid=${user?.uid ?? 'null'} isAnonymous=${user?.isAnonymous ?? false}');
      final snap = await FirebaseFirestore.instance.collection('Pdis_full').limit(20).get();
      await _append('[Pdis_full] docs=${snap.docs.length}');
    } catch (e) {
      await _append('[ERROR] ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _signInAnon() async {
    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.signInAnonymously();
      await _append('[Anon sign-in] uid=${cred.user?.uid}');
    } catch (e) {
      await _append('[Anon sign-in ERROR] ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  // Try to obtain an App Check token with and without forcing refresh.
  // Appends rich logs (including caught stack traces) to the debug output
  // so we can diagnose why getToken() doesn't return a visible token.
  Future<void> _getAppCheckToken() async {
    setState(() => _loading = true);
    try {
      await _append('[AppCheck] Attempting getToken(no refresh)');
      dynamic tokenResult = await FirebaseAppCheck.instance.getToken(false);
      String tokenStr;
      if (tokenResult == null) {
        tokenStr = 'null';
      } else if (tokenResult is String) {
        tokenStr = tokenResult;
      } else {
        try {
          tokenStr = (tokenResult as dynamic).token?.toString() ?? tokenResult.toString();
        } catch (_) {
          tokenStr = tokenResult.toString();
        }
      }
      await _append('[AppCheck token (no refresh)] $tokenStr');

      if (tokenStr == 'null' || tokenStr.isEmpty) {
        await _append('[AppCheck] No token returned, trying getToken(forceRefresh=true)');
        try {
          tokenResult = await FirebaseAppCheck.instance.getToken(true);
          if (tokenResult == null) {
            tokenStr = 'null';
          } else if (tokenResult is String) {
            tokenStr = tokenResult;
          } else {
            try {
              tokenStr = (tokenResult as dynamic).token?.toString() ?? tokenResult.toString();
            } catch (_) {
              tokenStr = tokenResult.toString();
            }
          }
          await _append('[AppCheck token (forced)] $tokenStr');
        } catch (e, s) {
          await _append('[AppCheck token ERROR after forced refresh] ${e.toString()}');
          developer.log('[AppCheck] forced getToken error', name: 'DebugPdisPanel', error: e, stackTrace: s);
        }
      }
      // Show native dialog with the token (or 'null') and copy token to clipboard
      try {
        await Clipboard.setData(ClipboardData(text: tokenStr));
      } catch (_) {
        // ignore clipboard errors
      }
      if (mounted) {
        showDialog<void>(context: context, builder: (ctx) {
          return AlertDialog(
            title: const Text('AppCheck token'),
            content: SingleChildScrollView(child: Text(tokenStr)),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            ],
          );
        });
      }
    } catch (e, s) {
      await _append('[AppCheck token ERROR] ${e.toString()}');
      developer.log('[AppCheck] getToken error', name: 'DebugPdisPanel', error: e, stackTrace: s);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Debug: Pdis / Auth', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _loading ? null : _checkPdis,
              icon: const Icon(Icons.download),
              label: const Text('Check Pdis_full'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loading ? null : _getAppCheckToken,
              icon: const Icon(Icons.vpn_key),
              label: const Text('Get AppCheck token'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loading ? null : _signInAnon,
              icon: const Icon(Icons.person_off),
              label: const Text('Sign in anonymously'),
            ),
          ]),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: widget.onForceReload == null ? null : () async {
              await widget.onForceReload!();
              await _append('[Force reload executed]');
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Force reload POIs'),
          ),
          const SizedBox(height: 12),
          const Text('Output:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 240),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(_output.isEmpty ? 'No output yet' : _output),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// (Opcionalmente, si hay código fuera de la clase, puede ir aquí)
