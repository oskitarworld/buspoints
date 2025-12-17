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
      print('Error inicializando FCM en web: $e');
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
        // ignore: avoid_print
        print('Could not change Firestore settings: $e');
      }

      final snapshot = await firestore.collection('places').limit(1).get();
      print('[TEST FIRESTORE] Conexión OK. Docs encontrados: \\${snapshot.docs.length}');
      if (snapshot.docs.isNotEmpty) {
        print('[TEST FIRESTORE] Primer doc: \\${snapshot.docs.first.data()}');
      }
    } catch (e) {
      print('[TEST FIRESTORE] ERROR: \\${e.toString()}');
    }
  } catch (e) {
    initializationError = e;
  }
  runApp(MyApp(initializationError: initializationError));
}

// Mostrar notificaciones push en primer plano
void setupFCMForegroundNotifications() {
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) {
      final notification = message.notification!;
      // Mostrar un SnackBar global con el mensaje
      final context = navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
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
