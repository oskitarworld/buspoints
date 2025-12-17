import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:myapp/models/place.dart';

class PlacesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<Place>> getPlaces() async {
    try {
      print('[PlacesService] INICIO getPlaces');
      final snapshot = await _firestore.collection('points').where('status', isEqualTo: 'approved').get();
      print('[PlacesService] Documentos recibidos: ${snapshot.docs.length}');
      final places = snapshot.docs.map((doc) {
        final data = doc.data();
        print('[PlacesService] Doc: ${doc.id}, data: $data');
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
      print('[PlacesService] Lugares parseados: ${places.length}');
      return places;
    } catch (e) {
      print('[PlacesService] ERROR: $e');
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
      print('Error fetching places by category: $e');
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
      print('Error adding place: $e');
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
      print('Error updating place: $e');
      rethrow;
    }
  }

  Future<void> deletePlace(String placeId) async {
    try {
      await _firestore.collection('places').doc(placeId).delete();
    } catch (e) {
      print('Error deleting place: $e');
      rethrow;
    }
  }
}