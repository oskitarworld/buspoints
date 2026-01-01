import 'package:flutter/services.dart';

class NativeStreetView {
  static const MethodChannel _channel = MethodChannel('com.app.buspoints/streetview');

  /// Try to open native Street View. Returns true if the platform handled it.
  /// If lat or lng is null the method returns false immediately.
  static Future<bool> open({required double? lat, required double? lng}) async {
    if (lat == null || lng == null) return false;
    try {
      await _channel.invokeMethod('openStreetView', {'lat': lat, 'lng': lng});
      return true;
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
