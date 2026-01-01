import 'package:cloud_firestore/cloud_firestore.dart';

class UserRoutePoint {
  final double lat;
  final double lng;
  final String? name;

  UserRoutePoint({required this.lat, required this.lng, this.name});

  Map<String, dynamic> toMap() => {'lat': lat, 'lng': lng, 'name': name};

  factory UserRoutePoint.fromMap(Map<String, dynamic> m) {
    return UserRoutePoint(lat: (m['lat'] as num).toDouble(), lng: (m['lng'] as num).toDouble(), name: m['name'] as String?);
  }
}

class UserRoute {
  final String id;
  final String name;
  final String description;
  final String createdBy;
  final List<UserRoutePoint> pdis;
  final bool isPublic;
  final Timestamp createdAt;

  UserRoute({required this.id, required this.name, required this.description, required this.createdBy, required this.pdis, required this.isPublic, required this.createdAt});

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'createdBy': createdBy,
        'pdis': pdis.map((p) => p.toMap()).toList(),
        'isPublic': isPublic,
        'createdAt': createdAt,
      };

  factory UserRoute.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final pdisList = (data['pdis'] as List? ?? []).map((e) => UserRoutePoint.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    return UserRoute(id: doc.id, name: data['name'] ?? '', description: data['description'] ?? '', createdBy: data['createdBy'] ?? '', pdis: pdisList, isPublic: data['isPublic'] ?? true, createdAt: data['createdAt'] ?? Timestamp.now());
  }
}
