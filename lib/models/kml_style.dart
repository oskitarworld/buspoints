import 'package:flutter/material.dart';

// Represents the style information for a KML placemark.
class KmlStyle {
  final String? iconUrl;
  final Color color;
  final double scale;

  KmlStyle({
    this.iconUrl,
    this.color = Colors.blue, // Default color if not specified
    this.scale = 1.0, // Default scale if not specified
  });
}
