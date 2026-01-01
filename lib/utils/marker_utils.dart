import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Genera un BitmapDescriptor con un círculo de color y un número centrado.
/// size es el ancho/alto en píxeles del bitmap.
Future<BitmapDescriptor> createNumberedMarker(int number, {Color color = Colors.blue, int size = 120}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final double radius = size / 2.0;

  // Fondo (círculo)
  final paint = Paint()..color = color;
  canvas.drawCircle(Offset(radius, radius), radius, paint);

  // Texto (número)
  final textPainter = TextPainter(textDirection: TextDirection.ltr);
  final textStyle = TextStyle(color: Colors.white, fontSize: radius * 0.9, fontWeight: FontWeight.bold);
  final textSpan = TextSpan(text: number.toString(), style: textStyle);
  textPainter.text = textSpan;
  textPainter.layout();
  final offset = Offset(radius - (textPainter.width / 2), radius - (textPainter.height / 2));
  textPainter.paint(canvas, offset);

  final ui.Image image = await recorder.endRecording().toImage(size, size);
  final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final Uint8List bytes = byteData!.buffer.asUint8List();
  // Use the newer bytes factory (replaces deprecated fromBytes)
  return BitmapDescriptor.bytes(bytes);
}
