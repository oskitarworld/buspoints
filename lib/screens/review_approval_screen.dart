import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      setState(() {
        _isAdmin = isAdminFlag;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _isAdmin = false;
        _loading = false;
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _pendingReviewsStream() {
    // Buscar todos los reviews pendientes en todos los PDIs
    return FirebaseFirestore.instance
        .collectionGroup('reviews')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
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
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
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
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final reviewDoc = snapshot.data!.docs[index];
            return ReviewListItem(reviewDoc: reviewDoc);
          },
        );
      },
    );
  }
}

class ReviewListItem extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> reviewDoc;
  const ReviewListItem({super.key, required this.reviewDoc});

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  Future<void> _updateReviewStatus(BuildContext context, String status) async {
    try {
      await reviewDoc.reference.update({'status': status});
      _showSnackBar(context, status == 'approved' ? 'Comentario aprobado.' : 'Comentario rechazado.');
    } catch (e) {
      _showSnackBar(context, 'Error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = reviewDoc.data();
    final comment = data['comment'] ?? '';
    final rating = data['rating'] ?? 0;
    final userId = data['userId'] ?? '';
    final createdAt = data['createdAt'] != null && data['createdAt'] is Timestamp
        ? (data['createdAt'] as Timestamp).toDate()
        : null;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            Text('Usuario: $userId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Aprobar'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: () => _updateReviewStatus(context, 'approved'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.close, color: Colors.white),
                  label: const Text('Rechazar'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () => _updateReviewStatus(context, 'rejected'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
