import 'package:google_maps_flutter/google_maps_flutter.dart';

class Place {
  final String name;
  final String category;
  final LatLng position;
  final String? iconPath;
  final String? description;
  final List<String>? specialCategories;

  Place({
    required this.name,
    required this.category,
    required this.position,
    this.iconPath,
    this.description,
    this.specialCategories,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'category': category,
      'position': '${position.latitude},${position.longitude}',
      'iconPath': iconPath,
      'description': description,
      'specialCategories': specialCategories,
    };
  }

  static Place fromMap(Map<String, dynamic> map) {
    final pos = map['position']?.split(',');
    return Place(
      name: map['name'] ?? '',
      category: map['category'] ?? '',
      position: pos != null && pos.length == 2
          ? LatLng(double.tryParse(pos[0]) ?? 0, double.tryParse(pos[1]) ?? 0)
          : const LatLng(0, 0),
      iconPath: map['iconPath'],
      description: map['description'],
      specialCategories: map['specialCategories'] is List ? List<String>.from((map['specialCategories'] as List).map((e) => e.toString())) : null,
    );
  }
}
