import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
// Biometric login removed — local_auth import deleted

import 'package:myapp/services/auth_service.dart';
import 'package:myapp/screens/forgot_password_screen.dart';
import 'package:myapp/widgets/dialogs.dart';
import 'package:myapp/widgets/contact_dialog.dart';
import 'package:myapp/widgets/branding_block.dart';

class SignInScreen extends StatefulWidget {
  final VoidCallback onToggleAuthMode;
  const SignInScreen({super.key, required this.onToggleAuthMode});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _userOrEmailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
  }


  Future<void> _signIn() async {
    if (!mounted || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      String email = _userOrEmailController.text.trim();
      if (!email.contains('@')) {
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'Debes ingresar un correo electrónico válido.'
        );
      }
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = await authService.signIn(
        email,
        _passwordController.text.trim(),
      );
      if (user != null) {
        // Consultar Firestore si el usuario está congelado
        final userDoc = await authService.firestore.collection('users').doc(user.uid).get();
        final data = userDoc.data();
        if (data != null && data['subscriptionFrozen'] == true) {
          if (mounted) {
            Navigator.of(context).pushReplacementNamed(
              '/frozen',
              arguments: {'username': data['name'] ?? email},
            );
            setState(() => _isLoading = false);
            return;
          }
        }
      }
      // On success, the AuthGate will handle navigation.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String errorMessage = 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo o contacta con el soporte.';
      if (e.code == 'invalid-credential') {
        errorMessage = 'El correo, usuario o la contraseña son incorrectos.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'La dirección de correo electrónico no es válida.';
      } else if (e.code == 'user-disabled') {
        errorMessage = 'Esta cuenta ha sido deshabilitada.';
      } else if (e.code == 'user-not-found') {
        errorMessage = 'No existe usuario con ese nombre.';
      } else if (e.code == 'already-logged-in') {
        // Custom error thrown by AuthService when a different active session exists
        errorMessage = 'Ya existe una sesión activa con esta cuenta en otro dispositivo.\n\n'
            'Si esto ocurre 3 veces, la cuenta será cancelada automáticamente sin derecho a reclamo.\n\n'
            'Si crees que se trata de un error, cierra sesión en el otro dispositivo o contacta con soporte inmediatamente.';
      } else if (e.code == 'account-locked') {
        errorMessage = 'Esta cuenta ha sido deshabilitada por seguridad debido a actividad sospechosa.\n\n'
            'Contacta con soporte para más información.';
      }
      showErrorDialog(context, 'Error de Autenticación', errorMessage);
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(
          context, 'Error Inesperado', 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo más tarde.');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/logo.png',
                  height: 150,
                ),
                const SizedBox(height: 40),
                Container(
                  constraints: const BoxConstraints(maxWidth: 350),
                  child: TextField(
                    controller: _userOrEmailController,
                    decoration: InputDecoration(
                      labelText: 'Correo electrónico',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxWidth: 350),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  Column(
                    children: [
                      SizedBox(
                        width: 200,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _signIn,
                          child: const Text('Iniciar Sesión', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      // Biometric login option removed
                    ],
                  ),
                TextButton(
                  onPressed: widget.onToggleAuthMode,
                  child: const Text('¿No tienes cuenta? Regístrate'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const ForgotPasswordScreen()),
                    );
                  },
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
                TextButton.icon(
                  onPressed: () {
                    showContactDialog(context);
                  },
                  icon: const Text('📧', style: TextStyle(fontSize: 18)),
                  label: const Text('Contacto'),
                ),
                const SizedBox(height: 24),
                // Branding block (logo + version + byline) - reusable widget
                const BrandingBlock(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}