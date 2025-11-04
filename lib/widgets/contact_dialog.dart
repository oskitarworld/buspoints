
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

void showContactDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Contacto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Enviar correo'),
              onTap: () {
                _launchURL('mailto:app@buspoints.net');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.web),
              title: const Text('Ir a la web de contacto'),
              onTap: () {
                _launchURL('https://buspoints.net/contacto/');
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('www.buspoints.net'),
              onTap: () {
                _launchURL('https://buspoints.net');
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _launchURL(String url) async {
  final Uri uri = Uri.parse(url);
  if (!await launchUrl(uri)) {
    throw 'No se pudo abrir $url';
  }
}
