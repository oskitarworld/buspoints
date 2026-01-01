import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

import 'package:myapp/firebase_options.dart';
import 'package:myapp/screens/home_screen.dart';
import 'package:myapp/services/auth_service.dart';
// NOTE: moved user role gating into `lib/widgets/auth_gate.dart`.
import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:myapp/screens/splash_screen.dart';
import 'package:myapp/screens/frozen_account_screen.dart';
// auth_gate is used by SplashScreen; not directly referenced here.

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initializationError;
  // Inicializar FCM
  if (kIsWeb) {
    // Registrar el service worker para notificaciones web
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      developer.log('[APP START] Firebase initialized at ${DateTime.now().toIso8601String()}', name: 'main');
      // Disable local persistence temporarily to diagnose long local DB operations.
      // This prevents Firestore from using its local SQLite cache while we debug.
      FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
      // Registrar el service worker (solo web)
      // El archivo ya existe en la raíz del proyecto
      await FirebaseMessaging.instance.setDeliveryMetricsExportToBigQuery(true);
    } catch (e) {
      developer.log('Error inicializando FCM en web: $e', name: 'main', error: e);
    }
  }
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Inicializar FCM en móvil/escritorio
    if (!kIsWeb) {
      await FirebaseMessaging.instance.requestPermission();
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    }
    // TEST DE CONEXIÓN FIRESTORE
    final firestore = FirebaseFirestore.instance;
    try {
      // Disable local persistence temporarily on mobile as well while debugging
      // long local DB operations (SQLite). Re-enable once validated.
      try {
        FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
        developer.log('[APP START] Firestore persistence disabled for debug', name: 'main');
      } catch (e) {
        developer.log('Could not change Firestore settings: $e', name: 'main', error: e);
      }

      final snapshot = await firestore.collection('places').limit(1).get();
      developer.log('[TEST FIRESTORE] Conexión OK. Docs encontrados: ${snapshot.docs.length}', name: 'main');
      if (snapshot.docs.isNotEmpty) {
        developer.log('[TEST FIRESTORE] Primer doc: ${snapshot.docs.first.data()}', name: 'main');
      }
    } catch (e) {
      developer.log('[TEST FIRESTORE] ERROR: ${e.toString()}', name: 'main', error: e);
    }
  } catch (e) {
    initializationError = e;
  }
  // Install global error handlers so uncaught exceptions are logged and
  // the app doesn't show the red error screen in production-like flows.
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log('Uncaught Flutter error: ${details.exception}', name: 'main', error: details.exception, stackTrace: details.stack);
    // Do NOT call FlutterError.presentError(details) here to avoid the
    // red-screen overlay in debug; we still want the error logged.
  };

  // Customize the ErrorWidget shown in the UI (the red error box) so that
  // Firestore permission errors (which we expect in some deployments) do
  // not surface as a blocking red box to users. We still log the error.
  // Globally suppress the visible ErrorWidget (red screen) and replace it
  // with a non-blocking empty widget. All errors are still logged using
  // developer.log so they can be reviewed in logs. The user requested that
  // the red error screen not be shown on devices.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    developer.log('Suppressed ErrorWidget shown to user: ${details.exception}', name: 'main', error: details.exception, stackTrace: details.stack);
    // Return a tiny, non-blocking widget so the app UI keeps rendering.
    return const SizedBox.shrink();
  };

  runZonedGuarded(() {
    runApp(MyApp(initializationError: initializationError));
  }, (error, stack) {
    developer.log('Uncaught zone error: $error', name: 'main', error: error, stackTrace: stack);
  });
}

// Mostrar notificaciones push en primer plano
void setupFCMForegroundNotifications() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      final notification = message.notification!;
      // Mostrar un SnackBar global con el mensaje
      final nav = navigatorKey.currentState;
      if (nav != null && nav.mounted) {
        final messenger = ScaffoldMessenger.of(nav.context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(notification.title != null
                ? '${notification.title}: ${notification.body ?? ''}'
                : notification.body ?? ''),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      // Note: badge update on Android launchers varies by device/launcher.
      // We rely on APNs badge (iOS) via server `apns.aps.badge` and send
      // `data.badge` so the app may update a launcher badge when in foreground.
    }
  });
}


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final Object? initializationError;
  const MyApp({super.key, this.initializationError});

  @override
  Widget build(BuildContext context) {
    if (initializationError != null) {
      return ErrorDisplayApp(error: initializationError!);
    }

    // Inicializar escucha de notificaciones en primer plano
    setupFCMForegroundNotifications();
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        StreamProvider<User?>(
          create: (context) => context.read<AuthService>().authStateChanges,
          initialData: null,
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Bus Points',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.light,
          ),
        ),
        themeMode: ThemeMode.light,
        home: const SplashScreen(),
        routes: {
          '/home': (context) => const HomeScreen(),
          '/auth': (context) => const AuthScreen(),
          '/frozen': (context) => const FrozenAccountScreen(username: 'usuario'),
        },
      ),
    );
  }
}

// AuthGate and UserRoleGate moved to `lib/widgets/auth_gate.dart` to avoid
// circular imports between `main.dart` and `splash_screen.dart`.

class ErrorDisplayApp extends StatelessWidget {
  final Object error;

  const ErrorDisplayApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Error de Inicialización'),
          backgroundColor: Colors.red,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Ocurrió un error al iniciar la aplicación:\n\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.red),
            ),
          ),
        ),
      ),
    );
  }
}
