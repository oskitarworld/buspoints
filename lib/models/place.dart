import 'package:google_maps_flutter/google_maps_flutter.dart';

class Place {
  final String name;
  final String category;
  final LatLng position;
  final String? iconPath;
  final String? description;

  Place({
    required this.name,
    required this.category,
    required this.position,
    this.iconPath,
    this.description,
  });
}
