import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/models/user_route.dart';

class RouteService {
  final CollectionReference _col = FirebaseFirestore.instance.collection('user_routes');

  /// Create a new user route.
  ///
  /// If [isPublicChoice] is true the user intends the route to be public
  /// (community). Public submissions require admin approval and will be
  /// created in a 'pending' state. If false the route is private (only the
  /// creator can see it) and will not require admin approval.
  Future<String> createRoute({required String name, required String description, required String uid, required List<UserRoutePoint> pdis, bool isPublicChoice = true}) async {
    final docRef = await _col.add({
      'name': name,
      'description': description,
      'createdBy': uid,
      'pdis': pdis.map((p) => p.toMap()).toList(),
      // By default routes are not approved and not public. We add a
      // helper flag 'needsApproval' so admins can filter only submissions
      // that require review (public submissions). Private routes set
      // needsApproval=false and will not appear in the admin queue.
      'approved': false,
      'isPublic': false,
      'isPrivate': !isPublicChoice,
      'needsApproval': isPublicChoice,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Approve a route (admin action). This updates the route document to
  /// mark it as approved and optionally make it public.
  Future<void> approveRoute(String routeId, {bool makePublic = true}) async {
    await _col.doc(routeId).update({'approved': true, 'isPublic': makePublic});
  }

  Future<List<UserRoute>> fetchPublicRoutes({int limit = 50}) async {
    final snap = await _col.where('isPublic', isEqualTo: true).orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => UserRoute.fromDoc(d)).toList();
  }

  Future<UserRoute> getRoute(String id) async {
    final doc = await _col.doc(id).get();
    return UserRoute.fromDoc(doc);
  }
}
