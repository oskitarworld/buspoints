import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PoiApprovalScreen extends StatelessWidget {
  const PoiApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprobar Puntos de Interés'),
      ),
      body: const PoiList(),
    );
  }
}

class PoiList extends StatelessWidget {
  const PoiList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('user_pois')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'No hay PDI pendientes de aprobación.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final poiDoc = snapshot.data!.docs[index];
            return PoiListItem(poiDoc: poiDoc);
          },
        );
      },
    );
  }
}

class PoiListItem extends StatelessWidget {
  final QueryDocumentSnapshot poiDoc;

  const PoiListItem({super.key, required this.poiDoc});

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  Future<void> _approvePoi(BuildContext context, String poiId) async {
    try {
      await FirebaseFirestore.instance.collection('user_pois').doc(poiId).update({'status': 'approved'});
      if (!context.mounted) return;
      _showSnackBar(context, 'PDI aprobado con éxito.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Error al aprobar el PDI: $e', isError: true);
    }
  }

  Future<void> _rejectPoi(BuildContext context, String poiId) async {
    try {
      await FirebaseFirestore.instance.collection('user_pois').doc(poiId).delete();
      if (!context.mounted) return;
      _showSnackBar(context, 'PDI rechazado con éxito.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Error al rechazar el PDI: $e', isError: true);
    }
  }

  Future<String> _getUserEmail(String uid) async {
    if (uid.isEmpty) return 'Usuario Desconocido';
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return userDoc.exists ? userDoc.data()!['email'] ?? 'Email no encontrado' : 'Usuario no encontrado';
    } catch (e) {
      return 'Error cargando email';
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = poiDoc.data() as Map<String, dynamic>;
    final String poiId = poiDoc.id;
    final String name = data['name'] ?? 'Sin Nombre';
    final String description = data['description'] ?? 'Sin descripción.';
    final String userId = data['submittedBy'] ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (description.isNotEmpty && description != 'Sin descripción.')
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            FutureBuilder<String>(
              future: _getUserEmail(userId),
              builder: (context, userSnapshot) {
                return Text(
                  'Enviado por: ${userSnapshot.data ?? 'Cargando...'}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: userSnapshot.hasData ? Colors.black : Colors.grey),
                );
              },
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.close, color: Colors.red),
                  label: const Text('Rechazar', style: TextStyle(color: Colors.red)),
                  onPressed: () => _rejectPoi(context, poiId),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text('Aprobar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _approvePoi(context, poiId),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
