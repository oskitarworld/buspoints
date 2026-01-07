// Clean single-definition AppDrawer
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:myapp/screens/profile_screen.dart';
import 'package:myapp/screens/home_screen.dart';
import 'package:myapp/screens/admin_panel_screen.dart';
import 'package:rxdart/rxdart.dart';
import 'package:myapp/screens/terms_of_use_screen.dart';
import 'package:myapp/widgets/branding_block.dart';
import 'package:myapp/screens/create_route_screen.dart';
import 'package:myapp/services/route_service.dart';
import 'package:myapp/models/user_route.dart';
import 'package:myapp/screens/community_routes_screen.dart';
import 'package:myapp/screens/private_routes_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:myapp/screens/privacy_policy_screen.dart';
import 'package:myapp/screens/how_it_works_screen.dart';
import 'package:myapp/widgets/contact_dialog.dart';
import 'package:myapp/services/firestore_web_compat.dart';

import '../screens/user_messages_received_screen.dart';
import '../screens/user_messages_sent_screen.dart';
import '../screens/admin_inbox_screen.dart';
import '../screens/admin_incidencias_screen.dart';
import '../screens/admin_mass_email_screen.dart';
import '../screens/admin_pushes_sent_screen.dart';
import '../screens/admin/security_events_screen.dart';
import '../screens/company_employees_screen.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  // stored for future use in the drawer footer (kept to avoid repeated
  // package_info calls). Currently BrandingBlock shows the app version.
  // ignore: unused_field
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
    _resolvedCompanyNames = {};
    _companyOwners = {};
  }

  // Cache for company owner UIDs (companyId -> ownerUid|null)
  Map<String, String?> _companyOwners = {};

  Future<void> _ensureCompanyOwner(String companyId) async {
  if (_companyOwners.containsKey(companyId)) return;
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('getCompanyOwners');
      final res = await callable.call({'companyIds': [companyId]});
      final data = res.data as Map<String, dynamic>? ?? {};
  final owners = data['owners'] as Map<String, dynamic>? ?? {};
  final owner = owners[companyId];
  _companyOwners[companyId] = owner?.toString();
      if (mounted) setState(() {});
      return;
    } catch (_) {
      // Fallback: leave as unknown (null) so we don't show management UI.
      _companyOwners[companyId] = null;
      if (mounted) setState(() {});
    }
  }

  // Cache for server-resolved company display names (id -> name)
  Map<String, String> _resolvedCompanyNames = {};

  // Live badge stream for inbox counts for a given user UID. Uses the same
  // client-side logic as the messages screen: treat `read != true` as unread
  // and ignore messages soft-deleted by the recipient.
  Widget _inboxLiveBadge(String uid) {
    return StreamBuilder<int>(
      stream: resilientStream(
        querySnapshotsCompat(FirebaseFirestore.instance.collection('user_messages').where('toUid', isEqualTo: uid))
            .map((snap) => snap.docs.where((d) {
                  final m = d.data();
                  if (m['deletedByRecipient'] != null) return false;
                  return m['read'] != true;
                }).length),
        name: 'drawer_inbox_live_$uid'),
      builder: (context, s) {
        final count = (s.hasData && s.data != null) ? s.data! : 0;
        return count > 0 ? _smallBadge(count > 9 ? '9+' : '$count') : const SizedBox.shrink();
      },
    );
  }

  /// Poll the server-side callable `getAdminInbox` to obtain admin-only
  /// message counts. We poll periodically because client-side Firestore
  /// listens may be rejected by security rules for admin-only collections.
  // ...existing code...

  // Poll the server-side callable `getAdminSummary` to obtain all admin counts
  // in one call (avoids client-side Firestore reads which may be denied).
  Stream<Map<String, int>> _pollAdminSummary() {
    final controller = StreamController<Map<String, int>>();
    Timer? timer;

    Future<void> fetchAndAdd() async {
      try {
        final functions = FirebaseFunctions.instance;
        final callable = functions.httpsCallable('getAdminSummary');
        final result = await callable.call();
        final data = result.data as Map<String, dynamic>? ?? {};
        final mapped = <String, int>{
          'pendingUsers': (data['pendingUsers'] as int?) ?? 0,
          'pendingPdis': (data['pendingPdis'] as int?) ?? 0,
          'pendingUserPois': (data['pendingUserPois'] as int?) ?? 0,
          'pendingReviews': (data['pendingReviews'] as int?) ?? 0,
          'systemNotifications': (data['systemNotifications'] as int?) ?? 0,
          'contactMessages': (data['contactMessages'] as int?) ?? 0,
          'userMessages': (data['userMessages'] as int?) ?? 0,
          'incidencias': (data['incidencias'] as int?) ?? 0,
        };
        controller.add(mapped);
        // Defensive client-side checks: if there are no message counts from
        // the callable, try to compute unread counts from client-visible
        // documents so admins still see the inbox badge when possible.
        try {
          final reportedMsgs = (mapped['contactMessages'] ?? 0) + (mapped['userMessages'] ?? 0);
          if (reportedMsgs == 0) {
            int contactUnread = 0;
            try {
              final cs = await FirebaseFirestore.instance.collection('contact_messages').get();
              contactUnread = cs.docs.where((d) {
                final m = d.data();
                if (m['isIncidencia'] == true) return false;
                if (m['pdiId'] != null) return false;
                if (m['motivo'] != null) return false;
                return m['read'] != true;
              }).length;
            } catch (_) {
              contactUnread = 0;
            }
            int userUnread = 0;
            try {
              final us = await FirebaseFirestore.instance.collection('user_messages').get();
              userUnread = us.docs.where((d) {
                final m = d.data();
                // Exclude messages soft-deleted by the recipient
                if (m['deletedByRecipient'] != null) return false;
                return m['read'] != true;
              }).length;
            } catch (_) {
              userUnread = 0;
            }
            final totalMsgs = contactUnread + userUnread;
            if (totalMsgs > 0) {
              final updated = Map<String,int>.from(mapped);
              updated['contactMessages'] = contactUnread;
              updated['userMessages'] = userUnread;
              controller.add(updated);
            }
          }
        } catch (_) {
          // ignore fallback errors
        }
        // Defensive client-side check: if the callable reports zero pending
        // reviews, do a lightweight collectionGroup check and emit an update
        // if we discover pending reviews visible to the client. This helps
        // when the callable is stale or misses items due to App Check timing.
        try {
          if ((mapped['pendingReviews'] ?? 0) == 0) {
            final rs = await FirebaseFirestore.instance.collectionGroup('reviews').where('status', isEqualTo: 'pending').get();
            final clientPending = rs.docs.where((d) => d.reference.path.startsWith('pdis_v2/')).length;
            if (clientPending > 0) {
              final updated = Map<String,int>.from(mapped);
              updated['pendingReviews'] = clientPending;
              // update the controller so listeners (drawer) see the badge
              controller.add(updated);
            }
          }
        } catch (_) {
          // ignore client fallback errors
        }
      } catch (e) {
        // Callable failed (App Check / permissions). Fall back to client-side queries where possible.
        try {
          final firestore = FirebaseFirestore.instance;
          // pending users
          int pendingUsers = 0;
          try {
            final us = await firestore.collection('users').where('status', isEqualTo: 'pending').get();
            pendingUsers = us.size;
          } catch (_) {
            pendingUsers = 0;
          }
          // pending pdis
          int pendingPdis = 0;
          try {
            final ps = await firestore.collection('pdis_v2').where('status', isEqualTo: 'pending').get();
            pendingPdis = ps.size;
          } catch (_) {
            pendingPdis = 0;
          }
          // pending user_pois
          int pendingUserPois = 0;
          try {
            final ups = await firestore.collection('user_pois').where('status', isEqualTo: 'pending').get();
            pendingUserPois = ups.size;
          } catch (_) {
            pendingUserPois = 0;
          }
          // pending reviews under pdis_v2
          int pendingReviews = 0;
          try {
            final rs = await firestore.collectionGroup('reviews').where('status', isEqualTo: 'pending').get();
            pendingReviews = rs.docs.where((d) => d.reference.path.startsWith('pdis_v2/')).length;
          } catch (_) {
            pendingReviews = 0;
          }
          // system notifications
          int systemNotifications = 0;
          try {
            final sn = await firestore.collection('system_notifications').where('read', isEqualTo: false).get();
            systemNotifications = sn.size;
          } catch (_) {
            systemNotifications = 0;
          }
          final mapped = <String, int>{
            'pendingUsers': pendingUsers,
            'pendingPdis': pendingPdis,
            'pendingUserPois': pendingUserPois,
            'pendingReviews': pendingReviews,
            'systemNotifications': systemNotifications,
            'contactMessages': 0,
            'userMessages': 0,
            'incidencias': 0,
          };
          controller.add(mapped);
        } catch (_) {
          try { controller.add(<String,int>{}); } catch (_) {}
        }
      }
    }

    controller.onListen = () {
      fetchAndAdd();
      timer = Timer.periodic(const Duration(seconds: 30), (_) => fetchAndAdd());
    };
    controller.onCancel = () {
      timer?.cancel();
    };
    return controller.stream;
  }

// admin PDI review screen removed from drawer; related stream helper removed as unused.

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
  final v = info.version;
  final b = info.buildNumber;
      setState(() {
        _appVersion = v.isNotEmpty ? (b.isNotEmpty ? 'v$v+$b' : 'v$v') : '';
      });
    } catch (e) {
      // ignore - leave _appVersion empty and fall back to hardcoded
    }
  }

  // Small local badge so we don't depend on an external package or a newer
  // Flutter SDK Badge widget. Keeps a compact circular red badge with white text.
  Widget _smallBadge(String label, {Color backgroundColor = Colors.red, Color textColor = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      // Conservative bounds: keep badge compact but allow up to ~56px when the
      // label is longer (we show an ellipsis). This prevents extremely wide
      // badges when the label becomes unexpectedly long.
      constraints: const BoxConstraints(minWidth: 20, minHeight: 18, maxWidth: 56, maxHeight: 22),
      child: Center(
        child: Text(
          label,
          style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final navigator = Navigator.of(context);
    final didRequestSignOut = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirmar Cierre de Sesión'),
          content: const Text('¿Estás seguro de que quieres cerrar la sesión?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );
    if (didRequestSignOut == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthScreen(), settings: const RouteSettings(name: '/auth')),
        (Route<dynamic> route) => false,
      );
    }
  }

  void _navigateToHome(BuildContext context) {
    Navigator.pop(context);
    if (ModalRoute.of(context)?.settings.name != '/home') {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen(), settings: const RouteSettings(name: '/home')),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Drawer();
    }
    return Drawer(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>> (
        stream: resilientStream(FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(), name: 'app_drawer_user_doc'),
        builder: (context, snapshot) {
          String? userName = user.email;
          String? role;
          final Map<String, dynamic> userData = (snapshot.connectionState == ConnectionState.active && snapshot.hasData) ? (snapshot.data?.data() ?? {}) : {};
          if (userData.isNotEmpty) {
            userName = userData['name'] ?? user.email;
            role = userData['role'];
          }
          // Compute a lightweight list of companies the user is associated
          // with for use in drawer shortcuts. We prefer names available in
          // the user document to avoid extra Firestore reads here.
          final List<Map<String, String>> userCompanies = [];
          try {
            List<String> cids = [];
            if (userData['companyIds'] is List) {
              cids = (userData['companyIds'] as List).map((e) => e.toString()).toList();
            } else if (userData['companyId'] != null) {
              cids = [userData['companyId'].toString()];
            }
            for (final cid in cids) {
              String cname = cid;
              try {
                if (userData['companyNames'] is Map && (userData['companyNames'] as Map)[cid] != null) {
                  cname = (userData['companyNames'] as Map)[cid].toString();
                } else if (userData['companies'] is List) {
                  for (final item in (userData['companies'] as List)) {
                    if (item is Map && (item['id']?.toString() == cid || item['companyId']?.toString() == cid)) {
                      final cand = item['name'] ?? item['companyName'] ?? item['displayName'];
                      if (cand != null) { cname = cand.toString(); break; }
                    }
                  }
                } else if ((userData['companyName'] ?? userData['company']) != null && cids.length == 1) {
                  cname = (userData['companyName'] ?? userData['company']).toString();
                }
              } catch (_) {}
              // Prefer a server-resolved name when available in cache
              final cached = _resolvedCompanyNames[cid];
              userCompanies.add({'id': cid, 'name': cached ?? cname});
            }
          } catch (_) {}

          // If any company id still looks like an id (no readable name),
          // request server-side names via the callable (only once per id).
          // Use a post-frame callback so we don't trigger async work during
          // the build synchronous phase.
          final idsNeeding = <String>[];
          for (final c in userCompanies) {
            final nid = c['id'] ?? '';
            final nname = c['name'] ?? '';
            // Heuristic: ids are long alphanumeric strings; if name equals id
            // we probably need a server resolution.
            if (nid.isNotEmpty && (nname == nid) && !_resolvedCompanyNames.containsKey(nid)) idsNeeding.add(nid);
          }
          if (idsNeeding.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              try {
                final functions = FirebaseFunctions.instance;
                final callable = functions.httpsCallable('getCompanyNames');
                final res = await callable.call({'companyIds': idsNeeding});
                final data = res.data as Map<String, dynamic>? ?? {};
                if (data['names'] is Map) {
                  final Map names = data['names'];
                  bool changed = false;
                  names.forEach((k, v) {
                    final ks = k.toString();
                    final vs = v?.toString() ?? ks;
                    if (_resolvedCompanyNames[ks] != vs) {
                      _resolvedCompanyNames[ks] = vs;
                      changed = true;
                    }
                  });
                  if (changed && mounted) setState(() {});
                }
              } catch (_) {
                // ignore callable failure; keep fallbacks
              }
            });
          }
          // Resolve company owner UIDs for companies listed in the drawer so
          // we can accurately determine if the current user is the true owner.
          final idsNeedOwner = <String>[];
          for (final c in userCompanies) {
            final cid = c['id'] ?? '';
            if (cid.isNotEmpty && !_companyOwners.containsKey(cid)) idsNeedOwner.add(cid);
          }
          if (idsNeedOwner.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              for (final cid in idsNeedOwner) {
                _ensureCompanyOwner(cid);
              }
            });
          }
          // If the user represents a company account (role == 'company') but
          // no company ids were detected, add a quick entry using the user's
          // own uid as the company id so owner accounts can see 'Rutas de mi empresa'.
          try {
            if ((role == 'company' || userData['role'] == 'company') && userCompanies.isEmpty) {
              final cname = (userData['companyName'] ?? userData['company'] ?? userData['name'] ?? 'Mi empresa').toString();
              userCompanies.insert(0, {'id': user.uid, 'name': cname});
            }
          } catch (_) {}
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(
                  userName ?? 'Cargando...',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                accountEmail: Text(user.email ?? ''),
                currentAccountPicture: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    userName?.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold),
                  ),
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Mapa'),
                onTap: () => _navigateToHome(context),
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Perfil'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  );
                },
              ),

              if (role == 'admin') ...[
                StreamBuilder<Map<String, int>>(
                  stream: resilientStream(_pollAdminSummary(), name: 'app_drawer_admin_summary'),
                  builder: (context, snapshot) {
                    final data = snapshot.hasData ? snapshot.data! : <String,int>{};
                    final int pendingUsers = data['pendingUsers'] ?? 0;
                    final int contactMessages = data['contactMessages'] ?? 0;
                    final int userMessages = data['userMessages'] ?? 0;
                    final int pendingUserPois = data['pendingUserPois'] ?? 0;
                    final int pendingReviews = data['pendingReviews'] ?? 0;
                    final int systemNotifications = data['systemNotifications'] ?? 0;
                    final int totalMessages = contactMessages + userMessages;
                    final totalPending = pendingUsers + totalMessages + pendingUserPois + pendingReviews + systemNotifications;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.admin_panel_settings),
                          title: const Text('Panel de administración'),
                          trailing: totalPending > 0 ? _smallBadge(totalPending > 9 ? '9+' : '$totalPending') : null,
                          onTap: () {
                            // Directly navigate to the admin panel (remove the summary popup per UX request)
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminPanelScreen()));
                          },
                        ),

                        ExpansionTile(
                          leading: const Icon(Icons.mail),
                          title: const Text('Mensajes'),
                          children: [
                            ListTile(
                              leading: const Icon(Icons.inbox),
                              title: const Text('Bandeja de entrada'),
                              trailing: _inboxLiveBadge(user.uid),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const AdminInboxScreen()),
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.send),
                              title: const Text('Mensajes enviados'),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const UserMessagesSentScreen()),
                                );
                              },
                            ),
                            // Incidencias (separate admin mailbox)
                            StreamBuilder<int>(
                              stream: resilientStream(queryCountStream(FirebaseFirestore.instance.collection('incidencias').where('read', isEqualTo: false)), name: 'drawer_incidencias_count'),
                              builder: (context, snap) {
                                final int unread = snap.hasData ? snap.data! : 0;
                                return ListTile(
                                  leading: const Icon(Icons.report_problem_outlined),
                                  title: const Text('Incidencias'),
                                  trailing: unread > 0 ? _smallBadge(unread > 99 ? '99+' : '$unread') : null,
                                  onTap: () {
                                    Navigator.pop(context);
                                    Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminIncidenciasScreen()));
                                  },
                                );
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.campaign_outlined),
                              title: const Text('Enviados (push)'),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const AdminPushesSentScreen()),
                                );
                              },
                            ),
                            // 'Notificaciones del sistema' removed from this
                            // admin messages accordion per UX request. The
                            // system notifications entry is available elsewhere
                            // in the admin UI.
                            ListTile(
                              leading: const Icon(Icons.block, color: Colors.redAccent),
                              title: const Text('Cuentas bloqueadas / Seguridad'),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const SecurityEventsScreen()));
                              },
                            ),
                            // 'Revisión PDIs (Admin)' removed per UX request
                            // 'Revisión Rutas', 'Crear ruta' and 'Rutas de la comunidad'
                            // removed from the admin messages accordion per UX request.
                            // These actions exist elsewhere in the drawer layout.
                            // 'Mis rutas' removed from this admin messages submenu per UX request
                            ListTile(
                              leading: const Icon(Icons.mark_email_unread_outlined),
                              title: const Text('Enviar email masivo'),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminMassEmailScreen()));
                              },
                            ),
                          ],
                        ),
                        // Separate Rutas block for admins in the main drawer as requested
                        const Divider(),
                        ListTile(
                          leading: const Icon(Icons.alt_route),
                          title: const Text('Crear ruta'),
                          subtitle: const Text('Selecciona POIs en el mapa y guarda tu ruta'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateRouteScreen()));
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.people_alt_outlined),
                          title: const Text('Rutas de la comunidad'),
                          subtitle: const Text('Explora rutas públicas creadas por otros usuarios'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const CommunityRoutesScreen()));
                          },
                        ),
                        // If the admin user represents one or more companies (or
                        // has been invited), show quick links to view routes for
                        // each company directly. We prefer names from the user
                        // doc when available to avoid extra reads.
                if (userCompanies.isNotEmpty)
                  Column(
                    children: userCompanies.map((c) {
                      final cid = c['id'] ?? '';
                      final cname = c['name'] ?? cid;
                      // Determine if current user is the owner: heuristic
                      // If the user represents the company account (role == 'company' and id == uid)
                      // we'll consider them the owner. For more accurate checks we could
                      // fetch the company doc ownerUid, but keep this lightweight here.
                      final ownerUid = _companyOwners[cid];
                      final bool likelyOwner = (ownerUid != null && ownerUid == user.uid) || (role == 'company' && cid == user.uid);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            leading: const Text('🚌', style: TextStyle(fontSize: 20)),
                            title: Text('Rutas de $cname'),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (context) => CommunityRoutesScreen(companyId: cid, companyName: cname)));
                            },
                          ),
                          // Recent routes stream (limited to 5) for this company. We show
                          // a compact list; editing/deleting only visible when likelyOwner.
                          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                            stream: resilientStream(
                              FirebaseFirestore.instance.collection('user_routes')
                                  .where('ownerCompanyId', isEqualTo: cid)
                                  .orderBy('createdAt', descending: true)
                                  .limit(5)
                                  .snapshots(),
                              name: 'drawer_company_routes_$cid'),
                            builder: (context, snap) {
                              if (!snap.hasData) return const SizedBox.shrink();
                              final docs = snap.data!.docs;
                              if (docs.isEmpty) return const SizedBox.shrink();
                              return Column(
                                children: docs.map((d) {
                                  final ur = UserRoute.fromDoc(d);
                                  return ListTile(
                                    dense: true,
                                    visualDensity: VisualDensity.compact,
                                    contentPadding: const EdgeInsets.only(left: 72.0, right: 8.0),
                                    title: Text(ur.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (likelyOwner) IconButton(
                                          icon: const Icon(Icons.edit, size: 20),
                                          tooltip: 'Editar',
                                          onPressed: () async {
                                            final navigator = Navigator.of(context);
                                            navigator.pop();
                                            final res = await navigator.push<bool?>(MaterialPageRoute(builder: (ctx) => CreateRouteScreen(routeToEdit: ur)));
                                            if (res == true && mounted) setState(() {});
                                          },
                                        ),
                                        if (likelyOwner) IconButton(
                                          icon: const Icon(Icons.delete, size: 20, color: Colors.redAccent),
                                          tooltip: 'Eliminar',
                                          onPressed: () async {
                                            final messenger = ScaffoldMessenger.of(context);
                                            final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
                                              title: const Text('Eliminar ruta'),
                                              content: const Text('¿Eliminar esta ruta de la empresa? Esta acción no se puede deshacer.'),
                                              actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Eliminar'))],
                                            ));
                                            if (ok == true) {
                                              try {
                                                final rs = RouteService();
                                                await rs.deleteRoute(ur.id, ownerCompanyId: cid);
                                                if (!mounted) return;
                                                messenger.showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
                                                setState(() {});
                                              } catch (e) {
                                                if (!mounted) return;
                                                messenger.showSnackBar(SnackBar(content: Text('No se pudo eliminar la ruta: $e')));
                                              }
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.chevron_right, size: 20),
                                          onPressed: () {
                                            Navigator.pop(context);
                                            Navigator.push(context, MaterialPageRoute(builder: (_) => CommunityRoutesScreen(companyId: cid, companyName: cname)));
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                        if (role == 'company')
                          ListTile(
                            leading: const Icon(Icons.group),
                            title: const Text('Gestión de empleados'),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const CompanyEmployeesScreen()));
                            },
                          ),
                        // 'Mis rutas' removed from admin routes block per UX request
                        // 'Aprobar rutas' moved into Admin Panel per UX request
                      ],
                    );
                  },
                ),
              ] else ...[
                const Divider(),
                // For regular users show live badges for unread messages and
                // system notifications. We combine two snapshot streams so the
                // badge updates live without extra client logic.
                StreamBuilder<List<int>>(
                  // For regular users also wrap both count streams defensively.
                  stream: Rx.combineLatest2<int, int, List<int>>(
                    // Use a snapshots-based stream so we can count messages where
                    // the `read` field is missing (treat as unread). Some older
                    // messages may not have an explicit `read: false` value; the
                    // messages UI treats `read != true` as unread, so the drawer
                    // must mirror that behavior.
                    resilientStream(
                      querySnapshotsCompat(FirebaseFirestore.instance.collection('user_messages').where('toUid', isEqualTo: user.uid))
                          .map((snap) => snap.docs.where((d) {
                            final m = d.data();
                            // Exclude messages soft-deleted by the recipient
                            if (m['deletedByRecipient'] != null) return false;
                            return m['read'] != true;
                          }).length),
                      name: 'app_drawer_unread_msgs'),
                    resilientStream(queryCountStream(FirebaseFirestore.instance.collection('users').doc(user.uid).collection('notifications').where('read', isEqualTo: false)), name: 'app_drawer_unread_system'),
                    (unreadMsgs, unreadSystem) => [unreadMsgs, unreadSystem],
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      // Debug: log computed message counts so we can trace why
                      // the badge might not be appearing on some devices.
                      debugPrint('AppDrawer: unreadMsgs=${snapshot.data![0]}, unreadSystem=${snapshot.data![1]}');
                    }
                    return ExpansionTile(
                      leading: const Icon(Icons.mail),
                      title: const Text('Mensajes'),
                      children: [
                        // Rutas quick actions moved below 'Mensajes'/'Contactar con Administradores'
                        // into their own separated block to improve discoverability.
                        ListTile(
                          leading: const Icon(Icons.inbox),
                          title: const Text('Recibidos'),
                          trailing: _inboxLiveBadge(user.uid),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const UserMessagesReceivedScreen(),
                              ),
                            );
                          },
                        ),
                        // For regular users keep order: Recibidos, Enviados, Notificaciones
                        ListTile(
                          leading: const Icon(Icons.send),
                          title: const Text('Enviados'),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const UserMessagesSentScreen(),
                              ),
                            );
                          },
                        ),
                        // 'Notificaciones del sistema' removed for regular users
                        // (the system notifications are still available to admins
                        // via the admin panel). Keeping this out of the user
                        // messages menu avoids confusion/bandwidth for normal users.
                      ],
                    );
                  },
                ),
                // Botón para contactar con administradores
                ListTile(
                  leading: const Icon(Icons.mail_outline, color: Colors.blue),
                  title: const Text('Contactar con Administradores'),
                  subtitle: const Text('Envía un mensaje al equipo', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    Navigator.pop(context);
                    showContactDialog(context);
                  },
                ),
                // Inserted: Rutas block (separated by dividers) — placed below
                // 'Mensajes' / 'Contactar con Administradores' and above the
                // legal information section as requested.
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.alt_route),
                  title: const Text('Crear ruta'),
                  subtitle: const Text('Selecciona POIs en el mapa y guarda tu ruta'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateRouteScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people_alt_outlined),
                  title: const Text('Rutas de la comunidad'),
                  subtitle: const Text('Explora rutas públicas creadas por otros usuarios'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const CommunityRoutesScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Rutas privadas'),
                  subtitle: const Text('Tus rutas privadas (solo visibles por ti)'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const PrivateRoutesScreen()));
                  },
                ),
                if (userCompanies.isNotEmpty)
                  Column(
                    children: userCompanies.map((c) => ListTile(
                      leading: const Text('🚌', style: TextStyle(fontSize: 20)),
                      title: Text('Rutas de ${c['name']}'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => CommunityRoutesScreen(companyId: c['id'], companyName: c['name'])));
                      },
                    )).toList(),
                  ),
                if (role == 'company')
                  ListTile(
                    leading: const Icon(Icons.group),
                    title: const Text('Gestión de empleados'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const CompanyEmployeesScreen()));
                    },
                  ),
                // 'Mis rutas' removed from main user block per UX request
                // End rutas block
                // Bloque de información legal
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Términos de Uso'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TermsOfUseScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Política de Privacidad'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline, color: Colors.blueGrey),
                  title: const Text('¿Cómo funciona?'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HowItWorksScreen()),
                    );
                  },
                ),
                // ...existing code...
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.recommend_outlined),
                  title: const Text('Recomiéndanos'),
                  onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final Uri wa = Uri.parse('https://wa.me/?text=Te%20recomiendo%20BusPoints,%20una%20app%20para%20encontrar%20PDIs%20y%20paradas%20por%20Europa.%20https://buspoints.net');
                      try {
                        final launched = await launchUrl(wa, mode: LaunchMode.externalApplication);
                        if (!launched) {
                          // fallback to native share sheet
                          await SharePlus.instance.share(ShareParams(text: 'Te recomiendo BusPoints, una app para encontrar PDIs y paradas por Europa. https://buspoints.net'));
                        }
                      } catch (e) {
                        // fallback to native share sheet
                        try {
                          await SharePlus.instance.share(ShareParams(text: 'Te recomiendo BusPoints, una app para encontrar PDIs y paradas por Europa. https://buspoints.net'));
                        } catch (_) {
                          messenger.showSnackBar(SnackBar(content: Text('Error abriendo WhatsApp: $e')));
                        }
                      }
                    },
                ),
              ],
              const Divider(),
              // Branding block (logo + version + byline)
              // Use the reusable BrandingBlock widget so the UI stays consistent.
              const BrandingBlock(),
              // ... no extra red separator here per design
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red)),
                onTap: () => _confirmSignOut(context),
              ),
              const SizedBox(height: 20),
              const SizedBox(height: 10),
            ],
          );
        },
      ),
    );
  }

}
