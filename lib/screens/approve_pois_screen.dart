import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ApprovePoisScreen extends StatefulWidget {
  const ApprovePoisScreen({super.key});

  @override
  State<ApprovePoisScreen> createState() => _ApprovePoisScreenState();
}

class _ApprovePoisScreenState extends State<ApprovePoisScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> _updatePoiStatus(
      String poiId, String newStatus, String userId) async {
    final poiRef = _firestore.collection('user_pois').doc(poiId);
    final userRef = _firestore.collection('users').doc(userId);

    try {
      await _firestore.runTransaction((transaction) async {
        final userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw Exception("El usuario no existe.");
        }

        // Update the POI status
        transaction.update(poiRef, {
          'status': newStatus,
          'reviewedAt': FieldValue.serverTimestamp(),
        });

        // If approved, update user's rewards
        if (newStatus == 'approved') {
          final userData = userDoc.data()!;

          // 1. Increment the approved POIs counter
          final currentPoisCount = (userData['approvedPoisCount'] ?? 0) as int;
          final newPoisCount = currentPoisCount + 1;

          // 2. Extend the subscription end date by 2 days
          DateTime newSubscriptionEndDate;
          final currentSubscriptionEnd =
              userData['subscriptionEndDate'] as Timestamp?;

          if (currentSubscriptionEnd != null &&
              currentSubscriptionEnd.toDate().isAfter(DateTime.now())) {
            // If the subscription is active, extend it from its current end date
            newSubscriptionEndDate =
                currentSubscriptionEnd.toDate().add(const Duration(days: 2));
          } else {
            // If expired or not set, extend it from today
            newSubscriptionEndDate =
                DateTime.now().add(const Duration(days: 2));
          }

          transaction.update(userRef, {
            'approvedPoisCount': newPoisCount,
            'subscriptionEndDate': Timestamp.fromDate(newSubscriptionEndDate),
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'POI ${newStatus == 'approved' ? 'aprobado' : 'rechazado'} con éxito.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar: $e')),
        );
      }
    }
  }

  Future<String> _getUserEmail(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (userDoc.exists) {
        return userDoc.data()?['email'] ?? 'Email no encontrado';
      }
      return 'Usuario no encontrado';
    } catch (e) {
      return 'Error al cargar email';
    }
  }

  void _showPoiDetails(DocumentSnapshot poi) {
    final poiData = poi.data() as Map<String, dynamic>;
    final GeoPoint location = poiData['location'];
    final LatLng position = LatLng(location.latitude, location.longitude);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(poiData['name']),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Categoría: ${poiData['category']}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(poiData['description'] ?? 'Sin descripción.'),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  width: 300,
                  child: GoogleMap(
                    initialCameraPosition:
                        CameraPosition(target: position, zoom: 15),
                    markers: {
                      Marker(markerId: MarkerId(poi.id), position: position)
                    },
                    scrollGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aprobar Puntos de Interés'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('user_pois')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text('No hay puntos pendientes de aprobación.'));
          }
          if (snapshot.hasError) {
            return const Center(
                child: Text('Ha ocurrido un error al cargar los datos.'));
          }

          final pois = snapshot.data!.docs;

          return ListView.builder(
            itemCount: pois.length,
            itemBuilder: (context, index) {
              final poi = pois[index];
              final poiData = poi.data() as Map<String, dynamic>;
              final userId = poiData['submittedBy'];

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: FutureBuilder<String>(
                  future: _getUserEmail(userId),
                  builder: (context, userSnapshot) {
                    return ListTile(
                      title: Text(poiData['name']),
                      subtitle: Text(
                          'Categoría: ${poiData['category']}\nEnviado por: ${userSnapshot.data ?? 'Cargando...'}'),
                      isThreeLine: true,
                      onTap: () => _showPoiDetails(poi),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.check, color: Colors.green),
                            tooltip: 'Aprobar',
                            onPressed: () =>
                                _updatePoiStatus(poi.id, 'approved', userId),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            tooltip: 'Rechazar',
                            onPressed: () =>
                                _updatePoiStatus(poi.id, 'rejected', userId),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
