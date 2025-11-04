import 'dart:io';
import 'dart:developer' as developer;
import 'package:path/path.dart' as p;
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/firebase_options.dart';
import 'package:myapp/services/kml_parsing.dart';

// This is a standalone Dart script to migrate KML data to Firestore.
// To run it:
// 1. Make sure you have a `firebase_options.dart` file correctly configured.
// 2. Run `flutter pub get` in your terminal.
// 3. Execute this script from the root of your project: `dart tool/migration.dart [path_to_kml_file]`
//    If no file path is provided, it will attempt to process all files.

Future<void> main(List<String> args) async {
  // Accept command line arguments
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  developer.log('Firebase Initialized. Starting migration...',
      name: 'migration.script');

  final firestore = FirebaseFirestore.instance;
  final poiCollection = firestore.collection('puntos_de_interes');

  List<File> kmlFilesToProcess = [];

  if (args.isNotEmpty) {
    // A specific file path is provided as an argument
    final filePath = args[0];
    if (p.extension(filePath) == '.kml' && await File(filePath).exists()) {
      kmlFilesToProcess.add(File(filePath));
      developer.log('Processing specified file: $filePath',
          name: 'migration.script');
    } else {
      developer.log(
          'Error: The file specified does not exist or is not a .kml file: $filePath',
          name: 'migration.script',
          level: 1000);
      return;
    }
  } else {
    // No arguments, process all files in the directory
    final pdisDirectory = Directory('assets/pdis');
    if (!await pdisDirectory.exists()) {
      developer.log('Error: assets/pdis directory not found.',
          name: 'migration.script', level: 1000);
      return;
    }
    kmlFilesToProcess = (await pdisDirectory.list().toList())
        .where((file) => file is File && p.extension(file.path) == '.kml')
        .map((file) => file as File)
        .toList();
    developer.log(
        'Found ${kmlFilesToProcess.length} KML files to process in assets/pdis/.',
        name: 'migration.script');
  }

  if (kmlFilesToProcess.isEmpty) {
    developer.log('No .kml files found to process.', name: 'migration.script');
    return;
  }

  int totalMigratedPois = 0;

  for (final file in kmlFilesToProcess) {
    final fileName = p.basename(file.path);
    developer.log('--- Processing $fileName ---', name: 'migration.script');
    try {
      final kmlString = await file.readAsString();
      final List<Map<String, dynamic>> places =
          parseKmlContent(kmlString, fileName);

      if (places.isEmpty) {
        developer.log('No placemarks found or parsed in $fileName.',
            name: 'migration.script');
        continue;
      }

      developer.log('Parsed ${places.length} POIs from $fileName.',
          name: 'migration.script');

      final WriteBatch batch = firestore.batch();
      int filePois = 0;

      for (final placeData in places) {
        final newPoiDoc = poiCollection.doc();

        batch.set(newPoiDoc, {
          'name': placeData['name'],
          'description': placeData['description'],
          'category': placeData['category'],
          'location': GeoPoint(placeData['latitude'], placeData['longitude']),
          'createdAt': FieldValue.serverTimestamp(),
        });
        filePois++;
      }

      if (filePois > 0) {
        developer.log(
            'Committing batch of $filePois POIs from $fileName to Firestore...',
            name: 'migration.script');
        await batch.commit();
        developer.log('Successfully committed $filePois POIs from $fileName.',
            name: 'migration.script');
        totalMigratedPois += filePois;
      }
    } catch (e, s) {
      developer.log('Error processing file $fileName',
          name: 'migration.script', error: e, stackTrace: s, level: 1000);
    }
  }

  if (totalMigratedPois > 0) {
    developer.log('\n--- MIGRATION COMPLETE! ---', name: 'migration.script');
    developer.log(
        '$totalMigratedPois points of interest have been successfully uploaded in total.',
        name: 'migration.script');
  } else {
    developer.log('\n--- MIGRATION FINISHED. No new POIs were added. ---',
        name: 'migration.script');
  }
}
