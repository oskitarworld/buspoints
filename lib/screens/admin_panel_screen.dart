import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
// import 'package:myapp/services/firestore_web_compat.dart'; // not needed here
// admin_inbox_screen is no longer referenced here; drawer provides access to the inbox.
import 'manage_users_screen.dart';
import 'poi_approval_screen.dart';
// import 'poi_history_screen.dart'; // no longer used after layout redesign
import 'review_approval_screen.dart';
import 'user_approval_screen.dart';
import 'create_user_screen.dart';
// Route creation and community listing are handled from the app UI; admin
// panel uses the dedicated review screen for route moderation.
import 'admin_routes_review_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _pendingUsers = 0;
  int _pendingUserPois = 0;
  int _pendingReviews = 0;
  int _pendingRoutes = 0;
  int get _totalPending => _pendingUsers + _pendingUserPois + _pendingReviews + _pendingRoutes;

  @override
  void initState() {
    super.initState();
    _loadAdminSummary();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadAdminSummary());
  }

  Future<void> _loadAdminSummary() async {
    bool callableSucceeded = false;
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getAdminSummary');
      final result = await callable.call();
      final data = result.data as Map<String, dynamic>? ?? {};
      setState(() {
        _pendingUsers = (data['pendingUsers'] as int?) ?? 0;
        _pendingUserPois = (data['pendingUserPois'] as int?) ?? 0;
        _pendingReviews = (data['pendingReviews'] as int?) ?? 0;
      });
      // Also perform a conservative client-side reconciliation: if the
      // callable reports fewer pending reviews than the client sees, prefer
      // the client-visible count. This ensures the badge shows even when
      // the callable is stale or temporarily inconsistent.
      try {
        final reviewsSnap = await FirebaseFirestore.instance.collectionGroup('reviews').where('status', isEqualTo: 'pending').get();
        final clientPending = reviewsSnap.docs.where((d) => d.reference.path.startsWith('pdis_v2/')).length;
        if (clientPending > _pendingReviews) {
          setState(() {
            _pendingReviews = clientPending;
          });
        }
      } catch (_) {
        // ignore client fallback errors (rules may prevent collectionGroup)
      }
      callableSucceeded = true;
    } catch (e) {
      // callable may fail due to App Check or permissions; fall back to client-side queries below
      debugPrint('getAdminSummary callable failed: $e');
    }
    // If callable failed, try to compute counts via Firestore client queries as a best-effort fallback.
    if (!callableSucceeded) {
      try {
        // pending users (client may only see some fields depending on rules)
        final usersSnap = await FirebaseFirestore.instance.collection('users').where('status', isEqualTo: 'pending').get();
        final pendingUsers = usersSnap.size;
        // pending user_pois
        int pendingUserPois = 0;
        try {
          final upSnap = await FirebaseFirestore.instance.collection('user_pois').where('status', isEqualTo: 'pending').get();
          pendingUserPois = upSnap.size;
        } catch (_) {
          pendingUserPois = 0;
        }
        // pending reviews under pdis_v2 (collectionGroup) - client may have access
        int pendingReviews = 0;
        try {
          final reviewsSnap = await FirebaseFirestore.instance.collectionGroup('reviews').where('status', isEqualTo: 'pending').get();
          pendingReviews = reviewsSnap.docs.where((d) => d.reference.path.startsWith('pdis_v2/')).length;
        } catch (_) {
          pendingReviews = 0;
        }
        setState(() {
          _pendingUsers = pendingUsers;
          _pendingUserPois = pendingUserPois;
          _pendingReviews = pendingReviews;
        });
      } catch (e) {
        // ignore fallback errors
        debugPrint('Fallback admin summary queries failed: $e');
      }
    }
    try {
      final routesSnap = await FirebaseFirestore.instance.collection('user_routes').where('approved', isEqualTo: false).where('needsApproval', isEqualTo: true).get();
      setState(() {
        _pendingRoutes = routesSnap.size;
      });
    } catch (_) {
      // ignore
    }
  }
  Timer? _refreshTimer;

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        backgroundColor: Colors.red[800],
        actions: [
          IconButton(onPressed: _loadAdminSummary, icon: const Icon(Icons.refresh)),
          if (_totalPending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 12.0, top: 10.0, bottom: 10.0),
              child: CircleAvatar(radius: 16, backgroundColor: Colors.white, child: Text(_totalPending > 99 ? '99+' : _totalPending.toString(), style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold))),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            // allow children to size naturally; logo can shrink if space is limited
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: Image.asset(
                    'assets/images/logo.png',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            // Compact grid of admin actions (icon tiles) for a mobile-like layout
            // Make the grid expand and scroll if needed to avoid bottom overflow
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemBuilder: (ctx, index) {
                  switch (index) {
                    case 0:
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.red[50], child: Icon(Icons.manage_accounts, color: Colors.red[800])),
                          title: const Text('Gestionar Usuarios'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManageUsersScreen())),
                        ),
                      );
                    case 1:
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.red[50], child: Icon(Icons.person_add_alt_1, color: Colors.red[800])),
                          title: const Text('Aprobar Usuarios'),
                          trailing: _pendingUsers > 0 ? CircleAvatar(radius: 14, backgroundColor: Colors.red, child: Text(_pendingUsers > 99 ? '99+' : _pendingUsers.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))) : null,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserApprovalScreen())),
                        ),
                      );
                    case 2:
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.red[50], child: Icon(Icons.person_add, color: Colors.red[800])),
                          title: const Text('Crear Usuario'),
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateUserScreen())),
                        ),
                      );
                    case 3:
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.red[50], child: Icon(Icons.check_circle, color: Colors.red[800])),
                          title: const Text('Aprobar PDIs'),
                          trailing: _pendingUserPois > 0 ? CircleAvatar(radius: 14, backgroundColor: Colors.red, child: Text(_pendingUserPois > 99 ? '99+' : _pendingUserPois.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))) : null,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PoiApprovalScreen())),
                        ),
                      );
                    case 4:
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.red[50], child: Icon(Icons.check_circle_outline, color: Colors.red[800])),
                          title: const Text('Aprobar Rutas'),
                          trailing: _pendingRoutes > 0 ? CircleAvatar(radius: 14, backgroundColor: Colors.red, child: Text(_pendingRoutes > 99 ? '99+' : _pendingRoutes.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))) : null,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminRoutesReviewScreen())),
                        ),
                      );
                    case 5:
                    default:
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.red[50], child: Icon(Icons.rate_review, color: Colors.red[800])),
                  title: const Text('Aprobar Valoraciones'),
                  // Show a numeric badge only when there are pending reviews.
                  // Previously we showed an error icon when the server-side
                  // callable failed which rendered as a '!' in a circle; this
                  // was confusing. Prefer to simply hide the trailing widget
                  // when there are no pending reviews.
                  trailing: _pendingReviews > 0
                    ? CircleAvatar(radius: 14, backgroundColor: Colors.red, child: Text(_pendingReviews > 99 ? '99+' : _pendingReviews.toString(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)))
                    : null,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReviewApprovalScreen())),
                        ),
                      );
                  }
                },
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: 6,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
  // ...previously used grid tile helper removed after redesign to list view
}
