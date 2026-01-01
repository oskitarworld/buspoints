import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Small compatibility helper for web: some versions of the firebase-js SDK
/// have reported internal assertion failures when many real-time listeners
/// (especially collectionGroup listeners) are active. To mitigate that class
/// of errors we expose a helper that returns a `Stream<QuerySnapshot>` which
/// uses the native query.snapshots() on native platforms but falls back to
/// a periodic polling using query.get() on web.
Stream<QuerySnapshot<Map<String, dynamic>>> querySnapshotsCompat(
  Query<Map<String, dynamic>> query, {
  Duration pollingInterval = const Duration(seconds: 6),
  int maxRetries = 5,
}) async* {
  if (!kIsWeb) {
    // Native platforms use the Firestore SDK's real-time snapshots.
    yield* query.snapshots();
    return;
  }

  // Web: implement a resilient polling loop that logs errors and retries.
  var retryCount = 0;
  while (true) {
    try {
      final snapshot = await query.get();
      yield snapshot;
      // Reset retry counter after a successful fetch.
      retryCount = 0;
    } catch (e, s) {
      developer.log('querySnapshotsCompat: error during query.get(): $e',
          name: 'firestore_web_compat', error: e, stackTrace: s);
      retryCount++;
      // If we keep failing, back off a bit to avoid tight error loops.
      if (retryCount > maxRetries) {
        final backoff = Duration(seconds: 10);
        developer.log('querySnapshotsCompat: backing off for ${backoff.inSeconds}s', name: 'firestore_web_compat');
        await Future.delayed(backoff);
      }
    }

    // Wait before the next polling iteration.
    await Future.delayed(pollingInterval);
  }
}

/// Convenience helper that converts a Firestore query into a stream of
/// integers representing the document count for that query. It uses the
/// querySnapshotsCompat helper under the hood so it behaves safely on web.
Stream<int> queryCountStream(
  Query<Map<String, dynamic>> query, {
  Duration pollingInterval = const Duration(seconds: 6),
}) {
  return querySnapshotsCompat(query, pollingInterval: pollingInterval)
      .transform(StreamTransformer.fromHandlers(
    handleData: (QuerySnapshot<Map<String, dynamic>> snap, EventSink<int> sink) {
      sink.add(snap.docs.length);
    },
    handleError: (error, stackTrace, EventSink<int> sink) {
      developer.log('queryCountStream error: $error', name: 'firestore_web_compat', error: error, stackTrace: stackTrace);
      // On error return a safe fallback count (0) so UI stays stable.
      sink.add(0);
    },
  ));
}

/// Wrap a stream and catch/log errors so they don't propagate as uncaught
/// errors in the UI layer. Useful for defensive shielding when the underlying
/// stream source (e.g. Firestore web watch) may emit internal errors.
Stream<T> resilientStream<T>(Stream<T> s, {String name = 'resilientStream'}) {
  // Use a small StreamController wrapper instead of StreamTransformer to
  // avoid runtime generic-type mismatches between different
  // DocumentSnapshot/QuerySnapshot specializations. The controller listens
  // to the source stream, forwards data events and logs+swallows errors.
  final controller = StreamController<T>.broadcast();
  StreamSubscription<T>? sub;

  controller.onListen = () {
    sub = s.listen(
      (data) {
        if (!controller.isClosed) controller.add(data);
      },
      onError: (Object error, StackTrace? stackTrace) {
        developer.log('resilientStream caught error: $error', name: name, error: error, stackTrace: stackTrace);
        // swallow error
      },
      onDone: () {
        if (!controller.isClosed) controller.close();
      },
      cancelOnError: false,
    );
  };

  controller.onCancel = () async {
    try {
      await sub?.cancel();
    } catch (e, s2) {
      developer.log('resilientStream cancel error: $e', name: name, error: e, stackTrace: s2);
    }
    if (!controller.isClosed) await controller.close();
  };

  return controller.stream;
}
