import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

// This screen is not currently in use, but the faulty import within it was breaking
// the entire application build. It has been corrected to prevent compile-time errors.

class SubscriptionStatusScreen extends StatelessWidget {
  final String status;

  const SubscriptionStatusScreen({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    String title;
    String message;
    IconData icon;

    switch (status) {
      case 'paused':
        title = 'Suscripción Pausada';
        message =
            'Tu acceso ha sido pausado temporalmente. Por favor, contacta con un administrador para reactivar tu cuenta.';
        icon = Icons.pause_circle_filled;
        break;
      case 'expired':
        title = 'Suscripción Caducada';
        message =
            'Tu suscripción ha caducado. Para renovarla y seguir usando la aplicación, por favor, contacta con un administrador.';
        icon = Icons.error;
        break;
      default:
        title = 'Acceso Restringido';
        message =
            'Hay un problema con tu cuenta. Por favor, contacta con un administrador.';
        icon = Icons.lock;
        break;
    }

    return Scaffold(
      backgroundColor: Colors.blueGrey[50],
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.blueGrey[900],
        automaticallyImplyLeading: false, // No back button
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 80, color: Colors.blueGrey[700]),
              const SizedBox(height: 20),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar Sesión'),
                onPressed: () => FirebaseAuth.instance.signOut(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
