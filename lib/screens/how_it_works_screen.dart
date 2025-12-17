import 'package:flutter/material.dart';

class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('¿Cómo funciona BusPoints?'),
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
            _sectionTitle('¿Qué es BusPoints?', Icons.info_outline),
            _sectionBody('BusPoints es una app colaborativa para encontrar y compartir puntos de interés (PDIs) útiles para conductores de autobús y guías turísticos.'),
            const SizedBox(height: 20),
            _sectionTitle('Buscar PDIs', Icons.search),
            _sectionBody('Utiliza el mapa para explorar PDIs cercanos. Puedes filtrar por categorías y buscar direcciones específicas.'),
            const SizedBox(height: 20),
            _sectionTitle('Añadir un PDI', Icons.add_location_alt),
            _sectionBody('Pulsa largo en el mapa para proponer un nuevo PDI. Completa los datos y envía tu sugerencia. Los administradores revisarán y aprobarán los PDIs enviados.'),
            const SizedBox(height: 20),
            _sectionTitle('Recompensas', Icons.emoji_events),
            _sectionBody('Si el PDI es válido y no está repetido, recibirás recompensa.'),
            const SizedBox(height: 20),
            _sectionTitle('Mensajes y contacto', Icons.mail_outline),
            _sectionBody('Puedes enviar y recibir mensajes desde el menú lateral. También puedes contactar con el equipo BusPoints desde la opción "Contacto".'),
            const SizedBox(height: 20),
            _sectionTitle('PDIs especiales: Lista Blanca, Gold y Negra', Icons.star),
            _sectionBody('• Lista Blanca: PDIs recomendados por la comunidad, verificados y de alta utilidad.\n• Lista Gold: PDIs de la Lista Blanca que, además, tienen al menos 3 valoraciones aprobadas y una valoración media de 4.0 o superior; se incluyen automáticamente en la Lista Gold para destacar los lugares más valorados.\n• Lista Negra: Sitios añadidos por otros usuarios donde han tratado mal a los profesionales o clientes.'),
            const SizedBox(height: 20),
            _sectionTitle('¿Tienes dudas o sugerencias?', Icons.help_outline),
            _sectionBody('Contacta con nosotros en app@buspoints.net o usa el formulario de contacto en la app.'),
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

  static Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueGrey, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            softWrap: true,
          ),
        ),
      ],
    );
  }

  static Widget _sectionBody(String body) {
    return Padding(
      padding: const EdgeInsets.only(left: 30.0, top: 4.0),
      child: Text(
        body,
        style: const TextStyle(fontSize: 15, color: Colors.black87),
      ),
    );
  }
}
