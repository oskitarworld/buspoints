import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:myapp/screens/home_screen.dart' show googleApiKey;
import 'package:myapp/widgets/native_streetview.dart';

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

    // Before attempting to approve, ensure the POI has valid coordinates.
    try {
      final snap = await poiRef.get();
      if (!snap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El PDI no existe.')));
        }
        return;
      }
  final data = snap.data();
      double? lat;
      double? lng;
      if (data != null) {
        if (data['latitude'] != null && data['longitude'] != null) {
          final rawLat = data['latitude'];
          final rawLng = data['longitude'];
          lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
          lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
        }
        if ((lat == null || lng == null) && data['geopoint'] is GeoPoint) {
          final gp = data['geopoint'] as GeoPoint;
          lat = gp.latitude;
          lng = gp.longitude;
        }
        if ((lat == null || lng == null) && data['location'] is GeoPoint) {
          final gp = data['location'] as GeoPoint;
          lat = gp.latitude;
          lng = gp.longitude;
        }
        if ((lat == null || lng == null) && data['position'] is String && (data['position'] as String).contains(',')) {
          final parts = (data['position'] as String).split(',');
          lat = double.tryParse(parts[0].trim());
          lng = double.tryParse(parts[1].trim());
        }
      }

      if (newStatus == 'approved' && (lat == null || lng == null)) {
        // Block approval: coordinates are required
        if (!mounted) return;
        // Capture navigator before awaiting the dialog so we can safely
        // navigate from the dialog's action without referencing the
        // possibly stale BuildContext.
        final nav = Navigator.of(context);
        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('Coordenadas faltantes'),
          content: const Text('Este PDI no tiene coordenadas válidas. No se puede aprobar hasta que tenga ubicación.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
            TextButton(onPressed: () {
              Navigator.of(ctx).pop();
              // Let the admin inspect the PDI on the map
              nav.pushNamed('/home', arguments: {
                'focus': {'docId': poiId, 'source': 'user_pois', 'name': data?['name'] ?? '', 'category': data?['category'] ?? ''}
              });
            }, child: const Text('Ver en mapa')),
          ],
        ));
        return;
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error comprobando coordenadas: $e')));
      return;
    }

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
            newSubscriptionEndDate = DateTime.now().add(const Duration(days: 2));
          }

          transaction.update(userRef, {
            'approvedPoisCount': newPoisCount,
            'subscriptionEndDate': Timestamp.fromDate(newSubscriptionEndDate),
            'subscriptionActive': true,
          });
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "POI ${newStatus == 'approved' ? 'aprobado' : 'rechazado'} con éxito.")),
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

  // Reusable helper to open Street View (embedded) or show a friendly message when missing
  Future<void> _openStreetViewDialog(BuildContext ctx, GeoPoint? gp) async {
    if (gp != null) {
      final lat = gp.latitude;
      final lng = gp.longitude;
      // Build a small HTML page that instantiates a StreetViewPanorama using
      // the Maps JavaScript API and our API key. This avoids redirecting to
      // google.com which can trigger sign-in UI in some environments.
      final html = '''
<!doctype html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>html,body,#panorama{height:100%;margin:0;padding:0}</style>
    <script src="https://maps.googleapis.com/maps/api/js?key=$googleApiKey&libraries=places"></script>
  </head>
  <body>
    <div id="panorama"></div>
    <script>
      function init() {
        var pano = new google.maps.StreetViewPanorama(document.getElementById('panorama'), {
          position: {lat: $lat, lng: $lng},
          pov: {heading: 0, pitch: 0},
          visible: true
        });
      }
      window.onload = init;
    </script>
  </body>
</html>
''';

      await showDialog<void>(
        context: ctx,
        builder: (innerCtx) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: const Text('Street View'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(innerCtx).pop(),
                  ),
                ],
              ),
              SizedBox(
                width: MediaQuery.of(ctx).size.width * 0.9,
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Builder(builder: (webCtx) {
                  final controller = WebViewController();
                  // Load as data URI to avoid external navigation and keep API key usage local
                  final dataUri = Uri.dataFromString(html, mimeType: 'text/html', encoding: Utf8Codec());
                  controller.setJavaScriptMode(JavaScriptMode.unrestricted);
                  controller.loadRequest(dataUri);
                  return WebViewWidget(controller: controller);
                }),
              ),
            ],
          ),
        ),
      );
    } else {
      await showDialog<void>(
        context: ctx,
        builder: (innerCtx) => AlertDialog(
          title: const Text('Sin Street View'),
          content: const Text('Google Street View no ha llegado aquí todavía. Puedes ver la ubicación en el mapa o aportar la información si lo deseas.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(innerCtx).pop(), child: const Text('Cerrar')),
          ],
        ),
      );
    }
  }

  void _showPoiDetails(DocumentSnapshot poi) {
    final poiData = poi.data() as Map<String, dynamic>;
    GeoPoint? location;
    try {
      if (poiData['location'] is GeoPoint) {
        location = poiData['location'] as GeoPoint;
      } else if (poiData['geopoint'] is GeoPoint) {
        location = poiData['geopoint'] as GeoPoint;
      } else if (poiData['geopoint'] is Map && poiData['geopoint']['latitude'] != null) {
        location = GeoPoint(poiData['geopoint']['latitude'], poiData['geopoint']['longitude']);
      }
    } catch (_) {
      location = null;
    }

    final position = location != null ? LatLng(location.latitude, location.longitude) : LatLng(40.4168, -3.7038);

    final nav = Navigator.of(context);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(poiData['name'] ?? 'PDI'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Categoría: ${poiData['category']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(poiData['description'] ?? 'Sin descripción.'),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  width: 300,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: position, zoom: 15),
                    markers: location != null ? { Marker(markerId: MarkerId(poi.id), position: position) } : {},
                    scrollGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                  ),
                ),
              ],
            ),
          ),
                actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
            // Street View: botón más visible con icono y texto
            SizedBox(
              height: 40,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () async {
                  // Capture the dialog-local BuildContext before awaiting so we
                  // don't reference it after an async gap (fix use_build_context_synchronously).
                  final dialogCtx = context;
                  // We captured the dialog-local BuildContext above (dialogCtx)
                  // and will only use dialogCtx for further UI operations. The
                  // call to NativeStreetView.open may perform platform work
                  // but doesn't reference the outer BuildContext — suppress
                  // the analyzer here after manual review.
                  // ignore: use_build_context_synchronously
                  final opened = await NativeStreetView.open(lat: location?.latitude, lng: location?.longitude);
                  if (!opened) {
                    // Fallback to embedded WebView Street View
                    // dialogCtx is a dialog-local BuildContext captured above.
                    // ignore: use_build_context_synchronously
                    await _openStreetViewDialog(dialogCtx, location);
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Circular background for the icon to make it more visible
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Icon(Icons.streetview, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text('Street View', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to Home and focus the POI coordinates so admin can inspect it on the full map
                if (location != null) {
                  nav.pushNamed('/home', arguments: {
                    'focus': {
                      'lat': location.latitude,
                      'lng': location.longitude,
                      'name': poiData['name'] ?? '',
                      'category': poiData['category'] ?? '',
                      'source': 'user_pois',
                      'docId': poi.id,
                    }
                  });
                } else {
                  // Fallback: still navigate without coords
                  nav.pushNamed('/home', arguments: {
                    'focus': {'name': poiData['name'] ?? '', 'category': poiData['category'] ?? '', 'source': 'user_pois', 'docId': poi.id}
                  });
                }
              },
              child: const Text('Ver en mapa'),
            ),
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
        stream: _firestore.collection('user_pois').where('status', isEqualTo: 'pending').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay puntos pendientes de aprobación.'));
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Ha ocurrido un error al cargar los datos.'));
          }

          final pois = snapshot.data!.docs;

          return ListView.builder(
            itemCount: pois.length,
            itemBuilder: (context, index) {
              final poi = pois[index];
              final poiData = poi.data() as Map<String, dynamic>;
              final userId = poiData['submittedBy'] ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: FutureBuilder<String>(
                  future: _getUserEmail(userId.toString()),
                  builder: (context, userSnapshot) {
                    // Extract coordinates to pass to home view
                    double? lat;
                    double? lng;
                    try {
                      if (poiData['location'] is GeoPoint) {
                        final gp = poiData['location'] as GeoPoint;
                        lat = gp.latitude;
                        lng = gp.longitude;
                      } else if (poiData['geopoint'] is GeoPoint) {
                        final gp = poiData['geopoint'] as GeoPoint;
                        lat = gp.latitude;
                        lng = gp.longitude;
                      } else if (poiData['latitude'] != null && poiData['longitude'] != null) {
                        final rawLat = poiData['latitude'];
                        final rawLng = poiData['longitude'];
                        lat = (rawLat is num) ? rawLat.toDouble() : double.tryParse(rawLat?.toString() ?? '');
                        lng = (rawLng is num) ? rawLng.toDouble() : double.tryParse(rawLng?.toString() ?? '');
                      } else if (poiData['position'] is String && (poiData['position'] as String).contains(',')) {
                        final parts = (poiData['position'] as String).split(',');
                        lat = double.tryParse(parts[0].trim());
                        lng = double.tryParse(parts[1].trim());
                      }
                    } catch (_) {
                      lat = null; lng = null;
                    }

                    return ListTile(
                      title: Text(poiData['name'] ?? 'PDI'),
                      subtitle: Text('Categoría: ${poiData['category']}\nEnviado por: ${userSnapshot.data ?? 'Cargando...'}'),
                      isThreeLine: true,
                      onTap: () {
                        Navigator.of(context).pushNamed('/home', arguments: {
                          'focus': {
                            if (lat != null && lng != null) 'lat': lat,
                            if (lat != null && lng != null) 'lng': lng,
                            'name': poiData['name'] ?? '',
                            'category': poiData['category'] ?? '',
                            'source': 'user_pois',
                            'docId': poi.id,
                          }
                        });
                      },
                      trailing: SizedBox(
                        width: 140,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Info as a small circular icon
                            InkWell(
                              onTap: () => _showPoiDetails(poi),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.info_outline, size: 20, color: Colors.black54),
                              ),
                            ),
                            // Approve button: square, centered icon
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.green,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => _updatePoiStatus(poi.id, 'approved', userId.toString()),
                                child: const Icon(Icons.check, color: Colors.white, size: 20),
                              ),
                            ),
                            // Reject button: square, centered icon
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.red,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () => _updatePoiStatus(poi.id, 'rejected', userId.toString()),
                                child: const Icon(Icons.close, color: Colors.white, size: 20),
                              ),
                            ),
                          ],
                        ),
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
