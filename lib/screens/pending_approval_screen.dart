import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:myapp/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/auth/auth_screen.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userEmail = FirebaseAuth.instance.currentUser?.email ?? 'tu-correo@ejemplo.com';
    const bizumNumberRaw = '602418045';
    const bizumNumberDisplay = '602 41 80 45';
    const subscriptionPrice = '15 €';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Bus Points'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: () => authService.signOut(),
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24.0, 20.0, 24.0, 24.0 + MediaQuery.of(context).padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Icon(Icons.check_circle_outline_rounded, size: 72, color: Colors.green),
              const SizedBox(height: 12),
              Text(
                '¡Casi listo!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold) ?? const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                'Tu cuenta ha sido creada (o tu periodo de prueba ha finalizado) y está pendiente de aprobación por un administrador. Para activar tu acceso, realiza un pago de 15€ vía Bizum usando tu correo de registro como destino. En cuanto recibamos la confirmación activaremos tu cuenta.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.45),
              ),
              const SizedBox(height: 20),

              // Instruction card styled like SubscriptionScreen
              Card(
                elevation: 4,
                shadowColor: Colors.black.withAlpha(26),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: Text('Instrucciones de Pago', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      const Divider(height: 20),
                      _buildInstructionRow(context, 'Teléfono:', bizumNumberDisplay, icon: Icons.phone, canCopy: true, copyValue: bizumNumberRaw),
                      const SizedBox(height: 12),
                      _buildInstructionRow(context, 'Importe:', subscriptionPrice, icon: Icons.euro),
                      const SizedBox(height: 12),
                      _buildInstructionRow(context, 'Concepto:', userEmail, icon: Icons.alternate_email, canCopy: true, copyValue: userEmail),
                      const SizedBox(height: 6),
                      const Text('Usa tu correo como concepto en Bizum. Cuando verifiquemos el pago activaremos tu cuenta.', style: TextStyle(fontSize: 13, color: Colors.black54), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 22),

              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await Provider.of<AuthService>(context, listen: false).signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (route) => false);
                    }
                  } catch (e) {
                    await FirebaseAuth.instance.signOut();
                  }
                },
                icon: const Icon(Icons.logout, color: Colors.white),
                label: const Text('Cerrar Sesión', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionRow(BuildContext context, String label, String value, {required IconData icon, bool canCopy = false, String? copyValue}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2.0), child: Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal))),
        if (canCopy)
          Padding(
            padding: const EdgeInsets.only(left: 8.0, top: 2.0),
            child: GestureDetector(
              onTap: () {
                final textToCopy = (copyValue ?? value).replaceAll(RegExp(r"\\D"), '');
                Clipboard.setData(ClipboardData(text: textToCopy));
                final snack = SnackBar(
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  duration: const Duration(milliseconds: 1400),
                  content: Row(
                    children: const [
                      Icon(Icons.check_circle, color: Colors.white),
                      SizedBox(width: 12),
                      Expanded(child: Text('Copiado al portapapeles', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                    ],
                  ),
                );
                ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(snack);
              },
              child: Icon(Icons.copy, size: 18, color: Theme.of(context).colorScheme.primary),
            ),
          ),
      ],
    );
  }
}


