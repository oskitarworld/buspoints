// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:myapp/services/firestore_web_compat.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:myapp/utils/marker_utils.dart';
// package:rxdart was used for merging streams in the old 'Añadidos' tab.
// That tab was removed; keep this file free of unused imports.
import 'package:myapp/models/user_model.dart'; // Import the updated model
import 'package:myapp/models/user_route.dart';
import 'package:myapp/screens/approved_pois_screen.dart';
import 'package:myapp/screens/edit_route_points_screen.dart';


class ProfileScreen extends StatefulWidget {
  /// initialInnerTabIndex: when opening Profile from other screens we may
  /// want to focus the inner tab (e.g. 'Mis rutas' at index 3). Defaults to 0.
  const ProfileScreen({super.key, this.initialInnerTabIndex = 0});

  final int initialInnerTabIndex;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // --- MÉTODOS DE VALORACIONES (antes de build) ---
  Widget _buildUserReviewsTab(BuildContext context, String uid, bool isAdmin) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection('reviews').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No tienes valoraciones.'));
        }
        final reviews = snapshot.data!.docs;
        return ListView.builder(
          itemCount: reviews.length,
          itemBuilder: (context, index) {
            final review = reviews[index];
            final data = review.data();
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: Icon(Icons.star, color: Colors.amber[700]),
                title: Text(data['comment'] ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [const Icon(Icons.star, size: 16, color: Colors.amber), const SizedBox(width: 4), Text(data['rating']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))]),
                    if (data['createdAt'] != null) Text('Fecha: ${data['createdAt'] is Timestamp ? (data['createdAt'] as Timestamp).toDate().toString().substring(0, 16) : data['createdAt'].toString()}'),
                    if (data['status'] != null) Padding(padding: const EdgeInsets.only(top: 6.0), child: Text('Estado: ${data['status']}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Editar', onPressed: () => _showEditReviewDialog(context, review)),
                    if (isAdmin) IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: 'Borrar', onPressed: () => _deleteReview(context, review)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditReviewDialog(BuildContext context, QueryDocumentSnapshot review) {
    final data = review.data() as Map<String, dynamic>;
    final controller = TextEditingController(text: data['comment'] ?? '');
    final ratingController = TextEditingController(text: data['rating']?.toString() ?? '');
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar valoración'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Comentario'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: ratingController,
              decoration: const InputDecoration(labelText: 'Puntuación (1-5)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final dialogNavigator = Navigator.of(ctx);
              final newComment = controller.text.trim();
              final newRating = int.tryParse(ratingController.text.trim()) ?? data['rating'];
              // Close the edit dialog first, then perform updates in background.
              dialogNavigator.pop();
              // Update mirrored review document
              await review.reference.update({'comment': newComment, 'rating': newRating});
              // Also try to update canonical review under pdis_v2/<pdiId>/reviews/<id>
              try {
                final pdiId = data['pdiId'] ?? data['pdiId'];
                if (pdiId != null) {
                  final canonRef = FirebaseFirestore.instance.collection('pdis_v2').doc(pdiId.toString()).collection('reviews').doc(review.id);
                  final canonSnap = await canonRef.get();
                  if (canonSnap.exists) {
                    await canonRef.update({'comment': newComment, 'rating': newRating});
                  }
                }
              } catch (_) {}
              if (!mounted) return;
              
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Valoración actualizada'),
                  content: const Text('Tu valoración ha sido actualizada.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                  ],
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _deleteReview(BuildContext context, QueryDocumentSnapshot review) async {
    final confirm = await showDialog<bool>(
    
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar valoración'),
        content: const Text('¿Seguro que quieres eliminar esta valoración?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        // Delete mirrored review
        await review.reference.delete();
      } catch (_) {}
      // Also try to delete canonical review under pdis_v2/<pdiId>/reviews/<id>
      try {
        final data = review.data() as Map<String, dynamic>;
        final pdiId = data['pdiId'];
        if (pdiId != null) {
          final canonRef = FirebaseFirestore.instance.collection('pdis_v2').doc(pdiId.toString()).collection('reviews').doc(review.id);
          final snap = await canonRef.get();
          if (snap.exists) await canonRef.delete();
        }
      } catch (_) {}
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Valoración eliminada'),
          content: const Text('La valoración ha sido eliminada.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
          ],
        ),
      );
    }
  }


  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showEditDialog(BuildContext context, String field, String value, String uid) {
    final controller = TextEditingController(text: value);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar ${field == 'email' ? 'Correo Electrónico' : 'Teléfono'}'),
        content: TextFormField(
          controller: controller,
          keyboardType: field == 'email' ? TextInputType.emailAddress : TextInputType.phone,
          decoration: InputDecoration(
            labelText: field == 'email' ? 'Correo Electrónico' : 'Teléfono',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final dialogNavigator = Navigator.of(ctx);
              final newValue = controller.text.trim();
              final usersRef = FirebaseFirestore.instance.collection('users');
              if (field == 'email') {
                final emailDup = await usersRef.where('email', isEqualTo: newValue).get();
                if (emailDup.docs.any((doc) => doc.id != uid)) {
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Correo duplicado'),
                      content: const Text('Ya existe una cuenta con ese correo electrónico'),
                      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))],
                    ),
                  );
                  return;
                }
              } else {
                final phoneDup = await usersRef.where('phone', isEqualTo: newValue).get();
                if (phoneDup.docs.any((doc) => doc.id != uid)) {
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Teléfono duplicado'),
                      content: const Text('Ya existe una cuenta con ese teléfono'),
                      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))],
                    ),
                  );
                  return;
                }
              }
              await usersRef.doc(uid).update({field: newValue});
              dialogNavigator.pop();
              if (!mounted) return;
              
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Datos actualizados'),
                  content: const Text('Tus datos han sido actualizados correctamente.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                  ],
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: const Center(child: Text('No has iniciado sesión.')),
      );
    }

    return DefaultTabController(
      length: 4,
      initialIndex: widget.initialInnerTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mi Perfil'),
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(icon: Icon(Icons.person), text: 'Perfil'),
              Tab(icon: Icon(Icons.place), text: 'Mis lugares'),
              Tab(icon: Icon(Icons.star), text: 'Valoraciones'),
              Tab(icon: Icon(Icons.emoji_events), text: 'Recompensas'),
            ],
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                  child: Text('No se pudo cargar el perfil.'));
            }

            final user = UserModel.fromFirestore(snapshot.data!);

            return TabBarView(
              children: [
                // PERFIL
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: <Widget>[
                              _buildProfileHeader(context, user),
                              const SizedBox(height: 12),
                              // If this user is a 'company' account, show an editable
                              // EMPRESA field so the company can set its public name.
                              if (user.role == 'company')
                                _buildCompanyNameEditor(context, snapshot.data!, user.uid),
                              const SizedBox(height: 12),
                              // Show company membership if present on user doc
                              _buildCompanyMembershipWidget(context, snapshot.data!),
                      const SizedBox(height: 32),
                      _buildMembershipCard(context, user),
                      const SizedBox(height: 24),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.email, color: Colors.blueGrey),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(user.email, style: const TextStyle(fontSize: 16)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Editar correo',
                                    onPressed: () => _showEditDialog(context, 'email', user.email, user.uid),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  const Icon(Icons.phone, color: Colors.blueGrey),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(user.phone, style: const TextStyle(fontSize: 16)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Editar teléfono',
                                    onPressed: () => _showEditDialog(context, 'phone', user.phone, user.uid),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildStatsCard(context, user.uid),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar Sesión'),
                      ),
                    ],
                  ),
                ),
                // MIS LUGARES
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildMyPlacesCard(context, user.uid),
                ),
                // VALORACIONES
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildUserReviewsTab(context, user.uid, user.role == 'admin'),
                ),
                // RECOMPENSAS
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildRewardsCard(context, user.uid),
                ),
              ],
            );
          },
        ),
      ),
    );
  // ...existing code...
  }

  Widget _buildProfileHeader(BuildContext context, UserModel user) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            user.name.isNotEmpty
                ? user.name.substring(0, 1).toUpperCase()
                : 'U',
            style: TextStyle(
                fontSize: 40,
                color: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 16),
        Text(user.name,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(user.email,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildCompanyNameEditor(BuildContext context, DocumentSnapshot userDoc, String uid) {
    final data = userDoc.data() as Map<String, dynamic>? ?? {};
    final initial = (data['companyName'] ?? data['name'] ?? '').toString();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('EMPRESA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.business, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(child: Text(initial.isNotEmpty ? initial : 'Nombre de la empresa', style: const TextStyle(fontSize: 16))),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'Editar nombre de la empresa',
                  onPressed: () async {
                    final controller = TextEditingController(text: initial);
                    final result = await showDialog<bool?>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Editar nombre de la empresa'),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(labelText: 'Nombre de la empresa'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar')),
                        ],
                      ),
                    );
                    if (result != true) return;
                    final newVal = controller.text.trim();
                    if (newVal.isEmpty) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El nombre de la empresa no puede estar vacío'), backgroundColor: Colors.red));
                      return;
                    }
                    try {
                      // Update both users/{uid} (company user profile) and companies/{uid} if exists
                      final batch = FirebaseFirestore.instance.batch();
                      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
                      batch.set(userRef, {'companyName': newVal, 'name': newVal}, SetOptions(merge: true));
                      final compRef = FirebaseFirestore.instance.collection('companies').doc(uid);
                      // attempt to update companies doc if present
                      final compSnap = await compRef.get();
                      if (compSnap.exists) {
                        batch.set(compRef, {'name': newVal, 'displayName': newVal}, SetOptions(merge: true));
                      }
                      await batch.commit();

                      // Propagate to employees subcollection (update companyName/companyDisplayName)
                      try {
                        final empCol = compRef.collection('employees');
                        final empSnap = await empCol.get();
                        int updated = 0;
                        if (empSnap.docs.isNotEmpty) {
                          // Firestore batch limit is 500; update in chunks
                          const int chunkSize = 400;
                          final docs = empSnap.docs;
                          for (var i = 0; i < docs.length; i += chunkSize) {
                            final batch2 = FirebaseFirestore.instance.batch();
                            final end = (i + chunkSize < docs.length) ? i + chunkSize : docs.length;
                            for (var j = i; j < end; j++) {
                              final dref = docs[j].reference;
                              batch2.set(dref, {'companyName': newVal, 'companyDisplayName': newVal}, SetOptions(merge: true));
                              updated++;
                            }
                            await batch2.commit();
                          }
                        }

                        // Also propagate to nested invited docs: companies/{cid}/employees_by_inviter/*/invited/*
                        try {
                          final invByRef = compRef.collection('employees_by_inviter');
                          final invitersSnap = await invByRef.get();
                          if (invitersSnap.docs.isNotEmpty) {
                            for (final inviterDoc in invitersSnap.docs) {
                              final invitedCol = inviterDoc.reference.collection('invited');
                              final invitedSnap = await invitedCol.get();
                              if (invitedSnap.docs.isEmpty) continue;
                              // update invited docs in chunks
                              final invitedDocs = invitedSnap.docs;
                              for (var i = 0; i < invitedDocs.length; i += 400) {
                                final batch3 = FirebaseFirestore.instance.batch();
                                final end = (i + 400 < invitedDocs.length) ? i + 400 : invitedDocs.length;
                                for (var j = i; j < end; j++) {
                                  final dref = invitedDocs[j].reference;
                                  batch3.set(dref, {'companyName': newVal, 'companyDisplayName': newVal}, SetOptions(merge: true));
                                  updated++;
                                }
                                await batch3.commit();
                              }
                            }
                          }
                        } catch (e) {
                          // swallow nested invites propagation errors; main update already done
                          debugPrint('Failed to propagate to employees_by_inviter: $e');
                        }

                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nombre actualizado y propagado a $updated documentos'), backgroundColor: Colors.green));
                      } catch (e) {
                        // If employees propagation fails, still succeed the main update
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nombre de empresa actualizado (no se pudo propagar por completo)'), backgroundColor: Colors.orange));
                      }

                      if (mounted) setState(() {}); // refresh UI to show new name
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar: $e'), backgroundColor: Colors.red));
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembershipCard(BuildContext context, UserModel user) {
    final bool isActive = user.isSubscriptionActive;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Membresía',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(isActive ? Icons.check_circle : Icons.cancel,
                    color: isActive ? Colors.green : Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(isActive ? 'Activa' : 'Vencida',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isActive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            const Text('Historial de Suscripción:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (user.subscriptionHistory.isEmpty)
              const Text('  • No hay registros de suscripción.')
            else
              ...user.subscriptionHistory.reversed.map((sub) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                        '  • ${_formatDate(sub.startDate)} a ${_formatDate(sub.endDate)}'),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanyMembershipWidget(BuildContext context, DocumentSnapshot userDoc) {
    final data = userDoc.data() as Map<String, dynamic>? ?? {};
    List<String> cids = [];
    if (data['companyIds'] is List) {
      cids = (data['companyIds'] as List).map((e) => e.toString()).toList();
    } else if (data['companyId'] != null) {
      cids = [data['companyId'].toString()];
    }

    if (cids.isEmpty) return const SizedBox.shrink();

    final String uid = userDoc.id;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: Future.wait(cids.map((cid) async {
        final Map<String, dynamic> result = {'id': cid, 'name': cid, 'inviterName': null, 'role': null, 'status': null};
        final compRef = FirebaseFirestore.instance.collection('companies').doc(cid);

        // Prefer users/{cid} companyName when present (some projects model companies as user docs)
        try {
          final userSnap = await FirebaseFirestore.instance.collection('users').doc(cid).get();
          if (userSnap.exists) {
            final ud = userSnap.data() ?? {};
            final unameCandidates = [ud['companyName'], ud['company_name'], ud['name'], ud['displayName'], ud['display_name']];
            for (final cand in unameCandidates) {
              if (cand != null) {
                final s = cand.toString().trim();
                if (s.isNotEmpty) {
                  result['name'] = s;
                  break;
                }
              }
            }
            if (result['name'] == cid) {
              String? firstStringUser(Map m, [int depth = 0]) {
                if (depth > 2) return null;
                for (final k in m.keys) {
                  final v = m[k];
                  if (v is String && v.trim().isNotEmpty) return v.trim();
                  if (v is Map) {
                    final nested = firstStringUser(v, depth + 1);
                    if (nested != null) return nested;
                  }
                }
                return null;
              }
              final found = firstStringUser(ud);
              if (found != null && found.isNotEmpty) result['name'] = found;
            }
          }
        } catch (_) {}

        // If still not resolved, check companies/{cid}
        try {
          final compSnap = await compRef.get();
          if (compSnap.exists) {
            final cd = compSnap.data() ?? {};
            // Prefer common fields that may contain the company display name
            final nameCandidates = [
              cd['name'],
              cd['displayName'],
              cd['companyName'],
              cd['display_name'],
              cd['title'],
              cd['displayname']
            ];
            for (final cand in nameCandidates) {
              if (cand != null) {
                final s = cand.toString().trim();
                if (s.isNotEmpty) {
                  result['name'] = s;
                  break;
                }
              }
            }

            // If still not found, search recursively for the first string field
            if (result['name'] == cid) {
              String? firstString(Map m, [int depth = 0]) {
                if (depth > 2) return null;
                for (final k in m.keys) {
                  final v = m[k];
                  if (v is String && v.trim().isNotEmpty) return v.trim();
                  if (v is Map) {
                    final nested = firstString(v, depth + 1);
                    if (nested != null) return nested;
                  }
                }
                return null;
              }
              try {
                final found = firstString(cd);
                if (found != null && found.isNotEmpty) result['name'] = found;
              } catch (_) {}
            }
          }
        } catch (_) {}

        // Read employee doc to get inviterName/role/status if available
        try {
          final empSnap = await compRef.collection('employees').doc(uid).get();
          if (empSnap.exists) {
            final ed = empSnap.data() ?? {};
            var inviterVal = (ed['inviterName'] ?? ed['invitedByName'] ?? ed['invitedBy']);
            if (inviterVal != null) {
              inviterVal = inviterVal.toString();
              // If inviterVal looks like a UID, try to resolve to a user name
              final isLikelyUid = RegExp(r"^[A-Za-z0-9_-]{12,}$");
              if (isLikelyUid.hasMatch(inviterVal)) {
                try {
                  final inviterSnap = await FirebaseFirestore.instance.collection('users').doc(inviterVal).get();
                  if (inviterSnap.exists) {
                    final idata = inviterSnap.data() ?? {};
                    inviterVal = (idata['name'] ?? idata['displayName'] ?? idata['companyName'])?.toString() ?? inviterVal;
                  }
                } catch (_) {}
              }
            }
            result['inviterName'] = inviterVal?.toString();
            result['role'] = ed['role']?.toString();
            result['status'] = ed['status']?.toString() ?? (ed['active'] == true ? 'active' : null);

            // If the company name is still unresolved (shows as CID/UID), try
            // to pick a readable name from the employee doc which may have been
            // backfilled by the server migration (invitedByCompanyName or companyName).
            final currentName = result['name']?.toString() ?? '';
            final looksLikeUid = RegExp(r"^[A-Za-z0-9_-]{12,}$");
            if (currentName == cid || looksLikeUid.hasMatch(currentName)) {
              final candidateFields = [ed['companyName'], ed['companyDisplayName'], ed['company'], ed['invitedByCompanyName']];
              for (final cand in candidateFields) {
                if (cand != null) {
                  final s = cand.toString().trim();
                  if (s.isNotEmpty) {
                    result['name'] = s;
                    break;
                  }
                }
              }
            }
          }
        } catch (_) {}

        // If the resolved company name is still just the CID or looks like a UID,
        // try a final direct fetch on users/{cid} to pick a readable field.
        try {
          final nameCandidate = result['name']?.toString() ?? '';
          final isLikelyUidName = RegExp(r"^[A-Za-z0-9_-]{12,}$");
          if (nameCandidate == cid || isLikelyUidName.hasMatch(nameCandidate)) {
            final retryUserSnap = await FirebaseFirestore.instance.collection('users').doc(cid).get();
            if (retryUserSnap.exists) {
              final rdata = retryUserSnap.data() ?? {};
              final unameCandidates = [rdata['companyName'], rdata['company_name'], rdata['name'], rdata['displayName'], rdata['display_name']];
              for (final cand in unameCandidates) {
                if (cand != null) {
                  final s = cand.toString().trim();
                  if (s.isNotEmpty) {
                    result['name'] = s;
                    break;
                  }
                }
              }
              if (result['name'] == cid) {
                // recursive search fallback
                String? firstStringUser(Map m, [int depth = 0]) {
                  if (depth > 2) return null;
                  for (final k in m.keys) {
                    final v = m[k];
                    if (v is String && v.trim().isNotEmpty) return v.trim();
                    if (v is Map) {
                      final nested = firstStringUser(v, depth + 1);
                      if (nested != null) return nested;
                    }
                  }
                  return null;
                }
                final found = firstStringUser(rdata);
                if (found != null && found.isNotEmpty) result['name'] = found;
              }
            }
          }
        } catch (_) {}

        return result;
      }).toList()),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final list = snap.data!;
        if (list.isEmpty) return const SizedBox.shrink();

        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pertenencia a empresa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ...list.map((c) {
                  final id = c['id'] as String? ?? '';
                  final name = c['name'] as String? ?? id;

                  return Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Text('🚌', style: TextStyle(fontSize: 22)),
                        title: Text(name),
                        trailing: TextButton(
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Abandonar empresa'),
                                content: Text('¿Estás seguro de que quieres abandonar la empresa "$name"? Esta acción no se puede deshacer desde tu perfil.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                                  ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Abandonar')),
                                ],
                              ),
                            );
                            if (confirm != true) return;
                            try {
                              final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
                              final res = await functions.httpsCallable('companyLeaveCompany').call({'companyId': id});
                              final data = res.data as Map<String, dynamic>?;
                              final status = data != null ? data['status'] as String? : null;
                              if (status == 'ok' || status == null) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Has abandonado la empresa'), backgroundColor: Colors.green));
                              } else if (status == 'not_member') {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No perteneces a esta empresa'), backgroundColor: Colors.orange));
                              } else {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resultado: $status')));
                              }
                            } on FirebaseFunctionsException catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message ?? e.code}'), backgroundColor: Colors.red));
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                            }
                          },
                          child: const Text('Abandonar', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                      const Divider(),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsCard(BuildContext context, String uid) {
    return FutureBuilder(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').doc(uid).collection('saved_places').get(),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('favorite_places').get(),
        // Solo reviews aprobadas (use the user's mirrored reviews subcollection):
        FirebaseFirestore.instance.collection('users').doc(uid).collection('reviews').where('status', isEqualTo: 'approved').get(),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('history_places').get(),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('reports').get(),
        // Count user-created routes for the statistics panel
        FirebaseFirestore.instance.collection('user_routes').where('createdBy', isEqualTo: uid).get(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data as List;
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estadísticas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.2,
                  children: [
                    _buildStatItem(context, Icons.bookmark, data[0].size.toString(), 'Guardados'),
                    _buildStatItem(context, Icons.favorite, data[1].size.toString(), 'Favoritos'),
                    _buildStatItem(context, Icons.star, data[2].size.toString(), 'Valoraciones'),
                    _buildStatItem(context, Icons.history, data[3].size.toString(), 'Visitados'),
                    _buildStatItem(context, Icons.report, data[4].size.toString(), 'Reportes'),
                    _buildStatItem(context, Icons.alt_route, data[5].size.toString(), 'Rutas'),
                  ],
                ),
                const SizedBox(height: 12),
                // Show user's current points (useful to verify awards were applied)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                  builder: (ctx, snapPoints) {
                    if (!snapPoints.hasData) return const SizedBox.shrink();
                    final u = snapPoints.data!.data();
                    final pts = (u != null && u['points'] != null) ? (u['points'].toString()) : '0';
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Chip(label: Text('Puntos: $pts', style: const TextStyle(fontWeight: FontWeight.bold))),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(BuildContext context, IconData icon, String count, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(height: 4),
        Text(count, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildMyPlacesCard(BuildContext context, String uid) {
    return DefaultTabController(
      length: 4,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
              const TabBar(
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: [
                Tab(icon: Icon(Icons.bookmark), text: 'Guardados'),
                Tab(icon: Icon(Icons.favorite), text: 'Favoritos'),
                Tab(icon: Icon(Icons.history), text: 'Historial'),
                Tab(icon: Icon(Icons.alt_route), text: 'Mis rutas'),
              ],
            ),
            SizedBox(
              // Give the tab content more vertical space so lists and maps
              // (e.g. 'Mis rutas' previews) don't appear clipped at half the
              // screen and cause awkward nested scrolling. Use a fraction of
              // the viewport height which works across devices.
              height: MediaQuery.of(context).size.height * 0.55,
              child: TabBarView(
                  children: [
                    _buildPlaceList(context, uid, 'saved_places'),
                    _buildPlaceList(context, uid, 'favorite_places'),
                    _buildPlaceList(context, uid, 'history_places'),
                    _buildUserRoutesList(context, uid),
                  ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserRoutesList(BuildContext context, String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('user_routes').where('createdBy', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No has creado rutas aún.'));

        // Separate private and public routes
        final privateDocs = docs.where((d) => (d.data()['isPrivate'] ?? false) == true).toList();
        final publicDocs = docs.where((d) => (d.data()['isPrivate'] ?? false) != true).toList();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: const Text('Rutas privadas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (privateDocs.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('No tienes rutas privadas.'))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: privateDocs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _buildRouteTile(privateDocs[i]),
                ),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: const Text('Rutas públicas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (publicDocs.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('No tienes rutas públicas.'))
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: publicDocs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) => _buildRouteTile(publicDocs[i]),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRouteTile(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data();
    final name = data['name'] ?? '(sin nombre)';
    final desc = data['description'] ?? '';
    final approved = data['approved'] == true;
    final isPrivate = data['isPrivate'] == true;
    final pdis = (data['pdis'] as List? ?? []).length;
    return ListTile(
      title: Text(name),
      subtitle: Text('$pdis puntos • ${approved ? 'Aprobada' : 'Pendiente'}\n$desc'),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.edit, color: Colors.orange), tooltip: 'Editar ruta', onPressed: () => _editOwnRoute(d.id, data)),
          IconButton(icon: const Icon(Icons.format_list_numbered, color: Colors.blue), tooltip: 'Editar puntos', onPressed: () {
            try {
              final userRoute = UserRoute.fromDoc(d);
              _editRoutePoints(userRoute);
            } catch (_) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se puede editar los puntos de la ruta')));
            }
          }),
          IconButton(icon: const Icon(Icons.delete_forever, color: Colors.red), tooltip: 'Eliminar ruta', onPressed: () async {
            final owner = data['createdBy'] ?? '';
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            if (currentUid == null || currentUid != owner) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No tienes permiso para eliminar esta ruta')));
              return;
            }
            final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
              title: const Text('Eliminar ruta'),
              content: const Text('¿Seguro que deseas eliminar esta ruta? Esta acción es irreversible.'),
              actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar'))],
            ));
            if (confirm == true) {
              try {
                await FirebaseFirestore.instance.collection('user_routes').doc(d.id).delete();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta eliminada')));
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error eliminando ruta: $e')));
              }
            }
          }),
          // For private routes always show a green tick. Public routes show
          // a green tick if approved or an hourglass if pending approval.
          isPrivate
              ? const Icon(Icons.check_circle, color: Colors.green)
              : (approved ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.hourglass_top, color: Colors.orange)),
        ],
      ),
      onTap: () {
        try {
          final userRoute = UserRoute.fromDoc(d);
          _showRoutePreview(userRoute);
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se puede mostrar la vista previa de la ruta')));
        }
      },
    );
  }

  Future<void> _showRoutePreview(UserRoute r) async {
    final Set<Marker> markers = {};
    for (var i = 0; i < r.pdis.length; i++) {
      try {
        final bmp = await createNumberedMarker(i + 1, size: 100, color: Colors.teal);
        markers.add(Marker(markerId: MarkerId(i.toString()), position: LatLng(r.pdis[i].lat, r.pdis[i].lng), icon: bmp, infoWindow: InfoWindow(title: 'Punto ${i + 1}')));
      } catch (_) {
        markers.add(Marker(markerId: MarkerId(i.toString()), position: LatLng(r.pdis[i].lat, r.pdis[i].lng), infoWindow: InfoWindow(title: 'Punto ${i + 1}')));
      }
    }

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(r.name),
              content: SizedBox(
                width: double.maxFinite,
                height: 300,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: LatLng(r.pdis.first.lat, r.pdis.first.lng), zoom: 13),
                    markers: markers,
                    polylines: {
                      Polyline(polylineId: const PolylineId('route'), points: r.pdis.map((p) => LatLng(p.lat, p.lng)).toList())
                    },
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
                ElevatedButton(onPressed: () => _openInGoogleMaps(r), child: const Text('Navegar')),
              ],
            ));
  }

  Future<void> _openInGoogleMaps(UserRoute r) async {
    if (r.pdis.isEmpty) return;
    try {
      final coords = r.pdis.map((p) => '${p.lat},${p.lng}').toList();
      final origin = coords.first;
      final destination = coords.last;
      String waypoints = '';
      if (coords.length > 2) {
        waypoints = coords.sublist(1, coords.length - 1).join('|');
      }
      final uriString = 'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(origin)}&destination=${Uri.encodeComponent(destination)}${waypoints.isNotEmpty ? '&waypoints=${Uri.encodeComponent(waypoints)}' : ''}&travelmode=driving';
      final uri = Uri.parse(uriString);

      // record history
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final first = r.pdis.first;
          FirebaseFirestore.instance.collection('users').doc(uid).collection('history').add({
            'action': 'open_route_navigation',
            'routeId': r.id,
            'routeName': r.name,
            'pointsCount': r.pdis.length,
            'timestamp': FieldValue.serverTimestamp(),
          });
          FirebaseFirestore.instance.collection('users').doc(uid).collection('history_places').add({
            'name': r.name,
            'category': 'route',
            'latitude': first.lat,
            'longitude': first.lng,
            'source': 'route_navigation',
            'sourceId': r.id,
            'poiId': null,
            'timestamp': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {}

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir Google Maps')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error abriendo Google Maps: $e')));
    }
  }

  Future<void> _editOwnRoute(String routeId, Map<String, dynamic> data) async {
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final descCtrl = TextEditingController(text: data['description'] ?? '');

    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Editar ruta'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
        TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Descripción')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Guardar'))],
    ));

    if (ok != true) return;

    try {
      await FirebaseFirestore.instance.collection('user_routes').doc(routeId).update({
        'name': nameCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta actualizada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error actualizando ruta: $e')));
    }
  }

  Future<void> _editRoutePoints(UserRoute route) async {
    // Open a full-screen editor that shows a map with draggable markers
    // and a reorderable list. Edits on the map/list sync and are saved on
    // Save. We push a new page to keep the UI responsive and avoid large
    // nested dialogs.
  final result = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EditRoutePointsScreen(route: route)));
    if (result == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Puntos actualizados')));
    }
  }

  /// List PDIs the user submitted (user_pois where submittedBy == uid)
  // _buildAddedPoisList removed: 'Añadidos' tab has been removed from Mis lugares.

  /// List PDIs the user submitted (user_pois where submittedBy == uid)
  // _buildAddedPoisList removed: 'Añadidos' tab has been removed from Mis lugares.

  Widget _buildPlaceList(BuildContext context, String uid, String collection) {
    // Special handling for history_places: show Pending and Aprobados sections
    if (collection == 'history_places') {
      // Show only navigation/history entries here. Exclude PDI submissions
      // (which have source == 'user_pois') so PDIs are shown in the
      // Recompensas popups instead.
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).collection(collection).orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No hay historial.'));
          final docs = snapshot.data!.docs.where((d) {
            final m = d.data() as Map<String, dynamic>;
            return (m['source'] ?? '') != 'user_pois';
          }).toList();
          if (docs.isEmpty) return const Center(child: Text('No hay historial.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final placeDoc = docs[index];
              final place = placeDoc.data() as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.history, color: Colors.blueGrey),
                title: Text(place['name'] ?? ''),
                subtitle: Text(place['category'] ?? ''),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () {
                  double? lat = (place['latitude'] is num) ? (place['latitude'] as num).toDouble() : null;
                  double? lng = (place['longitude'] is num) ? (place['longitude'] as num).toDouble() : null;
                  Navigator.of(context).pushNamed('/home', arguments: {
                    'focus': {
                      if (lat != null && lng != null) 'lat': lat,
                      if (lat != null && lng != null) 'lng': lng,
                      'name': place['name'] ?? '',
                      'category': place['category'] ?? '',
                    }
                  });
                },
              );
            },
          );
        },
      );
    }

    // Default behaviour for other collections
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        // Si no hay datos o está vacío, mostrar "Vacío" (incluso si hay error)
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Vacío'));
        }
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final place = snapshot.data!.docs[index];
            return ListTile(
              leading: const Icon(Icons.location_on, color: Colors.blue),
              title: Text(place['name'] ?? ''),
              subtitle: Text(place['category'] ?? '', style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
              onTap: () {
                // Try to extract coordinates from the stored place map. Support
                // several formats (position string 'lat,lng', or map with lat/lng).
                double? lat;
                double? lng;
                final p = place.data();
                try {
                  final pos = p['position'];
                  if (pos is String && pos.contains(',')) {
                    final parts = pos.split(',');
                    lat = double.tryParse(parts[0].trim());
                    lng = double.tryParse(parts[1].trim());
                  } else if (pos is Map) {
                    final rawLat = pos['lat'] ?? pos['latitude'];
                    final rawLng = pos['lng'] ?? pos['longitude'];
                    lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
                    lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
                  } else if (p['latitude'] != null && p['longitude'] != null) {
                    final rawLat = p['latitude'];
                    final rawLng = p['longitude'];
                    lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
                    lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
                  }
                } catch (_) {
                  lat = null; lng = null;
                }

                // Navigate to home and request initial focus on the coordinates.
                Navigator.of(context).pushNamed('/home', arguments: {
                  'focus': {
                    if (lat != null && lng != null) 'lat': lat,
                    if (lat != null && lng != null) 'lng': lng,
                    'name': p['name'] ?? '',
                    'category': p['category'] ?? '',
                  }
                });
              },
            );
          },
        );
      },
    );
  }

  Widget _buildRewardsCard(BuildContext context, String uid) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withAlpha(26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              'Recompensas',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // Stream user doc to get awardsHistory
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snap) {
                final userData = (snap.hasData && snap.data!.exists) ? snap.data!.data() ?? {} : {};
                final awards = (userData['awardsHistory'] is List) ? List.from(userData['awardsHistory']) : <dynamic>[];
                final awardsCount = awards.length;
                final totalDays = awards.fold<int>(0, (acc, a) => acc + ((a is Map && a['days'] is int) ? a['days'] as int : 0));

                return Column(
                  children: [
                    Row(
                      children: [
                        FaIcon(FontAwesomeIcons.trophy, size: 42, color: Colors.amber.shade700),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$awardsCount', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                              Text('Premios recibidos', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                            ],
                          ),
                        ),
                        // Total days badge
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                children: [
                                  Text('$totalDays', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Días totales', style: TextStyle(fontSize: 10, color: Colors.grey[700])),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('2 días por PDI aprobado', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                    const SizedBox(height: 12),
                    // Reviews counter & CTA
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: resilientStream(
                        querySnapshotsCompat(
                          FirebaseFirestore.instance.collection('users').doc(uid).collection('reviews'),
                        ),
                        name: 'profile_rewards_reviews_count',
                      ),
                      builder: (context, revSnap) {
                        final reviewsCount = revSnap.hasData ? revSnap.data!.docs.length : 0;
                        return Row(
                          children: [
                            // Animated encouragement icon
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 1.0, end: 1.05),
                              duration: const Duration(milliseconds: 800),
                              curve: Curves.easeInOut,
                              builder: (context, scale, child) {
                                return Transform.scale(scale: scale, child: child);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                                child: const Icon(Icons.thumb_up, color: Colors.green, size: 28),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('$reviewsCount', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                                  Text('Valoraciones realizadas', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                                  const SizedBox(height: 8),
                                  Text('Sigue valorando PDI y ayudando a la comunidad — ¡cada aportación suma!', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Two buttons: show pending and approved PDIs in a popup
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('PDIs pendientes'),
                          content: SizedBox(
                            width: double.maxFinite,
                              child: StreamBuilder<QuerySnapshot>(
                              // Query only by submitter to avoid requiring a composite index.
                              stream: FirebaseFirestore.instance.collection('user_pois').where('submittedBy', isEqualTo: uid).snapshots(),
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting) return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
                                if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No hay PDIs pendientes.')));
                                // Filter client-side for pending status and sort by submittedAt desc
                                final docsAll = snap.data!.docs;
                                final pendingDocs = docsAll.where((d) {
                                  final p = d.data() as Map<String, dynamic>;
                                  return (p['status'] ?? 'pending') == 'pending' && (p['submittedBy'] ?? '') == uid;
                                }).toList();
                                pendingDocs.sort((a, b) {
                                  final pa = a.data() as Map<String, dynamic>;
                                  final pb = b.data() as Map<String, dynamic>;
                                  final ta = pa['submittedAt'] is Timestamp ? (pa['submittedAt'] as Timestamp).toDate().millisecondsSinceEpoch : 0;
                                  final tb = pb['submittedAt'] is Timestamp ? (pb['submittedAt'] as Timestamp).toDate().millisecondsSinceEpoch : 0;
                                  return tb.compareTo(ta);
                                });

                                if (pendingDocs.isEmpty) return const SizedBox(height: 120, child: Center(child: Text('No hay PDIs pendientes.')));

                                return ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: pendingDocs.length,
                                  itemBuilder: (context, i) {
                                    final d = pendingDocs[i];
                                    final p = d.data() as Map<String, dynamic>;
                                    return ListTile(
                                      leading: const Icon(Icons.hourglass_top, color: Colors.orange),
                                      title: Text(p['name'] ?? ''),
                                      subtitle: Text(p['category'] ?? ''),
                                      onTap: () {
                                        double? lat = (p['latitude'] is num) ? (p['latitude'] as num).toDouble() : null;
                                        double? lng = (p['longitude'] is num) ? (p['longitude'] as num).toDouble() : null;
                                        Navigator.of(context).pushNamed('/home', arguments: {'focus': {if (lat != null) 'lat': lat, if (lng != null) 'lng': lng, 'name': p['name'] ?? '', 'category': p['category'] ?? ''}});
                                        Navigator.of(ctx).pop();
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))],
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.orange.shade50,
                          child: const Icon(Icons.hourglass_top, color: Colors.orange, size: 18),
                        ),
                        const SizedBox(height: 6),
                        const Text('PDIs pendientes', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApprovedPoisScreen(uid: uid)));
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.green.shade50,
                          child: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        ),
                        const SizedBox(height: 6),
                        const Text('PDIs aprobados', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


