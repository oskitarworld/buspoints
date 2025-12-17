import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';

class AddPoiScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final List<String> categories;

  const AddPoiScreen(
      {super.key, this.initialPosition, required this.categories});

  @override
  State<AddPoiScreen> createState() => _AddPoiScreenState();
}

class _AddPoiScreenState extends State<AddPoiScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedCategory;
  LatLng? _selectedLocation;
  Set<Marker> _markers = {};
  late CameraPosition _initialCameraPosition;

  @override
  void initState() {
    super.initState();
    // Preserve the category order passed by the caller (HomeScreen).
    // Do not sort here so the dropdown matches the main menu order.

    if (widget.initialPosition != null) {
      _selectedLocation = widget.initialPosition;
      _markers = {
        Marker(
          markerId: const MarkerId('new_poi_marker'),
          position: widget.initialPosition!,
          infoWindow: const InfoWindow(title: 'Ubicación Seleccionada'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        )
      };
      _initialCameraPosition = CameraPosition(
        target: widget.initialPosition!,
        zoom: 16.0,
      );
    } else {
      _initialCameraPosition = const CameraPosition(
        target: LatLng(40.416775, -3.703790), // Madrid
        zoom: 12.0,
      );
    }
  }

  void _onMapTapped(LatLng location) {
    setState(() {
      _selectedLocation = location;
      _markers = {
        Marker(
          markerId: const MarkerId('new_poi_marker'),
          position: location,
          infoWindow: const InfoWindow(title: 'Ubicación Seleccionada'),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        )
      };
    });
  }

  Future<void> _submitPoi() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedLocation == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, selecciona una ubicación en el mapa')),
        );
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes iniciar sesión para realizar esta acción')),
        );
        return;
      }

      try {
        // All user submissions go to user_pois with status 'pending'.
        final geoFirePoint = GeoFirePoint(GeoPoint(
            _selectedLocation!.latitude, _selectedLocation!.longitude));

        await FirebaseFirestore.instance.collection('user_pois').add({
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
          'category': _selectedCategory,
          // Helpful coordinate shapes for later processing/approval
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
          'geopoint': GeoPoint(_selectedLocation!.latitude, _selectedLocation!.longitude),
          'geo': geoFirePoint.data, // keeps geohash for potential proximity queries
          'submittedBy': user.uid,
          'submittedAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        });

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Gracias! Tu punto ha sido enviado para su revisión.')),
          );
        }
      } on FirebaseException catch (e) {
        if (!mounted) return;
        String errorMessage;
        if (e.code == 'permission-denied') {
          errorMessage = 'No estás autorizado para realizar esta acción. Por favor, contacta con un administrador si crees que esto es un error.';
        } else {
          errorMessage = 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo más tarde.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al enviar el punto: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Añadir Punto de Interés'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 300,
                  child: GoogleMap(
                    initialCameraPosition: _initialCameraPosition,
                    markers: _markers,
                    onTap: _onMapTapped,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _selectedLocation == null
                      ? '1. Toca el mapa para establecer la ubicación.'
                      : 'Ubicación establecida. Puedes ajustarla tocando el mapa de nuevo.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: '2. Selecciona una categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: widget.categories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category[0].toUpperCase() +
                          category.substring(1).replaceAll('_', ' ')),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedCategory = newValue;
                    });
                  },
                  validator: (value) =>
                      value == null ? 'Por favor, selecciona una categoría' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: '3. Dale un nombre al punto',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Por favor, introduce un nombre' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '4. Comentarios (opcional)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 3,
                  validator: (value) {
                    final cat = (_selectedCategory ?? '').toLowerCase();
                    if ((cat == 'lista gold' || cat == 'lista negra') &&
                        (value == null || value.isEmpty)) {
                      return 'Los comentarios son obligatorios para esta categoría.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  icon: const Icon(Icons.send),
                  label: const Text('Enviar'),
                  onPressed: _submitPoi,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
