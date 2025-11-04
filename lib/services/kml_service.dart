import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:developer' as developer;

import './kml_parsing.dart';

class KmlService {
  // This method now accepts the file name, loads the content in the main isolate,
  // and then passes the content to the background isolate for parsing.
  Future<List<Map<String, dynamic>>> loadKmlData(String kmlFileName) async {
    try {
      // 1. Load KML string from assets in the main isolate.
      final kmlString = await rootBundle.loadString('assets/pdis/$kmlFileName');

      // 2. Pass the loaded string and file name to the background isolate for parsing.
      // We use a map to pass multiple arguments to the compute function.
      final isolatesArguments = {
        'kmlString': kmlString,
        'kmlFileName': kmlFileName,
      };

      final placesData = await compute(_parseInIsolate, isolatesArguments);

      return placesData;
    } catch (e, s) {
      developer.log(
          'KML_Service: Error during KML processing for $kmlFileName: ${e.toString()}',
          stackTrace: s,
          name: 'kml.service');
      return [];
    }
  }
}

// This is the top-level function that will run in the new isolate.
// It unpacks the arguments and calls the pure parsing function.
List<Map<String, dynamic>> _parseInIsolate(Map<String, String> args) {
  final kmlString = args['kmlString']!;
  final kmlFileName = args['kmlFileName']!;
  // Call the refactored, pure parsing function from kml_parsing.dart
  return parseKmlContent(kmlString, kmlFileName);
}
