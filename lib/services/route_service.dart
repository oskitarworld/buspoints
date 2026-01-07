import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:myapp/models/user_route.dart';

class RouteService {
  final CollectionReference _col = FirebaseFirestore.instance.collection('user_routes');

  /// Create a new user route.
  ///
  /// [visibility] can be 'public' | 'private' | 'team'. If 'team' or 'private'
  /// and [ownerCompanyId] is provided, the route will be associated to that
  /// company and will not be publicly visible.
  Future<String> createRoute({required String name, required String description, required String uid, required List<UserRoutePoint> pdis, String visibility = 'public', String? ownerCompanyId}) async {
    // If this route is a company/team route, prefer creating it via a server-side
    // callable to avoid depending on client-side custom claims or App Check state.
    if (ownerCompanyId != null) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('createCompanyRoute');
        final res = await callable.call(<String, dynamic>{
          'name': name,
          'description': description,
          'pdis': pdis.map((p) => p.toMap()).toList(),
          'visibility': visibility,
          'ownerCompanyId': ownerCompanyId,
        });
        final data = res.data;
        if (data != null && data is Map && data['id'] != null) return data['id'].toString();
        if (data != null && data is Map && data['status'] == 'ok' && data['id'] != null) return data['id'].toString();
        throw Exception('Respuesta inesperada de createCompanyRoute: $data');
      } on FirebaseFunctionsException catch (fe) {
        // Produce a user-friendly message while preserving original details in logs.
        final msg = (fe.message != null && fe.message!.isNotEmpty) ? fe.message! : 'Error llamando a createCompanyRoute';
        throw Exception('No se pudo crear la ruta de empresa: $msg');
      } catch (e) {
        rethrow;
      }
    }

    // Fallback: personal/private route created directly by the client
    final Map<String, dynamic> doc = {
      'name': name,
      'description': description,
      'createdBy': uid,
      'pdis': pdis.map((p) => p.toMap()).toList(),
      'visibility': visibility, // 'public'|'private'|'team'
      'ownerCompanyId': ownerCompanyId,
      'createdAt': FieldValue.serverTimestamp(),
    };

    // Approval & public flags: public routes need admin approval; private/team are internal
    if (visibility == 'public') {
      doc['approved'] = false;
      doc['isPublic'] = false;
      doc['needsApproval'] = true;
    } else {
      // internal routes: immediate approved for company or private personal routes
      doc['approved'] = true;
      doc['isPublic'] = false;
      doc['needsApproval'] = false;
    }

    final docRef = await _col.add(doc);
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

  /// Fetch routes visible to a specific user.
  /// Includes:
  ///  - public routes which are approved and isPublic == true
  ///  - private routes created by the user
  ///  - team (company) routes where ownerCompanyId is in user's companyIds
  Future<List<UserRoute>> fetchRoutesForUser({required String uid, List<String>? userCompanyIds, int limit = 100}) async {
    // Build queries separately and merge results since Firestore doesn't support OR across different fields easily.
    final results = <UserRoute>[];

    // 1) Public approved routes
    final publicSnap = await _col.where('isPublic', isEqualTo: true).where('approved', isEqualTo: true).orderBy('createdAt', descending: true).limit(limit).get();
    results.addAll(publicSnap.docs.map((d) => UserRoute.fromDoc(d)));

    // 2) Private routes by the user
    final privateSnap = await _col.where('visibility', isEqualTo: 'private').where('createdBy', isEqualTo: uid).orderBy('createdAt', descending: true).limit(limit).get();
    results.addAll(privateSnap.docs.map((d) => UserRoute.fromDoc(d)));

    // 3) Team/company routes for user's companies
    if (userCompanyIds != null && userCompanyIds.isNotEmpty) {
      // Firestore supports 'in' queries with up to 10 items. We'll chunk if necessary.
      final chunks = <List<String>>[];
      for (var i = 0; i < userCompanyIds.length; i += 10) {
        chunks.add(userCompanyIds.sublist(i, i + 10 > userCompanyIds.length ? userCompanyIds.length : i + 10));
      }
      for (final chunk in chunks) {
        final teamSnap = await _col.where('visibility', isEqualTo: 'team').where('ownerCompanyId', whereIn: chunk).orderBy('createdAt', descending: true).limit(limit).get();
        results.addAll(teamSnap.docs.map((d) => UserRoute.fromDoc(d)));
      }
    }

    // Deduplicate by id and return sorted by createdAt desc
    final map = <String, UserRoute>{};
    for (final r in results) {
      map[r.id] = r;
    }
    final list = map.values.toList();
    list.sort((a, b) => b.createdAt.millisecondsSinceEpoch.compareTo(a.createdAt.millisecondsSinceEpoch));
    if (list.length > limit) return list.sublist(0, limit);
    return list;
  }

  Future<UserRoute> getRoute(String id) async {
    final doc = await _col.doc(id).get();
    return UserRoute.fromDoc(doc);
  }

  /// Fetch routes that belong to a specific company (ownerCompanyId == companyId)
  Future<List<UserRoute>> fetchRoutesForCompany(String companyId, {int limit = 100}) async {
    final snap = await _col.where('visibility', isEqualTo: 'team').where('ownerCompanyId', isEqualTo: companyId).orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => UserRoute.fromDoc(d)).toList();
  }

  /// Fetch private routes created by a specific user (visibility == 'private').
  Future<List<UserRoute>> fetchPrivateRoutesForUser(String uid, {int limit = 100}) async {
    final snap = await _col.where('visibility', isEqualTo: 'private').where('createdBy', isEqualTo: uid).orderBy('createdAt', descending: true).limit(limit).get();
    return snap.docs.map((d) => UserRoute.fromDoc(d)).toList();
  }

  /// Delete a route by id. Caller should handle permission errors.
  /// Delete a route by id. If [ownerCompanyId] is provided (team route), this
  /// will call a server-side callable which enforces company ownership/permissions.
  Future<void> deleteRoute(String routeId, {String? ownerCompanyId}) async {
    if (ownerCompanyId != null) {
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('deleteCompanyRoute');
        final res = await callable.call(<String, dynamic>{'routeId': routeId});
        final data = res.data;
        if (data != null && data is Map && data['status'] == 'ok') return;
        if (data != null && data is Map && data['status'] != null) return;
        return;
      } on FirebaseFunctionsException catch (fe) {
        final msg = (fe.message != null && fe.message!.isNotEmpty) ? fe.message! : 'Error calling deleteCompanyRoute';
        throw Exception('No se pudo eliminar la ruta de empresa: $msg');
      }
    }
    await _col.doc(routeId).delete();
  }

  /// Update an existing route. Only the provided fields will be updated.
  Future<void> updateRoute(String routeId, {String? name, String? description, List<dynamic>? pdis, String? visibility, String? ownerCompanyId, bool? approved, bool? isPublic}) async {
    // If this is a company/team route, prefer calling the server callable which
    // enforces company membership and permissions.
    if (ownerCompanyId != null) {
      final Map<String, dynamic> payload = {'routeId': routeId};
      if (name != null) payload['name'] = name;
      if (description != null) payload['description'] = description;
      if (pdis != null) payload['pdis'] = pdis;
      // We deliberately avoid allowing direct client changes to approval/isPublic
      // flags via this callable; those are admin-only operations.
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('updateCompanyRoute');
        final res = await callable.call(payload);
        final data = res.data;
        if (data != null && data is Map && data['status'] == 'ok') return;
        return;
      } on FirebaseFunctionsException catch (fe) {
        final msg = (fe.message != null && fe.message!.isNotEmpty) ? fe.message! : 'Error calling updateCompanyRoute';
        throw Exception('No se pudo actualizar la ruta de empresa: $msg');
      }
    }

    final Map<String, dynamic> patch = {};
    if (name != null) patch['name'] = name;
    if (description != null) patch['description'] = description;
    if (pdis != null) patch['pdis'] = pdis;
    if (visibility != null) patch['visibility'] = visibility;
    if (ownerCompanyId != null) patch['ownerCompanyId'] = ownerCompanyId;
    if (approved != null) patch['approved'] = approved;
    if (isPublic != null) patch['isPublic'] = isPublic;
    if (patch.isEmpty) return;
    patch['updatedAt'] = FieldValue.serverTimestamp();
    await _col.doc(routeId).update(patch);
  }
}
