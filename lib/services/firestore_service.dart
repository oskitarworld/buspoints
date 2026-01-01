import 'dart:async';
import 'dart:math' as math;
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_web_compat.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/models/place.dart';

// Normalize Firestore document maps into plain maps with primitive types
// suitable for sending to an isolate. The function extracts a canonical
// latitude/longitude pair (if present in various formats) and returns a
// lightweight map with name, category, description, latitude and longitude.
List<Map<String, dynamic>> _normalizeDocsForPlaces(dynamic rawDocs) {
  final docs = rawDocs as List;
  final List<Map<String, dynamic>> out = [];

  for (final raw in docs) {
    final data = Map<String, dynamic>.from(raw as Map);

    // Make a shallow serializable copy; nested maps are kept as-is.
    final Map<String, dynamic> s = {};
    data.forEach((k, v) {
      if (v is Map) {
        s[k] = Map<String, dynamic>.from(v);
      } else {
        s[k] = v;
      }
    });

    double? lat;
    double? lng;

    // latitude/longitude fields
    if (s.containsKey('latitude') && s.containsKey('longitude')) {
      final rawLat = s['latitude'];
      final rawLng = s['longitude'];
      lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
      lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
    }

    // position map { lat, lng }
    if ((lat == null || lng == null) && s['position'] is Map) {
      final pos = Map<String, dynamic>.from(s['position'] as Map);
      final rawLat = pos['lat'];
      final rawLng = pos['lng'];
      lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
      lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
    }

    // geopoint stored as a map { latitude, longitude } or {lat,lng}
    if ((lat == null || lng == null) && s['geopoint'] is Map) {
      final gp = Map<String, dynamic>.from(s['geopoint'] as Map);
      final rawLat = gp['latitude'] ?? gp['lat'];
      final rawLng = gp['longitude'] ?? gp['lng'];
      lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
      lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
    }

    // geoflutterfire format: geo: { geopoint: {lat,lng}, geohash: string }
    if ((lat == null || lng == null) && s['geo'] is Map) {
      final geo = Map<String, dynamic>.from(s['geo'] as Map);
      final maybeGp = geo['geopoint'];
      if (maybeGp is Map) {
        final rawLat = maybeGp['latitude'] ?? maybeGp['lat'];
        final rawLng = maybeGp['longitude'] ?? maybeGp['lng'];
        lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
        lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
      }
    }

    // Support migrated/legacy shapes: some docs include a `_coords` map
    // or a `location` map with underscored keys, or GeoJSON `geometry`.
    if ((lat == null || lng == null) && s['_coords'] is Map) {
      final c = Map<String, dynamic>.from(s['_coords'] as Map);
      final rawLat = c['latitude'] ?? c['lat'];
      final rawLng = c['longitude'] ?? c['lng'];
      lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
      lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
    }

    if ((lat == null || lng == null) && s['location'] is Map) {
      final loc = Map<String, dynamic>.from(s['location'] as Map);
      final rawLat = loc['latitude'] ?? loc['_latitude'] ?? loc['lat'] ?? loc['_lat'];
      final rawLng = loc['longitude'] ?? loc['_longitude'] ?? loc['lng'] ?? loc['_lng'];
      lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
      lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
    }

    // GeoJSON: geometry: { type: 'Point', coordinates: [lng, lat] }
    if ((lat == null || lng == null) && s['geometry'] is Map) {
      try {
        final geom = Map<String, dynamic>.from(s['geometry'] as Map);
        final coords = geom['coordinates'];
        if (coords is List && coords.length >= 2) {
          final rawLng = coords[0];
          final rawLat = coords[1];
          lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
          lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
        }
      } catch (_) {
        // ignore malformed geometry
      }
    }

    if (lat == null || lng == null) continue;

    // Normalize category: prefer a clean, predictable key used by the UI.
    String rawCategory = '';
    if (s.containsKey('category') && s['category'] != null) {
      rawCategory = s['category'].toString();
    }
    String normalizedCategory = rawCategory.trim().toLowerCase();
    // Normalize spaces/hyphens to underscores
    normalizedCategory = normalizedCategory.replaceAll(RegExp(r"[\s-]+"), '_');
    // Map icon-like or empty categories to 'otros'
    if (normalizedCategory.isEmpty || normalizedCategory.startsWith('icon-') ||
        RegExp(r'^icon-\d+-[0-9a-fA-F]{3,6}$').hasMatch(normalizedCategory)) {
      normalizedCategory = 'otros';
    }

    out.add({
      'name': s['name'],
      'category': normalizedCategory,
      'description': s['description'],
      'latitude': lat,
      'longitude': lng,
      // Preserve any icon path/url if present so the UI can use custom icons.
  'iconPath': s['iconPath'] ?? s['iconUrl'] ?? s['icon'],
    });
  }

  return out;
}

// Generate a URL/ID-safe slug from a string: lowercase, replace non-alnum with
// underscore, collapse underscores, trim edges.
String _slugify(String input) {
  var s = input.toLowerCase();
  s = s.replaceAll(RegExp(r"[^a-z0-9_\-]"), '_');
  s = s.replaceAll(RegExp(r'_+'), '_');
  s = s.trim();
  if (s.startsWith('_')) s = s.substring(1);
  if (s.endsWith('_')) s = s.substring(0, s.length - 1);
  return s;
}

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _usersCollectionName = 'users';
  static const String _poisCollectionName = 'pois';
  static const String _userPoisCollectionName = 'user_pois';
  // New normalized collection created by migration scripts. App will read
  // from `pdis_v2` if present to show normalized slugs/categories.
  static const String _pdisV2CollectionName = 'pdis_v2';

  Future<void> ensureAdminUser(User user) async {
    final userDocRef =
        _firestore.collection(_usersCollectionName).doc(user.uid);
    final userDoc = await userDocRef.get();

    if (!userDoc.exists) {
      await userDocRef.set({
        'email': user.email,
        'username': 'admin',
        'isAdmin': true, // Default to true for the first admin
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> createUserDocument(User user, {required String username}) async {
    final userDocRef =
        _firestore.collection(_usersCollectionName).doc(user.uid);
    final userDoc = await userDocRef.get();

    if (!userDoc.exists) {
      await userDocRef.set({
        'email': user.email,
        'username': username,
        'isAdmin': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<bool> isAdmin(String uid) async {
    try {
      final userDoc =
          await _firestore.collection(_usersCollectionName).doc(uid).get();
      if (userDoc.exists && userDoc.data()!['isAdmin'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      developer.log('Error checking admin status: $e',
          name: 'FirestoreService');
      return false;
    }
  }

  Future<void> updateUserStatus(String uid, String status) async {
    try {
      await _firestore
          .collection(_usersCollectionName)
          .doc(uid)
          .update({'status': status});
      developer.log('User status updated successfully',
          name: 'FirestoreService');
    } catch (e) {
      developer.log('Error updating user status: $e', name: 'FirestoreService');
      // Re-throw the exception to be handled by the UI layer
      rethrow;
    }
  }

  static const String _collectionName = 'locations';

  Stream<QuerySnapshot> getBusLocationStream() {
    developer.log(
        '[map.firestore] FORENSICS: Subscribing to Firestore collection: $_collectionName',
        name: 'map.firestore');
    return resilientStream(
      _firestore.collection(_collectionName).snapshots(),
      name: 'get_bus_location_stream',
    );
  }

  Future<void> addPointOfInterest(
      String name, String description, GeoPoint location) {
    final slug = _slugify(name);
    return _firestore.collection(_collectionName).add({
      'name': name,
      'description': description,
      'geopoint': location,
      'slug': slug,
    }).catchError((e) {
      developer.log('Error adding point of interest: $e', name: 'FirestoreService');
      // Re-throw the exception to be handled by the UI layer
      throw e;
    });
  }

  // =============================
  // Points of Interest (PDIs)
  // =============================

  /// Fetch approved POIs visible on the main map from 'pois' collection.
  /// To avoid OOM with very large collections, we cap the number of docs.
  /// Returns an empty list if no documents or on error.
  /// Fetch approved POIs visible on the main map.
  /// This will read the canonical `pois` collection and also include
  /// user-submitted POIs stored in `user_pois` that have been approved.
  /// To avoid OOM, we cap the final returned list to [limit].
  Future<List<Place>> getApprovedPois({int limit = 300, bool includeUserPois = true}) async {
    try {
      developer.log('[FirestoreService] getApprovedPois(): reading pois and user_pois (limit: $limit, includeUserPois: $includeUserPois)',
          name: 'FirestoreService');
      // Try pdis_v2 first (current canonical collection). If it has documents,
      // prefer it and skip reading Pdis_full/pois fallback.
      List<Place> pois = [];
      bool usedPdisV2 = false;
      try {
        final pdisV2Snapshot = await _firestore.collection(_pdisV2CollectionName).limit(limit).get();
        developer.log('[FirestoreService] getApprovedPois(): pdis_v2 docs: ${pdisV2Snapshot.docs.length}', name: 'FirestoreService');
        if (pdisV2Snapshot.docs.isNotEmpty) {
          final pdisRaw = pdisV2Snapshot.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            final Map<String, dynamic> serial = {};
            data.forEach((k, v) {
              if (v is GeoPoint) {
                serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
              } else {
                serial[k] = v;
              }
            });
            return serial;
          }).toList();
          final normalizedPdisV2 = await compute(_normalizeDocsForPlaces, pdisRaw);
          pois = normalizedPdisV2
            .map((data) => Place(
              name: data['name'] ?? '',
              category: data['category'] ?? 'otros',
              position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
              description: data['description'],
              iconPath: data['iconPath'] as String?,
            ))
            .whereType<Place>()
            .toList();
          usedPdisV2 = true;
        }
      } catch (e, s) {
        developer.log('[FirestoreService] getApprovedPois(): error reading pdis_v2 (continuing): $e', name: 'FirestoreService', error: e, stackTrace: s);
      }

      // 1) Read canonical PDIs from `Pdis_full` (preferred canonical source)
      if (!usedPdisV2) {
        try {
          final pdisFullSnapshot = await _firestore.collection('Pdis_full').limit(limit).get();
          developer.log('[FirestoreService] getApprovedPois(): Pdis_full docs: ${pdisFullSnapshot.docs.length}', name: 'FirestoreService');
          final pdisRaw = pdisFullSnapshot.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            final Map<String, dynamic> serial = {};
            data.forEach((k, v) {
              if (v is GeoPoint) {
                serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
              } else {
                serial[k] = v;
              }
            });
            return serial;
          }).toList();
          final normalizedPdisFull = await compute(_normalizeDocsForPlaces, pdisRaw);
          pois = normalizedPdisFull
            .map((data) => Place(
              name: data['name'] ?? '',
              category: data['category'] ?? 'otros',
              position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
              description: data['description'],
              iconPath: data['iconPath'] as String?,
            ))
            .whereType<Place>()
            .toList();
        } catch (e, s) {
          developer.log('[FirestoreService] getApprovedPois(): error reading Pdis_full (falling back): $e', name: 'FirestoreService', error: e, stackTrace: s);
          // If Pdis_full is not available, fall back to the legacy `pois` collection
          final poisSnapshot = await _firestore.collection(_poisCollectionName).limit(limit).get();
          developer.log('[FirestoreService] getApprovedPois(): pois docs (fallback): ${poisSnapshot.docs.length}', name: 'FirestoreService');
          final poisRaw = poisSnapshot.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            final Map<String, dynamic> serial = {};
            data.forEach((k, v) {
              if (v is GeoPoint) {
                serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
              } else {
                serial[k] = v;
              }
            });
            return serial;
          }).toList();
          final normalizedPois = await compute(_normalizeDocsForPlaces, poisRaw);
          pois = normalizedPois
            .map((data) => Place(
              name: data['name'] ?? '',
              category: data['category'] ?? 'otros',
              position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
              description: data['description'],
              iconPath: data['iconPath'] as String?,
            ))
            .whereType<Place>()
            .toList();
        }
      }

      // Additionally, always attempt to read the legacy `pois` collection
      // because some user-submitted POIs may live there even when pdis_v2
      // or Pdis_full are present. Read a limited set and merge them; they
      // will be deduplicated below.
      try {
        final extraPoisSnap = await _firestore.collection(_poisCollectionName).limit(limit).get();
        developer.log('[FirestoreService] getApprovedPois(): extra pois docs: ${extraPoisSnap.docs.length}', name: 'FirestoreService');
        final extraRaw = extraPoisSnap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          final Map<String, dynamic> serial = {};
          data.forEach((k, v) {
            if (v is GeoPoint) {
              serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
            } else {
              serial[k] = v;
            }
          });
          return serial;
        }).toList();
        final normalizedExtra = await compute(_normalizeDocsForPlaces, extraRaw);
        final extraPlaces = normalizedExtra
          .map((data) => Place(
            name: data['name'] ?? '',
            category: data['category'] ?? 'otros',
            position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
            description: data['description'],
            iconPath: data['iconPath'] as String?,
          ))
          .whereType<Place>()
          .toList();
        pois.addAll(extraPlaces);
      } catch (e, s) {
        developer.log('[FirestoreService] getApprovedPois(): error reading additional pois: $e', name: 'FirestoreService', error: e, stackTrace: s);
      }

    // 2) Optionally read approved user-submitted POIs
      List<Place> userPois = [];
      if (includeUserPois) {
        try {
      final userSnapshot = await _firestore
        .collection(_userPoisCollectionName)
        .where('status', isEqualTo: 'approved')
        // We limit to a reasonable number to avoid huge results.
        .limit(200)
        .get();
      developer.log('[FirestoreService] getApprovedPois(): user_pois docs: ${userSnapshot.docs.length}', name: 'FirestoreService');
      final userRaw = userSnapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        final Map<String, dynamic> serial = {};
        data.forEach((k, v) {
          if (v is GeoPoint) {
            serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
          } else {
            serial[k] = v;
          }
        });
        return serial;
      }).toList();
      final normalizedUserPois = await compute(_normalizeDocsForPlaces, userRaw);
      userPois = normalizedUserPois
        .map((data) => Place(
          name: data['name'] ?? '',
          category: data['category'] ?? 'otros',
          position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
          description: data['description'],
          iconPath: data['iconPath'] as String?,
          specialCategories: data['specialCategories'] is List ? List<String>.from((data['specialCategories'] as List).map((e) => e.toString())) : null,
          ))
        .whereType<Place>()
        .toList();
        } catch (e, s) {
          developer.log('[FirestoreService] getApprovedPois(): error reading user_pois: $e', name: 'FirestoreService', error: e, stackTrace: s);
          // ignore user_pois errors and continue with canonical pois
        }
      }

        // 3) Additionally, if a migration was performed, read `pdis_v2` which
        // contains normalized documents (slug, category). This is optional and
        // non-fatal: if the collection is absent or access is denied we continue.
        List<Place> pdisV2Places = [];
        try {
          final pdisSnapshot = await _firestore
            .collection(_pdisV2CollectionName)
            .limit(limit)
            .get();
          developer.log('[FirestoreService] getApprovedPois(): pdis_v2 docs: ${pdisSnapshot.docs.length}', name: 'FirestoreService');
          final pdisRaw = pdisSnapshot.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            final Map<String, dynamic> serial = {};
            data.forEach((k, v) {
              if (v is GeoPoint) {
                serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
              } else {
                serial[k] = v;
              }
            });
            return serial;
          }).toList();
          final normalizedPdis = await compute(_normalizeDocsForPlaces, pdisRaw);
          pdisV2Places = normalizedPdis
            .map((data) => Place(
              name: data['name'] ?? '',
              category: data['category'] ?? 'otros',
              position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
              description: data['description'],
              iconPath: data['iconPath'] as String?,
            ))
            .whereType<Place>()
            .toList();
        } catch (e, s) {
          developer.log('[FirestoreService] getApprovedPois(): error reading pdis_v2 (continuing): $e', name: 'FirestoreService', error: e, stackTrace: s);
        }

      // 3) Merge and deduplicate by rounded coordinates + name
      final Map<String, Place> merged = {};
      void addPlace(Place p) {
        final key = '${p.position.latitude.toStringAsFixed(6)}:${p.position.longitude.toStringAsFixed(6)}:${p.name.toLowerCase()}';
        if (!merged.containsKey(key)) merged[key] = p;
      }

      for (final p in pois) {
        addPlace(p);
      }
      for (final p in userPois) {
        addPlace(p);
      }
      for (final p in pdisV2Places) {
        addPlace(p);
      }

      final results = merged.values.toList();

      // 4) Respect the overall limit
      if (results.length > limit) {
        developer.log('[FirestoreService] getApprovedPois(): truncating results from ${results.length} to $limit', name: 'FirestoreService');
        return results.sublist(0, limit);
      }
      return results;
    } catch (e, s) {
      developer.log('[FirestoreService] getApprovedPois() ERROR', name: 'FirestoreService', error: e, stackTrace: s);
      return [];
    }
  }

  /// Fetch POIs within a bounding box. This requires documents to have
  /// top-level numeric `latitude` and `longitude` fields. The query uses a
  /// range on latitude and client-side filters longitude. Returns an empty
  /// list if the collection can't be read or if no docs match.
  Future<List<Place>> getPoisInBounds(LatLngBounds bounds, {double paddingDegrees = 0.05, int limit = 1000}) async {
    try {
      final south = bounds.southwest.latitude - paddingDegrees;
      final north = bounds.northeast.latitude + paddingDegrees;
      double west = bounds.southwest.longitude - paddingDegrees;
      double east = bounds.northeast.longitude + paddingDegrees;

      // Normalize longitude wrap-around
      if (west < -180) west += 360;
      if (east > 180) east -= 360;

      developer.log('[FirestoreService] getPoisInBounds(): lat range $south..$north, lng range $west..$east', name: 'FirestoreService');

      // Query by latitude range (Firestore supports range filters on a single field)
      final snapshot = await _firestore
        .collection(_pdisV2CollectionName)
        .where('latitude', isGreaterThanOrEqualTo: south)
        .where('latitude', isLessThanOrEqualTo: north)
        .limit(limit)
        .get();

      developer.log('[FirestoreService] getPoisInBounds(): returned docs: ${snapshot.docs.length}', name: 'FirestoreService');

      final pdisRaw = snapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        final Map<String, dynamic> serial = {};
        data.forEach((k, v) {
          if (v is GeoPoint) {
            serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
          } else {
            serial[k] = v;
          }
        });
        return serial;
      }).toList();

      final normalized = await compute(_normalizeDocsForPlaces, pdisRaw);

      // Filter by longitude client-side (handles dateline wrap if necessary)
      List<Map<String, dynamic>> filtered = normalized.where((data) {
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        if (lat == null || lng == null) return false;
        bool lngInRange;
        if (west <= east) {
          lngInRange = lng >= west && lng <= east;
        } else {
          // wrap-around case
          lngInRange = lng >= west || lng <= east;
        }
        return lngInRange && lat >= south && lat <= north;
      }).toList();

      final places = filtered.map((data) => Place(
        name: data['name'] ?? '',
        category: data['category'] ?? 'otros',
        position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
        description: data['description'],
        iconPath: data['iconPath'] as String?,
      )).whereType<Place>().toList();

      return places;
    } catch (e, s) {
      developer.log('[FirestoreService] getPoisInBounds() ERROR: $e', name: 'FirestoreService', error: e, stackTrace: s);
      return [];
    }
  }

  /// Same as getPoisInBounds but reads `user_pois` and only includes
  /// documents with status == 'approved'.
  Future<List<Place>> getUserPoisInBounds(LatLngBounds bounds, {double paddingDegrees = 0.05, int limit = 500}) async {
    try {
      final south = bounds.southwest.latitude - paddingDegrees;
      final north = bounds.northeast.latitude + paddingDegrees;

      // Many user-submitted POIs don't have top-level `latitude`/`longitude`.
      // To be robust we read a reasonable set of approved user_pois and
      // compute/filter client-side. This avoids missing docs stored with
      // `position`, `geopoint`, `geo` or legacy nested fields.
      final snapshot = await _firestore
        .collection(_userPoisCollectionName)
        .where('status', isEqualTo: 'approved')
        .limit(limit)
        .get();

      developer.log('[FirestoreService] getUserPoisInBounds(): returned docs: ${snapshot.docs.length}', name: 'FirestoreService');

      final raw = snapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        final Map<String, dynamic> serial = {};
        data.forEach((k, v) {
          if (v is GeoPoint) {
            serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
          } else if (v is Map) {
            serial[k] = Map<String, dynamic>.from(v);
          } else {
            serial[k] = v;
          }
        });
        return serial;
      }).toList();

      final normalized = await compute(_normalizeDocsForPlaces, raw);

      // Filter by bounds client-side (handles dateline wrap and missing top-level fields)
      final filtered = normalized.where((data) {
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        if (lat == null || lng == null) return false;
        final west = bounds.southwest.longitude - paddingDegrees;
        final east = bounds.northeast.longitude + paddingDegrees;
        bool lngInRange;
        if (west <= east) {
          lngInRange = lng >= west && lng <= east;
        } else {
          lngInRange = lng >= west || lng <= east;
        }
        return lat >= south && lat <= north && lngInRange;
      }).toList();

      final places = filtered.map((data) => Place(
        name: data['name'] ?? '',
        category: data['category'] ?? 'otros',
        position: LatLng((data['latitude'] as double), (data['longitude'] as double)),
        description: data['description'],
        iconPath: data['iconPath'] as String?,
      )).whereType<Place>().toList();

      return places;
    } catch (e, s) {
      developer.log('[FirestoreService] getUserPoisInBounds() ERROR: $e', name: 'FirestoreService', error: e, stackTrace: s);
      return [];
    }
  }

  /// Fetch POIs within a radius (in kilometers) from a center point.
  /// Uses a latitude range query and client-side longitude filtering.
  Future<List<Place>> getPoisInRadius(LatLng center, double radiusKm, {int limit = 2000}) async {
    try {
      // Approximate degrees per km
      const double kmPerDegLat = 111.32;
      final double latDelta = radiusKm / kmPerDegLat;
      final double south = center.latitude - latDelta;
      final double north = center.latitude + latDelta;

      // Longitude degrees vary with latitude
  final double kmPerDegLng = kmPerDegLat * (math.cos(center.latitude * 3.141592653589793 / 180.0));
      final double lngDelta = (kmPerDegLng.abs() < 1e-6) ? 180.0 : radiusKm / kmPerDegLng.abs();
      double west = center.longitude - lngDelta;
      double east = center.longitude + lngDelta;

      if (west < -180) west += 360;
      if (east > 180) east -= 360;

      developer.log('[FirestoreService] getPoisInRadius(): center=${center.latitude},${center.longitude} radiusKm=$radiusKm latRange=$south..$north lngApprox=$west..$east', name: 'FirestoreService');

      final snapshot = await _firestore
        .collection(_pdisV2CollectionName)
        .where('latitude', isGreaterThanOrEqualTo: south)
        .where('latitude', isLessThanOrEqualTo: north)
        .limit(limit)
        .get();

      final pdisRaw = snapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        final Map<String, dynamic> serial = {};
        data.forEach((k, v) {
          if (v is GeoPoint) {
            serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
          } else {
            serial[k] = v;
          }
        });
        return serial;
      }).toList();

      final normalized = await compute(_normalizeDocsForPlaces, pdisRaw);

      // Filter by actual great-circle distance to ensure within radius
      List<Place> places = [];
      for (final data in normalized) {
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        if (lat == null || lng == null) continue;
        // Haversine distance
        final double r = 6371.0; // Earth radius km
        final double dLat = (lat - center.latitude) * (3.141592653589793 / 180.0);
        final double dLng = (lng - center.longitude) * (3.141592653589793 / 180.0);
  final double a = (math.sin(dLat / 2) * math.sin(dLat / 2)) + (math.cos(center.latitude * (3.141592653589793 / 180.0)) * math.cos(lat * (3.141592653589793 / 180.0)) * math.sin(dLng / 2) * math.sin(dLng / 2));
  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
        final double dist = r * c;
        if (dist <= radiusKm) {
          places.add(Place(
            name: data['name'] ?? '',
            category: data['category'] ?? 'otros',
            position: LatLng(lat, lng),
            description: data['description'],
            iconPath: data['iconPath'] as String?,
          ));
        }
      }

      developer.log('[FirestoreService] getPoisInRadius(): matched ${places.length} places within $radiusKm km', name: 'FirestoreService');
      return places;
    } catch (e, s) {
      developer.log('[FirestoreService] getPoisInRadius() ERROR: $e', name: 'FirestoreService', error: e, stackTrace: s);
      return [];
    }
  }

  /// Same as getPoisInRadius but for `user_pois` (only status == 'approved').
  Future<List<Place>> getUserPoisInRadius(LatLng center, double radiusKm, {int limit = 1000}) async {
    try {
  // Read a reasonable set of approved user_pois and perform Haversine
      // filtering client-side so we don't miss docs stored in different formats.
      final snapshot = await _firestore
        .collection(_userPoisCollectionName)
        .where('status', isEqualTo: 'approved')
        .limit(limit)
        .get();

      final raw = snapshot.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        final Map<String, dynamic> serial = {};
        data.forEach((k, v) {
          if (v is GeoPoint) {
            serial[k] = {'latitude': v.latitude, 'longitude': v.longitude};
          } else if (v is Map) {
            serial[k] = Map<String, dynamic>.from(v);
          } else {
            serial[k] = v;
          }
        });
        return serial;
      }).toList();


  final normalized = await compute(_normalizeDocsForPlaces, raw);

      // Haversine filtering
      List<Place> places = [];
      for (final data in normalized) {
        final lat = data['latitude'] as double?;
        final lng = data['longitude'] as double?;
        if (lat == null || lng == null) continue;
        final double r = 6371.0; // Earth radius km
        final double dLat = (lat - center.latitude) * (3.141592653589793 / 180.0);
        final double dLng = (lng - center.longitude) * (3.141592653589793 / 180.0);
        final double a = (math.sin(dLat / 2) * math.sin(dLat / 2)) + (math.cos(center.latitude * (3.141592653589793 / 180.0)) * math.cos(lat * (3.141592653589793 / 180.0)) * math.sin(dLng / 2) * math.sin(dLng / 2));
        final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
        final double dist = r * c;
        if (dist <= radiusKm) {
          places.add(Place(
            name: data['name'] ?? '',
            category: data['category'] ?? 'otros',
            position: LatLng(lat, lng),
            description: data['description'],
            iconPath: data['iconPath'] as String?,
          ));
        }
      }
      developer.log('[FirestoreService] getUserPoisInRadius(): matched ${places.length} user_pois within $radiusKm km', name: 'FirestoreService');
      return places;
    } catch (e, s) {
      developer.log('[FirestoreService] getUserPoisInRadius() ERROR: $e', name: 'FirestoreService', error: e, stackTrace: s);
      return [];
    }
  }

  /// Stream of user-submitted POIs pending approval from 'user_pois'.
  Stream<QuerySnapshot> pendingUserPoisStream() {
    developer.log('[FirestoreService] pendingUserPoisStream(): subscribing to user_pois (status==pending)',
        name: 'FirestoreService');
    return resilientStream(
      _firestore.collection(_userPoisCollectionName).where('status', isEqualTo: 'pending').snapshots(),
      name: 'pending_user_pois_stream',
    );
  }

  /// Approve a user-submitted POI by updating its status to 'approved'.
  /// Note: Optionally, you may want to move the document to 'pois'.
  Future<void> approveUserPoi(String poiId) async {
    try {
      await _firestore
          .collection(_userPoisCollectionName)
          .doc(poiId)
          .update({'status': 'approved', 'approvedAt': FieldValue.serverTimestamp()});
      developer.log('[FirestoreService] approveUserPoi(): approved $poiId', name: 'FirestoreService');
    } catch (e) {
      developer.log('[FirestoreService] approveUserPoi() ERROR: $e', name: 'FirestoreService');
      rethrow;
    }
  }

  /// Approve and move a user-submitted POI from 'user_pois' to 'pois'.
  /// 1) Read doc from user_pois
  /// 2) Create new doc in pois with normalized fields and approved metadata
  /// 3) Delete original user_pois doc
  /// 4) Optionally increment submitter's approvedPoisCount
  Future<void> approveUserPoiAndMove(String poiId) async {
    final userPoiRef = _firestore.collection(_userPoisCollectionName).doc(poiId);
    final userPoiSnap = await userPoiRef.get();
    if (!userPoiSnap.exists) {
      throw StateError('El PDI no existe o ya fue procesado.');
    }

    final data = userPoiSnap.data() as Map<String, dynamic>;

    // Normalize coordinates
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
      final rawLat = pos['lat'];
      final rawLng = pos['lng'];
      lat = (rawLat is int) ? rawLat.toDouble() : (rawLat as double?);
      lng = (rawLng is int) ? rawLng.toDouble() : (rawLng as double?);
    }
    if ((lat == null || lng == null) && data['geopoint'] is GeoPoint) {
      final gp = data['geopoint'] as GeoPoint;
      lat = gp.latitude;
      lng = gp.longitude;
    }
    // geoflutterfire format: geo: { geopoint: GeoPoint, geohash: string }
    if ((lat == null || lng == null) && data['geo'] is Map) {
      final geo = Map<String, dynamic>.from(data['geo'] as Map);
      final maybeGp = geo['geopoint'];
      if (maybeGp is GeoPoint) {
        lat = maybeGp.latitude;
        lng = maybeGp.longitude;
      }
    }

    // (block removed - pdis_v2 handling moved to the top of this function)
    if (lat == null || lng == null) {
      throw StateError('El PDI no tiene coordenadas válidas.');
    }

    final submitterUid = (data['submittedBy'] ?? data['creator_uid'] ?? '').toString();

    final poisRef = _firestore.collection(_poisCollectionName).doc();
    final batch = _firestore.batch();
    batch.set(poisRef, {
      'name': (data['name'] ?? '').toString(),
      'description': data['description']?.toString(),
      'category': (data['category'] ?? 'otros').toString(),
      // Store as canonical latitude/longitude
      'latitude': lat,
      'longitude': lng,
      'status': 'approved',
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedFrom': _userPoisCollectionName,
      if (submitterUid.isNotEmpty) 'submittedBy': submitterUid,
      'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
    });
    // Delete original
    batch.delete(userPoiRef);

    // Also add a lightweight record into the submitter's `users/{uid}/added_pois`
    // so approved PDIs are visible in the user's "Añadidos" / historial.
    if (submitterUid.isNotEmpty) {
      final userAddedRef = _firestore.collection(_usersCollectionName).doc(submitterUid).collection('added_pois').doc(poisRef.id);
      batch.set(userAddedRef, {
        'name': (data['name'] ?? '').toString(),
        'category': (data['category'] ?? 'otros').toString(),
        'latitude': lat,
        'longitude': lng,
        'poiId': poisRef.id,
        'approvedAt': FieldValue.serverTimestamp(),
        'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
        'source': _poisCollectionName,
      });
    }

    // Optionally increment submitter's approvedPoisCount
    if (submitterUid.isNotEmpty) {
      final userRef = _firestore.collection(_usersCollectionName).doc(submitterUid);
      batch.update(userRef, {'approvedPoisCount': FieldValue.increment(1)});
    }

    await batch.commit();
    developer.log('[FirestoreService] approveUserPoiAndMove(): moved $poiId to ${poisRef.id}', name: 'FirestoreService');

    // Update the submitter's history_places entry (if any) to mark it approved
    if (submitterUid.isNotEmpty) {
      try {
        final histQuery = await _firestore
            .collection(_usersCollectionName)
            .doc(submitterUid)
            .collection('history_places')
            .where('source', isEqualTo: 'user_pois')
            .where('sourceId', isEqualTo: poiId)
            .get();
        for (final h in histQuery.docs) {
          await h.reference.update({
            'status': 'approved',
            'poiId': poisRef.id,
            'approvedAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e, s) {
        developer.log('Error updating history_places for $submitterUid: $e', name: 'FirestoreService', error: e, stackTrace: s);
      }
    }

    // Award +2 days subscription to the submitter (if any) to keep parity with
    // the server-side Cloud Function that awards on approval. Admin users have
    // permission to update user documents according to security rules, so we
    // apply the award here to avoid missing awards when the admin moves the
    // document instead of updating its status in-place.
    if (submitterUid.isNotEmpty) {
      try {
        await _firestore.runTransaction((tx) async {
          final userRef = _firestore.collection(_usersCollectionName).doc(submitterUid);
          final userSnap = await tx.get(userRef);
          if (!userSnap.exists) return;
          final udata = userSnap.data() as Map<String, dynamic>;
          final List<dynamic> history = (udata['subscriptionHistory'] as List<dynamic>?)?.toList() ?? [];
          final List<dynamic> awards = (udata['awardsHistory'] as List<dynamic>?)?.toList() ?? [];

          final now = DateTime.now();
          final nowTs = Timestamp.fromDate(now);
          final addDays = Duration(days: 2);

          final newAward = {
            'type': 'pdi_approved',
            'days': 2,
            'date': nowTs,
            'poiId': poiId,
          };

          if (history.isEmpty) {
            final newSub = {
              'startDate': nowTs,
              'endDate': Timestamp.fromDate(now.add(addDays)),
            };
            history.add(newSub);
            tx.update(userRef, {
              'subscriptionHistory': history,
              'subscriptionStart': newSub['startDate'],
              'subscriptionEnd': newSub['endDate'],
              'awardsHistory': awards..add(newAward),
            });
          } else {
            // Find latest end date in history
            DateTime latestEnd = DateTime.fromMillisecondsSinceEpoch(0);
            int latestIdx = 0;
            for (int i = 0; i < history.length; i++) {
              try {
                final item = Map<String, dynamic>.from(history[i] as Map);
                final ts = item['endDate'] as Timestamp?;
                if (ts != null) {
                  final dt = ts.toDate();
                  if (dt.isAfter(latestEnd)) {
                    latestEnd = dt;
                    latestIdx = i;
                  }
                }
              } catch (e) {
                // ignore malformed
              }
            }

            if (latestEnd.isAfter(now)) {
              final newEnd = latestEnd.add(addDays);
              final latestItem = Map<String, dynamic>.from(history[latestIdx] as Map);
              history[latestIdx] = {
                'startDate': latestItem['startDate'] ?? nowTs,
                'endDate': Timestamp.fromDate(newEnd),
              };
              tx.update(userRef, {
                'subscriptionHistory': history,
                'subscriptionEnd': Timestamp.fromDate(newEnd),
                'awardsHistory': awards..add(newAward),
              });
            } else {
              final newSub = {
                'startDate': nowTs,
                'endDate': Timestamp.fromDate(now.add(addDays)),
              };
              history.add(newSub);
              tx.update(userRef, {
                'subscriptionHistory': history,
                'subscriptionEnd': newSub['endDate'],
                'awardsHistory': awards..add(newAward),
              });
            }
          }
        });
        developer.log('[FirestoreService] approveUserPoiAndMove(): awarded +2 days to $submitterUid for $poiId', name: 'FirestoreService');
      } catch (e, s) {
        developer.log('Error awarding subscription in approveUserPoiAndMove: $e', name: 'FirestoreService', error: e, stackTrace: s);
      }
    }
  }

  /// Reject (delete) a user-submitted POI.
  Future<void> rejectUserPoi(String poiId) async {
    try {
      await _firestore.collection(_userPoisCollectionName).doc(poiId).delete();
      developer.log('[FirestoreService] rejectUserPoi(): deleted $poiId', name: 'FirestoreService');
    } catch (e) {
      developer.log('[FirestoreService] rejectUserPoi() ERROR: $e', name: 'FirestoreService');
      rethrow;
    }
  }

  /// Internal helper to map a Firestore doc into a Place model.
  /// Supports multiple coordinate formats: (latitude, longitude) fields,
  /// position {lat, lng} map, or a GeoPoint stored in 'geopoint'.
  // _mapDocToPlace removed: normalization and mapping now happen via
  // _normalizeDocsForPlaces and compute() to centralize logic and enable isolates.

  // ========== SUBSCRIPTION MANAGEMENT ==========

  /// Extends a user's subscription by adding a new subscription period.
  /// [uid] - The user ID to extend the subscription for.
  /// [months] - Number of months to extend (can be fractional for partial months).
  /// Returns the new end date of the subscription.
  Future<DateTime> extendUserSubscription(String uid, double months) async {
    try {
      final userDocRef = _firestore.collection(_usersCollectionName).doc(uid);
      final userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        throw Exception('User not found');
      }

      final data = userDoc.data() as Map<String, dynamic>;
      List<dynamic> history = data['subscriptionHistory'] ?? [];

      // Determine the start date for the new subscription period
      DateTime startDate;
      if (history.isNotEmpty) {
        // Find the latest end date in the history
        final latestSub = history.map((item) {
          final map = item as Map<String, dynamic>;
          return (map['endDate'] as Timestamp).toDate();
        }).reduce((a, b) => a.isAfter(b) ? a : b);

        // Start the new period from the latest end date, or from now if it's in the past
        startDate = latestSub.isAfter(DateTime.now()) ? latestSub : DateTime.now();
      } else {
        // No history, start from now
        startDate = DateTime.now();
      }

      // Calculate end date by adding the specified months
      final int wholeDays = (months * 30).round(); // Approximate: 1 month = 30 days
      final endDate = startDate.add(Duration(days: wholeDays));

      // Create the new subscription period
      final newSubscription = {
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(endDate),
      };

      // Append the new subscription to the history
      history.add(newSubscription);

      // Update the user document
      await userDocRef.update({
        'subscriptionHistory': history,
      });

      developer.log(
        'Extended subscription for user $uid by $months months. New end date: $endDate',
        name: 'FirestoreService',
      );

      return endDate;
    } catch (e) {
      developer.log('Error extending subscription: $e', name: 'FirestoreService');
      rethrow;
    }
  }

  /// Reduces a user's subscription by removing days/months from the end date.
  /// [uid] - The user ID to reduce the subscription for.
  /// [months] - Number of months to reduce (can be fractional).
  /// Returns the new end date of the subscription.
  Future<DateTime> reduceUserSubscription(String uid, double months) async {
    try {
      final userDocRef = _firestore.collection(_usersCollectionName).doc(uid);
      final userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        throw Exception('User not found');
      }

      final data = userDoc.data() as Map<String, dynamic>;
      List<dynamic> history = data['subscriptionHistory'] ?? [];

      if (history.isEmpty) {
        throw Exception('No subscription history found');
      }

      // Find the latest subscription
      final latestSubMap = history.last as Map<String, dynamic>;
      final currentEndDate = (latestSubMap['endDate'] as Timestamp).toDate();
      final startDate = (latestSubMap['startDate'] as Timestamp).toDate();

      // Calculate new end date by subtracting months
      final int daysToSubtract = (months * 30).round();
      final newEndDate = currentEndDate.subtract(Duration(days: daysToSubtract));

      // Make sure the new end date is not before the start date
      if (newEndDate.isBefore(startDate)) {
        throw Exception('No se puede reducir más allá de la fecha de inicio');
      }

      // Update the latest subscription in history
      history[history.length - 1] = {
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(newEndDate),
      };

      // Update the user document
      await userDocRef.update({
        'subscriptionHistory': history,
      });

      developer.log(
        'Reduced subscription for user $uid by $months months. New end date: $newEndDate',
        name: 'FirestoreService',
      );

      return newEndDate;
    } catch (e) {
      developer.log('Error reducing subscription: $e', name: 'FirestoreService');
      rethrow;
    }
  }

  /// Freezes a user's subscription by marking it with a special flag.
  /// [uid] - The user ID to freeze the subscription for.
  /// [freeze] - true to freeze, false to unfreeze.
  Future<void> freezeUserSubscription(String uid, bool freeze) async {
    try {
      final userDocRef = _firestore.collection(_usersCollectionName).doc(uid);
      final userDoc = await userDocRef.get();

      if (!userDoc.exists) {
        throw Exception('User not found');
      }

      // Add or update the frozen flag
      await userDocRef.update({
        'subscriptionFrozen': freeze,
        'subscriptionFrozenDate': freeze ? Timestamp.now() : null,
      });

      developer.log(
        'Subscription for user $uid is now ${freeze ? "frozen" : "unfrozen"}',
        name: 'FirestoreService',
      );
    } catch (e) {
      developer.log('Error freezing subscription: $e', name: 'FirestoreService');
      rethrow;
    }
  }

  /// Gets all users for subscription management
  Stream<QuerySnapshot> getAllUsersStream() {
    return _firestore
        .collection(_usersCollectionName)
        .orderBy('email')
        .snapshots();
  }
}
