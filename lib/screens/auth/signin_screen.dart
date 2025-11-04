import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:myapp/services/auth_service.dart';
import 'package:myapp/screens/forgot_password_screen.dart';
import 'package:myapp/widgets/dialogs.dart';
import 'package:myapp/widgets/contact_dialog.dart';

class SignInScreen extends StatefulWidget {
  final VoidCallback onToggleAuthMode;
  const SignInScreen({super.key, required this.onToggleAuthMode});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;

  Future<void> _signIn() async {
    if (!mounted || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      await Provider.of<AuthService>(context, listen: false).signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      // On success, the AuthGate will handle navigation. We don't need to do anything here.
      // The widget might be unmounted after this, so we don't call setState.
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String errorMessage = 'An unexpected error occurred. Please try again or contact support.';
      if (e.code == 'invalid-credential') {
        errorMessage = 'The email or password you entered is incorrect.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'The email address is not valid.';
      } else if (e.code == 'user-disabled') {
        errorMessage = 'This user account has been disabled.';
      }
      showErrorDialog(context, 'Authentication Error', errorMessage);
      // Only stop loading if there was an error
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(
          context, 'Unexpected Error', 'An unexpected error occurred. Please try again later.');
      setState(() => _isLoading = false);
    }
    // We remove the finally block so that the loading state is only reset on error.
    // On success, the widget will be replaced by the AuthGate.
  }

  Future<void> _signInWithGoogle() async {
    if (!mounted || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      await Provider.of<AuthService>(context, listen: false).signInWithGoogle();
      // On success, AuthGate will navigate. No need to set state here.
    } catch (e) {
      if (!mounted) return;
      showErrorDialog(context, 'Authentication Error', 'An error occurred during Google sign-in. Please try again.');
      // Only stop loading if there was an error
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
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Correo Electrónico'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
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
                const SizedBox(height: 20),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: _signIn,
                        child: const Text('Iniciar Sesión', style: TextStyle(fontSize: 16)),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _signInWithGoogle,
                        icon: const FaIcon(FontAwesomeIcons.google,
                            color: Colors.white, size: 20),
                        label: const Text('Continuar con Google'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12)
                        ),
                      ),
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
                TextButton(
                  onPressed: () => showContactDialog(context),
                  child: const Text('Contacto'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
