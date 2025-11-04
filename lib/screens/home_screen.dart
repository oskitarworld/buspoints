import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart' as xml;
import 'dart:developer' as developer;

import 'package:myapp/config/app_config.dart';
import 'package:myapp/models/place.dart';
import 'package:myapp/widgets/app_drawer.dart';

class PlacePrediction {
  final String description;
  final String placeId;
  PlacePrediction({required this.description, required this.placeId});
  factory PlacePrediction.fromJson(Map<String, dynamic> json) {
    return PlacePrediction(
      description: json['description'] as String,
      placeId: json['place_id'] as String,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Completer<GoogleMapController> _mapController = Completer();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Set<Marker> _markers = {};
  final Set<String> _selectedCategories = {};
  List<Place> _allPlaces = [];

  bool _isCategoryListVisible = false;
  List<PlacePrediction> _predictions = [];
  Timer? _debounce;

  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(40.416775, -3.703790), // Madrid
    zoom: 12.0,
  );

  final Map<String, String> _categoryIconPaths = {
    'carga y descarga': 'assets/icons/carga_y_descarga.png',
    'parking de pago': 'assets/icons/parking.png',
    'zonas de espera o autocares': 'assets/icons/zona_espera.png',
    'gasolineras': 'assets/icons/gasolinera.png',
    'hoteles y restaurantes': 'assets/icons/hotel.png',
    'restricciones de altura o paso': 'assets/icons/restriccion.png',
    'otros': 'assets/icons/otros.png',
    'lista gold': 'assets/icons/lista_blanca.png',
    'lista negra': 'assets/icons/lista_negra.png',
  };

  final List<String> _orderedCategories = [
    'carga y descarga',
    'parking de pago',
    'zonas de espera o autocares',
    'gasolineras',
    'hoteles y restaurantes',
    'restricciones de altura o paso',
    'otros',
  ];
  final List<String> _specialCategories = ['lista gold', 'lista negra'];
  final Map<String, BitmapDescriptor> _markerIcons = {};

  @override
  void initState() {
    super.initState();
    _initializeMap();
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus && mounted) {
        setState(() => _predictions = []);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _initializeMap() async {
    await _preloadMarkerIcons();
    await _loadPlacesFromXml();
    _onDeselectAll();
  }

  Future<void> _loadPlacesFromXml() async {
    try {
      final String xmlString = await rootBundle.loadString('assets/data/pdis.xml');
      final document = xml.XmlDocument.parse(xmlString);
      final placemarks = document.findAllElements('Placemark');

      final List<Place> loadedPlaces = [];
      for (final placemark in placemarks) {
        final name = placemark.findElements('name').first.innerText;
        final description = placemark.findElements('description').first.innerText;
        final styleUrl = placemark.findElements('styleUrl').first.innerText;
        final coordinates = placemark.findElements('Point').first.findElements('coordinates').first.innerText.trim();
        final parts = coordinates.split(',');
        final lon = double.parse(parts[0]);
        final lat = double.parse(parts[1]);

        final category = _getCategoryFromStyle(styleUrl);

        loadedPlaces.add(Place(
          name: name,
          description: description,
          category: category,
          position: LatLng(lat, lon),
        ));
      }
      _allPlaces = loadedPlaces;
      _refreshMarkers();
    } catch (e, s) {
      developer.log(
        'Error loading or parsing XML',
        name: 'HomeScreen',
        error: e,
        stackTrace: s,
      );
    }
  }

  String _getCategoryFromStyle(String styleUrl) {
      if (styleUrl.contains('#icon-1704-0288D1')) return 'carga y descarga';
      if (styleUrl.contains('#icon-1704-F57C00')) return 'parking de pago';
      if (styleUrl.contains('#icon-1704-E65100')) return 'zonas de espera o autocares';
      if (styleUrl.contains('#icon-1704-503D36')) return 'gasolineras';
      if (styleUrl.contains('#icon-1704-9C27B0')) return 'hoteles y restaurantes';
      if (styleUrl.contains('#icon-1704-F44336')) return 'restricciones de altura o paso';
      if (styleUrl.contains('#icon-1704-7CB342')) return 'otros';
      if (styleUrl.contains('#icon-1704-F9A825')) return 'lista gold';
      if (styleUrl.contains('#icon-1704-000000')) return 'lista negra';
      return 'otros';
  }


  void _onMapCreated(GoogleMapController controller) {
    _mapController.complete(controller);
  }

  void _refreshMarkers() {
    final Set<Marker> newMarkers = {};
    for (final place in _allPlaces) {
        if (_selectedCategories.contains(place.category)) {
            newMarkers.add(Marker(
                markerId: MarkerId(place.name + place.position.toString()), // Unique ID
                position: place.position,
                infoWindow: InfoWindow(title: place.name, snippet: place.description),
                icon: _getIconForCategory(place.category),
                onTap: () => _onMarkerTapped(place),
            ));
        }
    }
    if (mounted) {
        setState(() {
            _markers = newMarkers;
        });
    }
  }

  Future<void> _preloadMarkerIcons() async {
    await Future.wait(_categoryIconPaths.entries.map((entry) async {
      final icon = await _getResizedMarkerIcon(entry.value, 100);
      if(icon != null) {
        _markerIcons[_normalizeCategory(entry.key)] = icon;
      }
    }));
  }

  BitmapDescriptor _getIconForCategory(String category) {
    return _markerIcons[category] ?? _markerIcons['otros'] ?? BitmapDescriptor.defaultMarker;
  }

  String _normalizeCategory(String category) {
    return category.toLowerCase().replaceAll('_', ' ').trim();
  }

  void _onCategorySelected(String category) {
    setState(() {
      final normalizedCategory = _normalizeCategory(category);
      _selectedCategories.clear();
      _selectedCategories.add(normalizedCategory);
      _isCategoryListVisible = false;
    });
    _refreshMarkers();
  }

  void _onSelectAll() {
    setState(() {
      _selectedCategories.clear();
      _selectedCategories.addAll(_categoryIconPaths.keys.map(_normalizeCategory));
      _isCategoryListVisible = false;
    });
    _refreshMarkers();
  }

  void _onDeselectAll() {
    setState(() {
      _selectedCategories.clear();
       _isCategoryListVisible = false;
    });
    _refreshMarkers();
  }

  void _toggleCategoryList() {
    setState(() => _isCategoryListVisible = !_isCategoryListVisible);
  }

  void _hideCategoryList() {
    if (_isCategoryListVisible) {
      setState(() => _isCategoryListVisible = false);
    }
  }

  Future<BitmapDescriptor?> _getResizedMarkerIcon(String path, int width) async {
    try {
      final ByteData data = await rootBundle.load(path);
      final Uint8List list = data.buffer.asUint8List();
      final ui.Codec codec = await ui.instantiateImageCodec(
        list,
        targetWidth: width,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        developer.log('Failed to get byte data for icon: $path', name: 'HomeScreen');
        return null;
      }
      final Uint8List resizedBytes = byteData.buffer.asUint8List();
      return BitmapDescriptor.bytes(resizedBytes);
    } catch (e, s) {
      developer.log(
        'Error loading or resizing marker icon: $path',
        name: 'HomeScreen',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }

   void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (mounted && query.length > 2) {
        _fetchPlacePredictions(query);
      } else if (mounted) {
        setState(() => _predictions = []);
      }
    });
  }

  Future<void> _fetchPlacePredictions(String input) async {
    const apiKey = AppConfig.googleMapsApiKey;
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': input,
      'key': apiKey,
      'language': 'es',
      'components': 'country:es',
    });
    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted && data['status'] == 'OK') {
          setState(() {
            _predictions = (data['predictions'] as List)
                .map((p) => PlacePrediction.fromJson(p))
                .toList();
          });
        }
      }
    } catch (e, s) {
       developer.log(
        'Failed to fetch place predictions',
        name: 'HomeScreen',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<void> _moveToPlace(String placeId) async {
    _searchFocusNode.unfocus();
    _searchController.clear();

    const apiKey = AppConfig.googleMapsApiKey;
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'key': apiKey,
      'fields': 'geometry',
      'language': 'es',
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          final location = data['result']['geometry']['location'];
          final controller = await _mapController.future;
          controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
            target: LatLng(location['lat'], location['lng']),
            zoom: 18.0,
          )));
        }
      }
    } catch (e, s) {
      developer.log(
        'Failed to move to place',
        name: 'HomeScreen',
        error: e,
        stackTrace: s,
      );
    }
  }

  Future<void> _goToMyLocation() async {
    final controller = await _mapController.future;
    final location = Location();
    final permission = await location.requestPermission();
    if (permission == PermissionStatus.granted) {
      try {
        final pos = await location.getLocation();
        if (pos.latitude != null && pos.longitude != null) {
          controller.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
            target: LatLng(pos.latitude!, pos.longitude!),
            zoom: 15.0,
          )));
        }
      } catch (e, s) {
         developer.log(
          'Failed to get current location',
          name: 'HomeScreen',
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  Future<void> _zoomIn() async {
    final controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    final controller = await _mapController.future;
    controller.animateCamera(CameraUpdate.zoomOut());
  }

  void _onMarkerTapped(Place place) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(place.name),
        content: SingleChildScrollView(
          child: ListBody(children: <Widget>[
            Text('Categoría: ${place.category.replaceAll('_', ' ')}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (place.description != null && place.description!.isNotEmpty)
              Text(place.description!),
            const SizedBox(height: 20),
            const Text('¿Obtener indicaciones para llegar a este lugar?'),
          ]),
        ),
        actions: [
          TextButton(
              child: const Text('Cerrar'),
              onPressed: () => Navigator.of(context).pop()),
          TextButton(
              child: const Text('Obtener Indicaciones'),
              onPressed: () => _launchMaps(
                  place.position.latitude, place.position.longitude)),
        ],
      ),
    );
  }

  void _onMapLongPress(LatLng position) {
    // This part might need adjustment if you keep the AddPoiScreen
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir Punto de Interés'),
        content: const Text('Funcionalidad no disponible en modo offline.'),
        actions: [
          TextButton(
            child: const Text('Cerrar'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _launchMaps(double lat, double lon) async {
    Navigator.of(context).pop();
    final uri = Uri.tryParse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
    if (uri != null) {
      try {
        final bool canLaunch = await canLaunchUrl(uri);
        if (canLaunch) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
           developer.log('Could not launch $uri', name: 'HomeScreen');
        }
      } catch (e, s) {
        developer.log(
          'Error launching maps',
          name: 'HomeScreen',
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.directions_bus, color: Colors.white),
            SizedBox(width: 10),
            Text('Bus Points'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _goToMyLocation,
            tooltip: 'Mi Ubicación',
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Stack(
              children: [
                GestureDetector(
                  onTap: _hideCategoryList,
                  child: GoogleMap(
                    mapType: MapType.normal,
                    initialCameraPosition: _initialCameraPosition,
                    markers: _markers,
                    onMapCreated: _onMapCreated,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    padding: const EdgeInsets.only(top: 80.0, bottom: 20.0),
                    onTap: (_) {
                      _searchFocusNode.unfocus();
                      _hideCategoryList();
                    },
                    onLongPress: _onMapLongPress,
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: _buildSearchCard(),
                ),
                if (_predictions.isNotEmpty)
                  Positioned(
                    top: 80,
                    left: 10,
                    right: 10,
                    child: _buildSuggestionsList(),
                  ),
                if (_isCategoryListVisible)
                  Center(
                    child: _buildCategoryList(),
                  ),
                Positioned(
                  bottom: 20,
                  left: 15,
                  child: _buildZoomButtons(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleCategoryList,
        backgroundColor: Colors.blueAccent,
        child: const Icon(
          Icons.search,
          color: Colors.white,
          size: 32,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

   Widget _buildCategoryList() {
    Widget buildCategoryTile(String category) {
      final label = category
          .split(' ')
          .map((word) =>
              word.isNotEmpty ? word[0].toUpperCase() + word.substring(1) : '')
          .join(' ');
      return ListTile(
        title: Text(label, textAlign: TextAlign.center),
        onTap: () => _onCategorySelected(category),
      );
    }

    return Card(
      elevation: 8.0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.7,
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Mostrar Todos',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: _onSelectAll,
            ),
            ListTile(
              title: const Text('Ocultar Todos',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: _onDeselectAll,
            ),
            const Divider(),
            ..._orderedCategories.map(buildCategoryTile),
            const Divider(),
            ..._specialCategories.map(buildCategoryTile),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FloatingActionButton(
          mini: true,
          onPressed: _zoomIn,
          backgroundColor: Colors.white,
          heroTag: 'zoomIn',
          child: const Icon(Icons.add, color: Colors.blue),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          mini: true,
          onPressed: _zoomOut,
          backgroundColor: Colors.white,
          heroTag: 'zoomOut',
          child: const Icon(Icons.remove, color: Colors.blue),
        ),
      ],
    );
  }

  Widget _buildSearchCard() {
    return Card(
      elevation: 4.0,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Buscar una dirección...',
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: () {
                    _searchController.clear();
                    if (mounted) {
                      setState(() => _predictions = []);
                    }
                    _searchFocusNode.unfocus();
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Card(
      elevation: 4.0,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: _predictions.length,
        itemBuilder: (context, index) {
          final prediction = _predictions[index];
          return ListTile(
            leading: const Icon(Icons.location_on_outlined, color: Colors.grey),
            title: Text(prediction.description),
            onTap: () => _moveToPlace(prediction.placeId),
          );
        },
      ),
    );
  }
}
