
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:myapp/firebase_options.dart';
import 'package:myapp/models/user_model.dart';
import 'package:myapp/screens/home_screen.dart';
import 'package:myapp/services/auth_service.dart';
import 'package:myapp/screens/pending_approval_screen.dart';
import 'package:myapp/screens/verify_email_screen.dart';
import 'package:myapp/screens/subscription_screen.dart';
import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:myapp/screens/splash_screen.dart'; // Importa la nueva pantalla

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initializationError;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    initializationError = e;
  }
  runApp(MyApp(initializationError: initializationError));
}

class MyApp extends StatelessWidget {
  final Object? initializationError;
  const MyApp({super.key, this.initializationError});

  @override
  Widget build(BuildContext context) {
    if (initializationError != null) {
      return ErrorDisplayApp(error: initializationError!);
    }

    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        StreamProvider<User?>(
          create: (context) => context.read<AuthService>().authStateChanges,
          initialData: null,
        ),
      ],
      child: MaterialApp(
        title: 'Bus Points',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.light,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blueGrey,
            brightness: Brightness.dark,
          ),
        ),
        themeMode: ThemeMode.system,
        home: const SplashScreen(), // <<--- AQUÍ ESTÁ EL CAMBIO
        routes: {
          '/home': (context) => const HomeScreen(),
          '/auth': (context) => const AuthScreen(),
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);

    if (user == null) {
      return const AuthScreen();
    }

    if (!user.emailVerified) {
      return const VerifyEmailScreen();
    }

    return UserRoleGate(user: user);
  }
}

class UserRoleGate extends StatelessWidget {
  final User user;

  const UserRoleGate({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // This can happen briefly if a user is deleted from the backend.
          // Signing out is a good safe action.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<AuthService>().signOut();
          });
          return const Scaffold(body: Center(child: Text('Usuario no encontrado. Cerrando sesión...')));
        }

        final userModel = UserModel.fromFirestore(snapshot.data!);

        if (userModel.role == 'admin') {
          return const HomeScreen();
        }

        switch (userModel.status) {
          case 'approved':
            return userModel.isSubscriptionActive
                ? const HomeScreen()
                : const SubscriptionScreen();
          case 'pending':
          default:
            return const PendingApprovalScreen();
        }
      },
    );
  }
}

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
