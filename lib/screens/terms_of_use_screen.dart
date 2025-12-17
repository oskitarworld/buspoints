import 'package:flutter/material.dart';

class TermsOfUseScreen extends StatelessWidget {
  const TermsOfUseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Términos de Uso'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Términos de Uso de BusPoints',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              'Bienvenido/a a BusPoints (la “App”). Al utilizarla aceptas estos Términos de Uso (“Términos”).',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            _sectionTitle('1. Sobre la información que ofrecemos'),
            _sectionBody('1.1. BusPoints proporciona información de puntos de interés cercanos a paradas y rutas de autobús.'),
            _sectionBody('1.2. No podemos garantizar que la información sea siempre exacta, completa o reciente, por lo que debe utilizarse como orientación general. No nos hacemos responsables de puntos erróneos, fallos en ubicaciones ni daños derivados del uso.'),
            const SizedBox(height: 16),
            _sectionTitle('2. Aportaciones del usuario'),
            _sectionBody('2.1. Al enviar información aceptas que podamos usarla para mejorar el servicio.'),
            const SizedBox(height: 16),
            _sectionTitle('3. Limitación de responsabilidad'),
            _sectionBody('No somos responsables de errores, fallos técnicos, interrupciones, pérdidas de datos o daños derivados del uso de la App. La App puede incluir enlaces de terceros ajenos a nuestro control.'),
            const SizedBox(height: 16),
            _sectionTitle('4. Modificaciones'),
            _sectionBody('Podemos actualizar estos Términos.'),
            const SizedBox(height: 16),
            _sectionTitle('5. Uso permitido'),
            _sectionBody('Uso legal y correcto. Prohibida la manipulación, copia masiva o uso ilícito.'),
            const SizedBox(height: 16),
            _sectionTitle('6. Datos personales'),
            _sectionBody('Tratados según nuestra Política de Privacidad.'),
            const SizedBox(height: 16),
            _sectionTitle('7. Legislación aplicable'),
            _sectionBody('Se rige por la legislación del país o región del responsable.'),
            const SizedBox(height: 16),
            _sectionTitle('8. Contacto'),
            _sectionBody('app@buspoints.net'),
            const SizedBox(height: 32),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('Cerrar'),
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
    );
  }

  static Widget _sectionBody(String body) {
    return Padding(
      padding: const EdgeInsets.only(left: 12.0, top: 4.0),
      child: Text(
        body,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
    );
  }
}
