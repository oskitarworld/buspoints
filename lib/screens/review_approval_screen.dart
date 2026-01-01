import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_web_compat.dart';
import 'package:myapp/widgets/firestore_error_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReviewApprovalScreen extends StatelessWidget {
  const ReviewApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprobar Comentarios y Valoraciones'),
      ),
      body: const ReviewList(),
    );
  }
}

class ReviewList extends StatefulWidget {
  const ReviewList({super.key});

  @override
  State<ReviewList> createState() => _ReviewListState();
}

class _ReviewListState extends State<ReviewList> {
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _isAdmin = false;
          _loading = false;
        });
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      final isAdminFlag = data != null && ((data['role'] == 'admin') || (data['isAdmin'] == true));
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdminFlag;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;
        _loading = false;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _pendingReviewsStream() {
    // Buscar todos los reviews pendientes en todos los PDIs
    return querySnapshotsCompat(
      FirebaseFirestore.instance
          .collectionGroup('reviews')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_isAdmin) {
      return const Center(
        child: Text(
          'Acceso denegado. Solo administradores pueden ver comentarios pendientes.',
          style: TextStyle(fontSize: 16, color: Colors.red),
          textAlign: TextAlign.center,
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _pendingReviewsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return firestoreErrorWidget(context, snapshot.error);
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'No hay comentarios/valoraciones pendientes de aprobación.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          );
        }
  // Filter to only include canonical PDI reviews under `pdis_v2/*/reviews`.
  // Using startsWith guards better against other duplicate parents and
  // is more explicit than checking for '/users/'.
  final canonicalDocs = snapshot.data!.docs.where((d) => d.reference.path.startsWith('pdis_v2/')).toList();
        if (canonicalDocs.isEmpty) {
          return const Center(
            child: Text(
              'No hay comentarios/valoraciones pendientes de aprobación.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.builder(
          itemCount: canonicalDocs.length,
          itemBuilder: (context, index) {
            final reviewDoc = canonicalDocs[index];
            return ReviewListItem(reviewDoc: reviewDoc);
          },
        );
      },
    );
  }
}

class ReviewListItem extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> reviewDoc;
  const ReviewListItem({super.key, required this.reviewDoc});

  @override
  State<ReviewListItem> createState() => _ReviewListItemState();
}

class _ReviewListItemState extends State<ReviewListItem> {
  String? _resolvedUserName;

  @override
  void initState() {
    super.initState();
    _resolveUserNameIfNeeded();
  }

  Future<void> _resolveUserNameIfNeeded() async {
    final data = widget.reviewDoc.data();
    final rawName = (data['userDisplayName'] ?? data['userName'] ?? data['displayName'] ?? data['authorName'] ?? '')?.toString();
    final userId = (data['userId'] ?? '')?.toString();
    if (rawName != null && rawName.isNotEmpty) {
      _resolvedUserName = rawName;
      if (mounted) setState(() {});
      return;
    }
    if (userId == null || userId.isEmpty) return;
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final udata = userDoc.data();
      final candidate = udata != null ? (udata['displayName'] ?? udata['name'] ?? udata['username'] ?? '')?.toString() : '';
      if (candidate != null && candidate.isNotEmpty) {
        _resolvedUserName = candidate;
        if (mounted) setState(() {});
      }
    } catch (_) {
      // ignore errors resolving user name
    }
  }

  Future<bool> _updateReviewStatus(String status) async {
    try {
      await widget.reviewDoc.reference.update({'status': status});
      // Also update mirrored copy under users/{userId}/reviews/{reviewId} if present
      try {
        final data = widget.reviewDoc.data();
        final userId = (data['userId'] ?? '')?.toString();
        if (userId != null && userId.isNotEmpty) {
          final userRevRef = FirebaseFirestore.instance.collection('users').doc(userId).collection('reviews').doc(widget.reviewDoc.id);
          await userRevRef.update({'status': status});
        }
      } catch (_) {
        // ignore mirror update errors
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.reviewDoc.data();
    final comment = data['comment'] ?? '';
    final rating = data['rating'] ?? 0;
    final userId = (data['userId'] ?? '')?.toString();
    final userDisplayName = _resolvedUserName ?? (data['userDisplayName'] ?? data['userName'] ?? data['displayName'] ?? data['authorName'] ?? '')?.toString();
    final createdAt = data['createdAt'] != null && data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          // Navigate to the PDI (parent document of this review) if available
          final nav = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          try {
            final pdiRef = widget.reviewDoc.reference.parent.parent;
            if (pdiRef == null) {
              messenger.showSnackBar(const SnackBar(content: Text('No se pudo localizar el PDI asociado')));
              return;
            }
            final pdiDoc = await pdiRef.get();
            final pdiData = pdiDoc.data();
            double? lat;
            double? lng;
            String name = '';
            String category = '';
            if (pdiData != null) {
              name = (pdiData['name'] ?? '')?.toString() ?? '';
              category = (pdiData['category'] ?? '')?.toString() ?? '';
              try {
                if (pdiData['location'] is GeoPoint) {
                  final gp = pdiData['location'] as GeoPoint;
                  lat = gp.latitude;
                  lng = gp.longitude;
                } else if (pdiData['geopoint'] is GeoPoint) {
                  final gp = pdiData['geopoint'] as GeoPoint;
                  lat = gp.latitude;
                  lng = gp.longitude;
                } else if (pdiData['latitude'] != null && pdiData['longitude'] != null) {
                  final rawLat = pdiData['latitude'];
                  final rawLng = pdiData['longitude'];
                  lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
                  lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
                }
              } catch (_) {
                // ignore
              }
            }
            final args = {
              'focus': {
                if (lat != null) 'lat': lat,
                if (lng != null) 'lng': lng,
                'name': name,
                'category': category,
                'source': 'pdis_v2',
                'docId': pdiRef.id,
              }
            };
            nav.pushNamed('/home', arguments: args);
          } catch (e) {
            messenger.showSnackBar(const SnackBar(content: Text('Error al navegar al PDI')));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ...List.generate(5, (i) => Icon(i < rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 20)),
                  const SizedBox(width: 8),
                  if (createdAt != null)
                    Text('${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 8),
              Text(comment, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text('Usuario: ${userDisplayName != null && userDisplayName.isNotEmpty ? userDisplayName : userId}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text('Aprobar'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final success = await _updateReviewStatus('approved');
                      if (success) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Comentario aprobado.'), backgroundColor: Colors.green),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Error al aprobar'), backgroundColor: Colors.red),
                        );
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.close, color: Colors.white),
                    label: const Text('Rechazar'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final success = await _updateReviewStatus('rejected');
                      if (success) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Comentario rechazado.'), backgroundColor: Colors.green),
                        );
                      } else {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Error al rechazar'), backgroundColor: Colors.red),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
