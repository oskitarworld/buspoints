import 'dart:async';

/// Simple singleton service to broadcast map refresh events across screens.
class MapRefreshService {
  MapRefreshService._internal();
  static final MapRefreshService _instance = MapRefreshService._internal();
  static MapRefreshService get instance => _instance;

  final StreamController<void> _ctrl = StreamController<void>.broadcast();

  Stream<void> get onRefresh => _ctrl.stream;

  void requestRefresh() {
    try {
      _ctrl.add(null);
    } catch (_) {}
  }

  void dispose() {
    _ctrl.close();
  }
}
