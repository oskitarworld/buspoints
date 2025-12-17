import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class WebPlacesAutocomplete {
  // Devuelve una lista de objetos con {description, place_id}
  static Future<List<Map<String, dynamic>>> getSuggestions(String input) async {
    if (!kIsWeb) return [];
    // Cambia la URL por la de tu función desplegada en Firebase
    final url = Uri.parse(
      'https://us-central1-buspoint-49ea0.cloudfunctions.net/placesAutocomplete?input=$input',
    );
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final predictions = data['predictions'] as List;
      return predictions.map((p) => {
            'description': p['description'],
            'place_id': p['place_id'] ?? '',
          }).toList();
    } else {
      return [];
    }
  }
}
