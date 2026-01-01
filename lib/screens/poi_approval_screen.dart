import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_service.dart';
import 'package:myapp/widgets/firestore_error_widget.dart';

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

  FirestoreService get _fs => FirestoreService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _fs.pendingUserPoisStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return firestoreErrorWidget(context, snapshot.error);
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

class PoiListItem extends StatefulWidget {
  final QueryDocumentSnapshot poiDoc;

  const PoiListItem({super.key, required this.poiDoc});

  @override
  State<PoiListItem> createState() => _PoiListItemState();
}

class _PoiListItemState extends State<PoiListItem> {
  bool _isProcessing = false;

  void _showMessageDialog(String title, String message, {bool isError = false}) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _approvePoi(String poiId) async {
    setState(() => _isProcessing = true);
    try {
      await FirestoreService().approveUserPoiAndMove(poiId);
      if (!mounted) return;
  // Show success and then close dialog and the approval screen so the admin
  // returns to the list and sees the updated stream.
  _showMessageDialog('Hecho', 'PDI aprobado con éxito.');
  setState(() => _isProcessing = false);
  // Give the dialog a moment to be seen
  await Future.delayed(const Duration(milliseconds: 600));
  if (!mounted) return;
  // First pop any open dialog
  Navigator.of(context).pop();
  // Then try to pop the approval screen to return to the admin panel list
  await Future.delayed(const Duration(milliseconds: 80));
  if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showMessageDialog('Error', 'Error al aprobar el PDI:\n$e', isError: true);
    }
  }

  Future<void> _rejectPoi(String poiId) async {
    setState(() => _isProcessing = true);
    try {
      await FirestoreService().rejectUserPoi(poiId);
      if (!mounted) return;
  _showMessageDialog('Hecho', 'PDI rechazado con éxito.');
  setState(() => _isProcessing = false);
  await Future.delayed(const Duration(milliseconds: 600));
  if (!mounted) return;
  Navigator.of(context).pop();
  await Future.delayed(const Duration(milliseconds: 80));
  if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showMessageDialog('Error', 'Error al rechazar el PDI:\n$e', isError: true);
    }
  }

  Future<String> _getUserEmail(String uid) async {
    if (uid.isEmpty) return 'Usuario Desconocido';
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      return userDoc.exists ? (userDoc.data()!['email'] ?? 'Email no encontrado') : 'Usuario no encontrado';
    } catch (e) {
      return 'Error cargando email';
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.poiDoc.data() as Map<String, dynamic>;
    final String poiId = widget.poiDoc.id;
    final String name = data['name'] ?? 'Sin Nombre';
    final String description = data['description'] ?? 'Sin descripción.';
    final String userId = data['submittedBy'] ?? '';

    return InkWell(
      onTap: () {
        // Navigate to home map focusing on this POI if coordinates are available.
        double? lat;
        double? lng;
        try {
          if (data['latitude'] != null && data['longitude'] != null) {
            final rawLat = data['latitude'];
            final rawLng = data['longitude'];
            lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
            lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
          } else if (data['geopoint'] is GeoPoint) {
            final gp = data['geopoint'] as GeoPoint;
            lat = gp.latitude;
            lng = gp.longitude;
          }
        } catch (_) {
          lat = null; lng = null;
        }
        Navigator.of(context).pushNamed('/home', arguments: {
          'focus': {
            if (lat != null) 'lat': lat,
            if (lng != null) 'lng': lng,
            'name': name,
            'docId': poiId,
          }
        });
      },
      child: Card(
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
                  onPressed: _isProcessing ? null : () => _rejectPoi(poiId),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: _isProcessing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.check, color: Colors.white),
                  label: const Text('Aprobar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isProcessing ? null : () => _approvePoi(poiId),
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
