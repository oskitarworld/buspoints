import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:xml/xml.dart' as xml;
import 'dart:convert';
import 'dart:developer' as developer;

class MigrateKmlToFirestore {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> migrate() async {
    try {
      final kmlFileNames = await _getKmlFileNames();
      developer.log(
          'Starting migration for ${kmlFileNames.length} KML files...',
          name: 'kml.migration');

      for (String fileName in kmlFileNames) {
        await _migrateFile(fileName);
      }

      developer.log('KML data migration to Firestore completed successfully!',
          name: 'kml.migration');
    } catch (e, s) {
      developer.log('Error during the migration process: ${e.toString()}',
          stackTrace: s, name: 'kml.migration');
      throw Exception('Migration failed. Check logs for details.');
    }
  }

  Future<List<String>> _getKmlFileNames() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    final kmlFiles = manifestMap.keys
        .where((String key) =>
            key.startsWith('assets/pdis/') && key.endsWith('.kml'))
        .toList();
    return kmlFiles;
  }

  Future<void> _migrateFile(String assetPath) async {
    try {
      final kmlString = await rootBundle.loadString(assetPath);
      final document = xml.XmlDocument.parse(kmlString);
      final placemarks = document.descendants
          .whereType<xml.XmlElement>()
          .where((e) => e.name.local == 'Placemark');

      developer.log('Migrating ${placemarks.length} placemarks from $assetPath',
          name: 'kml.migration');

      WriteBatch batch = _firestore.batch();
      int counter = 0;

      for (var placemark in placemarks) {
        final name = _extractData(placemark, 'name');
        final description = _extractData(placemark, 'description');
        final coordinatesString = _extractCoordinates(placemark);
        final styleUrl = _extractStyleUrl(placemark);

        if (name != null && coordinatesString != null) {
          final parts = coordinatesString.split(',');
          if (parts.length >= 2) {
            final longitude = double.tryParse(parts[0]);
            final latitude = double.tryParse(parts[1]);

            if (latitude != null && longitude != null) {
              final docRef = _firestore.collection('locations').doc();
              batch.set(docRef, {
                'name': name,
                'description': description,
                'location': GeoPoint(latitude, longitude),
                'category': styleUrl?.replaceFirst('#', '') ?? '',
                'original_file': assetPath.split('/').last,
                'status': 'approved',
                'created_at': FieldValue.serverTimestamp(),
              });
              counter++;
            }
          }
        }
        // Commit batch in chunks to avoid exceeding limits
        if (counter >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          counter = 0;
        }
      }
      // Commit any remaining operations
      if (counter > 0) {
        await batch.commit();
      }
      developer.log(
          'Successfully migrated ${placemarks.length} placemarks from $assetPath.',
          name: 'kml.migration');
    } catch (e, s) {
      developer.log('Failed to migrate file $assetPath: ${e.toString()}',
          stackTrace: s, name: 'kml.migration');
      // Continue with the next file
    }
  }

  String? _extractData(xml.XmlElement placemark, String fieldName) {
    try {
      return placemark.descendants
          .firstWhere((e) => e is xml.XmlElement && e.name.local == fieldName)
          .value
          ?.trim();
    } catch (e) {
      return null;
    }
  }

  String? _extractCoordinates(xml.XmlElement placemark) {
    try {
      return placemark.descendants
          .firstWhere(
              (e) => e is xml.XmlElement && e.name.local == 'coordinates')
          .value
          ?.trim();
    } catch (e) {
      return null;
    }
  }

  String? _extractStyleUrl(xml.XmlElement placemark) {
    try {
      return placemark.descendants
          .firstWhere((e) => e is xml.XmlElement && e.name.local == 'styleUrl')
          .value
          ?.trim();
    } catch (e) {
      return null;
    }
  }
}
