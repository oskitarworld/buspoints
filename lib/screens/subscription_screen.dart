import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:myapp/services/auth_service.dart';
import 'package:myapp/screens/auth/auth_screen.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? 'tu email';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Membresía Expirada'),
        automaticallyImplyLeading: false, // No back button
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await Provider.of<AuthService>(context, listen: false).signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false,
                  );
                }
              } catch (e) {
                // fallback to direct signOut if provider fails
                await FirebaseAuth.instance.signOut();
              }
            },
            tooltip: 'Cerrar Sesión',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 20),
            Icon(FontAwesomeIcons.fileInvoiceDollar,
                color: Theme.of(context).colorScheme.primary, size: 60),
            const SizedBox(height: 20),
            Text(
              'Tu membresía ha caducado',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Para renovar tu acceso por un año más, por favor sigue estos pasos:',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, color: Colors.black87),
            ),
            const SizedBox(height: 30),
            _buildInstructionCard(context, userEmail),
            const SizedBox(height: 20),
            const Text(
              'Una vez verificado el pago, un administrador activará tu cuenta. Este proceso puede tardar hasta 24 horas.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.black54),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await Provider.of<AuthService>(context, listen: false).signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                      (route) => false,
                    );
                  }
                } catch (e) {
                  await FirebaseAuth.instance.signOut();
                }
              },
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('Cerrar Sesión',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.grey[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionCard(BuildContext context, String userEmail) {
    // canonical number without spaces (used for copying)
    const bizumNumberRaw = '602418045';
    // display with spaces for readability
    const bizumNumber = '602 41 80 45';
    const subscriptionPrice = '15 €'; // Updated Price

    return Card(
      elevation: 4,
      shadowColor: Colors.black.withAlpha(26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Instrucciones de Pago',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 24),
            _buildInstructionRow(context, 'Servicio:', 'Bizum',
                icon: FontAwesomeIcons.mobileScreenButton),
            const SizedBox(height: 16),
      _buildInstructionRow(context, 'Teléfono:', bizumNumber,
        icon: FontAwesomeIcons.phone, canCopy: true, copyValue: bizumNumberRaw),
            const SizedBox(height: 16),
            _buildInstructionRow(context, 'Importe:', subscriptionPrice,
                icon: FontAwesomeIcons.euroSign),
            const SizedBox(height: 16),
            _buildInstructionRow(context, 'Concepto:', userEmail,
                icon: FontAwesomeIcons.solidEnvelope, canCopy: true),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionRow(BuildContext context, String label, String value,
    {required IconData icon, bool canCopy = false, String? copyValue}) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start, // Align to the top for multi-line text
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2.0), // Adjust icon alignment
          child: Icon(icon,
              size: 18, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(width: 16), // Add some space
        Expanded(
          // Use Expanded to allow text to wrap
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal),
          ),
        ),
        if (canCopy)
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
            child: GestureDetector(
              onTap: () {
                final textToCopy = (copyValue ?? value).replaceAll(RegExp(r"\\D"), '');
                Clipboard.setData(ClipboardData(text: textToCopy));
                // Custom styled floating SnackBar with icon
                final snack = SnackBar(
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  duration: const Duration(milliseconds: 1400),
                  content: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Teléfono copiado al portapapeles',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                );
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(snack);
              },
              child: Icon(Icons.copy, size: 18, color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    );
  }
}
