import 'package:flutter/services.dart' show rootBundle;
import 'package:xml/xml.dart' as xml;
import 'dart:developer' as developer;

// This new top-level function will contain only the parsing logic.
// It is safe to be called from a background isolate via compute().
List<Map<String, dynamic>> parseKmlContent(
    String kmlString, String kmlFileName) {
  try {
    final document = xml.XmlDocument.parse(kmlString);

    final placemarks = document.descendants
        .whereType<xml.XmlElement>()
        .where((e) => e.name.local == 'Placemark');

    final List<Map<String, dynamic>> placesData = [];

    for (var placemark in placemarks) {
      final name = _extractPlacemarkName(placemark);
      final coordinatesString = _extractCoordinates(placemark);

      if (name == null || coordinatesString == null) {
        continue;
      }

      final parts = coordinatesString.split(',');
      if (parts.length < 2) {
        continue;
      }

      final longitude = double.tryParse(parts[0]);
      final latitude = double.tryParse(parts[1]);

      if (longitude == null || latitude == null) {
        continue;
      }

      final description = _extractPlacemarkDescription(placemark);
      final categoryName = _extractCategory(placemark, kmlFileName);

      placesData.add({
        'name': name,
        'category': categoryName,
        'latitude': latitude,
        'longitude': longitude,
        'description': description,
      });
    }

    return placesData;
  } catch (e, s) {
    developer.log(
        'CRITICAL error during KML parsing for $kmlFileName: ${e.toString()}',
        stackTrace: s,
        name: 'kml.parsing');
    return [];
  }
}

// The original function is now refactored to handle loading and then call the parsing function.
Future<List<Map<String, dynamic>>> loadAndParseKml(String kmlFileName) async {
  try {
    final kmlString = await rootBundle.loadString('assets/pdis/$kmlFileName');
    // Call the pure parsing function
    return parseKmlContent(kmlString, kmlFileName);
  } catch (e, s) {
    developer.log(
        'CRITICAL error during KML asset loading for $kmlFileName: ${e.toString()}',
        stackTrace: s,
        name: 'kml.loading');
    return []; // Return empty list on critical failure
  }
}

// Helper to find first element by its local name, searching only direct children.
xml.XmlElement? _findFirstChildElement(
    xml.XmlElement element, String localName) {
  try {
    return element.children
        .whereType<xml.XmlElement>()
        .firstWhere((child) => child.name.local == localName);
  } catch (e) {
    return null; // Return null if not found
  }
}

// Helper to find all elements by their local name, searching only direct children.
Iterable<xml.XmlElement> _findChildElements(
    xml.XmlElement element, String localName) {
  return element.children
      .whereType<xml.XmlElement>()
      .where((child) => child.name.local == localName);
}

// Helper to find a specific data field within ExtendedData.
String? _findDataInExtendedData(xml.XmlElement placemark, String fieldName) {
  final extendedData = _findFirstChildElement(placemark, 'ExtendedData');
  if (extendedData == null) return null;

  final dataElements = _findChildElements(extendedData, 'Data');
  for (final dataElement in dataElements) {
    if (dataElement.getAttribute('name')?.toLowerCase() ==
        fieldName.toLowerCase()) {
      return _findFirstChildElement(dataElement, 'value')?.value?.trim();
    }
  }

  final schemaData = _findFirstChildElement(extendedData, 'SchemaData');
  if (schemaData != null) {
    final simpleDataElements = _findChildElements(schemaData, 'SimpleData');
    for (final simpleDataElement in simpleDataElements) {
      if (simpleDataElement.getAttribute('name')?.toLowerCase() ==
          fieldName.toLowerCase()) {
        return simpleDataElement.value?.trim();
      }
    }
  }

  return null;
}

// Extracts the placemark name.
String? _extractPlacemarkName(xml.XmlElement placemark) {
  final nameElement = _findFirstChildElement(placemark, 'name');
  if (nameElement != null &&
      nameElement.value != null &&
      nameElement.value!.trim().isNotEmpty) {
    return nameElement.value!.trim();
  }
  // Fallback to checking ExtendedData
  final nameFromData = _findDataInExtendedData(placemark, 'name');
  if (nameFromData != null && nameFromData.trim().isNotEmpty) {
    return nameFromData.trim();
  }
  return null;
}

// Extracts the placemark description.
String? _extractPlacemarkDescription(xml.XmlElement placemark) {
  final descElement = _findFirstChildElement(placemark, 'description');
  if (descElement != null &&
      descElement.value != null &&
      descElement.value!.trim().isNotEmpty) {
    return descElement.value!.trim();
  }
  // Fallback to checking ExtendedData
  final descFromData = _findDataInExtendedData(placemark, 'description');
  if (descFromData != null && descFromData.trim().isNotEmpty) {
    return descFromData.trim();
  }
  return null;
}

// Extracts the coordinate string from a Point element.
String? _extractCoordinates(xml.XmlElement placemark) {
  try {
    final point = placemark.descendants
        .firstWhere((e) => e is xml.XmlElement && e.name.local == 'Point');
    return _findFirstChildElement(point as xml.XmlElement, 'coordinates')
        ?.value
        ?.trim();
  } catch (e) {
    // Fallback for coordinates directly under placemark (less common)
    return _findFirstChildElement(placemark, 'coordinates')?.value?.trim();
  }
}

String _extractCategory(xml.XmlElement placemark, String fallbackFileName) {
  final styleUrlElement = _findFirstChildElement(placemark, 'styleUrl');
  if (styleUrlElement != null && styleUrlElement.value != null) {
    final styleUrl = styleUrlElement.value!.trim();
    if (styleUrl.isNotEmpty) {
      // Assuming the category is part of the styleUrl, e.g., "#category-name"
      return styleUrl.replaceFirst('#', '');
    }
  }
  return _getCategoryFromFileName(fallbackFileName);
}

String _getCategoryFromFileName(String fileName) {
  // More robustly remove extension
  return fileName.split('.').first;
}
