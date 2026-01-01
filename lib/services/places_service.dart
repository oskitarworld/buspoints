import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/models/place.dart';

class PlacesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Place>> getPlaces() async {
    try {
      developer.log('INICIO getPlaces', name: 'PlacesService');
      final snapshot = await _firestore.collection('points').where('status', isEqualTo: 'approved').get();
      developer.log('Documentos recibidos: ${snapshot.docs.length}', name: 'PlacesService');
      final places = snapshot.docs.map((doc) {
        final data = doc.data();
        developer.log('Doc: ${doc.id}, data: $data', name: 'PlacesService');
        return Place(
          name: data['name'] ?? '',
          description: data['description'] ?? '',
          category: data['category'] ?? 'otros',
          position: LatLng(
            (data['latitude'] ?? 0.0) as double,
            (data['longitude'] ?? 0.0) as double,
          ),
          specialCategories: data['specialCategories'] is List ? List<String>.from((data['specialCategories'] as List).map((e) => e.toString())) : null,
        );
      }).toList();
      developer.log('Lugares parseados: ${places.length}', name: 'PlacesService');
      return places;
    } catch (e) {
      developer.log('ERROR: $e', name: 'PlacesService', error: e, stackTrace: StackTrace.current);
      return [];
    }
  }

  Future<List<Place>> getPlacesByCategory(String category) async {
    try {
      final snapshot = await _firestore
          .collection('points')
          .where('category', isEqualTo: category)
          .where('status', isEqualTo: 'approved')
          .get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Place(
          name: data['name'] ?? '',
          description: data['description'] ?? '',
          category: data['category'] ?? 'otros',
          position: LatLng(
            (data['latitude'] ?? 0.0) as double,
            (data['longitude'] ?? 0.0) as double,
          ),
          specialCategories: data['specialCategories'] is List ? List<String>.from((data['specialCategories'] as List).map((e) => e.toString())) : null,
        );
      }).toList();
    } catch (e) {
      developer.log('Error fetching places by category: $e', name: 'PlacesService', error: e, stackTrace: StackTrace.current);
      return [];
    }
  }

  Future<void> addPlace(Place place) async {
    try {
      await _firestore.collection('places').add({
        'name': place.name,
        'description': place.description,
        'category': place.category,
        'position': {
          'lat': place.position.latitude,
          'lng': place.position.longitude,
        },
      });
    } catch (e) {
      developer.log('Error adding place: $e', name: 'PlacesService', error: e, stackTrace: StackTrace.current);
      rethrow;
    }
  }

  Future<void> updatePlace(String placeId, Place place) async {
    try {
      await _firestore.collection('places').doc(placeId).update({
        'name': place.name,
        'description': place.description,
        'category': place.category,
        'position': {
          'lat': place.position.latitude,
          'lng': place.position.longitude,
        },
      });
    } catch (e) {
      developer.log('Error updating place: $e', name: 'PlacesService', error: e, stackTrace: StackTrace.current);
      rethrow;
    }
  }

  Future<void> deletePlace(String placeId) async {
    try {
      await _firestore.collection('places').doc(placeId).delete();
    } catch (e) {
      developer.log('Error deleting place: $e', name: 'PlacesService', error: e, stackTrace: StackTrace.current);
      rethrow;
    }
  }
}