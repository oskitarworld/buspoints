import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Política de Privacidad'),
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
              'Política de Privacidad – BusPoints',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            _sectionTitle('1. Responsable del tratamiento'),
            _sectionBody('BusPoints • app@buspoints.net • www.buspoints.net'),
            const SizedBox(height: 12),
            _sectionTitle('2. Datos que recopilamos'),
            _sectionBody('Datos de uso, ubicación aproximada, sugerencias enviadas, datos de suscripción.'),
            const SizedBox(height: 12),
            _sectionTitle('3. Finalidad'),
            _sectionBody('Mejorar la App, mostrar puntos de interés, gestionar recompensas, analizar estadísticas.'),
            const SizedBox(height: 12),
            _sectionTitle('4. Base legal'),
            _sectionBody('Ejecución del servicio, interés legítimo y consentimiento.'),
            const SizedBox(height: 12),
            _sectionTitle('5. Cesión de datos'),
            _sectionBody('Solo a proveedores tecnológicos bajo confidencialidad.'),
            const SizedBox(height: 12),
            _sectionTitle('6. Conservación'),
            _sectionBody('Solo el tiempo necesario.'),
            const SizedBox(height: 12),
            _sectionTitle('7. Derechos'),
            _sectionBody('Acceso, rectificación, supresión, oposición, portabilidad. Contacto: app@buspoints.net'),
            const SizedBox(height: 12),
            _sectionTitle('8. Seguridad'),
            _sectionBody('Medidas técnicas y organizativas.'),
            const SizedBox(height: 12),
            _sectionTitle('9. Cambios'),
            _sectionBody('La versión vigente estará en la web.'),
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
