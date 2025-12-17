import 'package:flutter/material.dart';
import 'package:myapp/widgets/contact_dialog.dart';

class FrozenAccountScreen extends StatelessWidget {
  final String username;
  const FrozenAccountScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Cuenta congelada'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.blueGrey),
              const SizedBox(height: 24),
              const Text(
                'Cuenta congelada',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Para más información, manda un correo a app@buspoints.es indicando tu nombre de usuario ("$username") y el motivo de tu consulta.',
                style: const TextStyle(fontSize: 18, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: const Icon(Icons.email_outlined),
                label: const Text('Contactar'),
                onPressed: () {
                  showContactDialog(context);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Recuerda importar 'package:url_launcher/url_launcher.dart' en tu pubspec.yaml y en el archivo donde uses launchUrl.