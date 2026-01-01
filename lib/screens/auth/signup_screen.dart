import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:myapp/services/auth_service.dart';
import 'package:myapp/widgets/dialogs.dart';
import 'package:myapp/screens/terms_of_use_screen.dart';
import 'package:myapp/screens/verify_email_screen.dart';

class SignUpScreen extends StatefulWidget {
  final VoidCallback onToggleAuthMode;
  const SignUpScreen({super.key, required this.onToggleAuthMode});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _acceptedTerms = false;
  bool _wantsTrial = false;

  void _signUp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_acceptedTerms) {
      setState(() {});
      return;
    }
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final user = await Provider.of<AuthService>(context, listen: false).register(
        _nameController.text,
        _emailController.text,
        _phoneController.text,
        _passwordController.text,
        wantsTrial: _wantsTrial,
      );
      if (mounted && user != null) {
        // Ensure navigation happens after the current frame to avoid
        // interfering with any rebuilds triggered by auth state listeners.
        debugPrint('[SignUpScreen] Registro completado para ${user.email}; programando navegación a VerifyEmailScreen');
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          try {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const VerifyEmailScreen()),
            );
          } catch (e, st) {
            debugPrint('[SignUpScreen] Error al navegar a VerifyEmailScreen: $e\n$st');
            // Fallback: show a dialog instructing the user to ir a la pantalla de verificación manualmente
            if (mounted) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Registro completado'),
                  content: const Text('Tu cuenta se ha creado. Por favor, revisa tu correo para verificarla. Si no recibes el correo, ve a la pantalla de verificación desde el menú de inicio de sesión.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
                  ],
                ),
              );
            }
          }
        });
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String errorMessage = 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo o contacta con el soporte.';
      if (e.code == 'weak-password') {
        errorMessage = 'La contraseña proporcionada es demasiado débil.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'Ya existe una cuenta para ese correo electrónico.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'La dirección de correo electrónico no es válida.';
      } else if (e.code == 'username-already-in-use') {
        errorMessage = 'El nombre de usuario ya está en uso. Elige otro.';
      } else if (e.code == 'phone-already-in-use') {
        errorMessage = 'Ya existe una cuenta para ese teléfono.';
      } else if (e.code == 'firestore-error') {
        // Surface Firestore errors (permission issues, connectivity) to the user
        errorMessage = e.message ?? 'No se pudo completar la verificación de datos. Por favor, inténtalo de nuevo más tarde.';
      }
      showErrorDialog(context, 'Error de Registro', errorMessage);
    } catch (e) {
      if (mounted) {
        showErrorDialog(
            context, 'Error Inesperado', 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo más tarde.');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Image.asset(
                    'assets/images/logo.png',
                    height: 150,
                  ),
                  const SizedBox(height: 40),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'El nombre es obligatorio';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'El teléfono es obligatorio';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Correo Electrónico',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'El correo electrónico es obligatorio';
                        }
                        if (!value.contains('@')) {
                          return 'Ingresa un correo electrónico válido';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: TextFormField(
                      controller: _passwordController,
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
                      obscureText: !_isPasswordVisible,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'La contraseña es obligatoria';
                        }
                        if (value.length < 6) {
                          return 'La contraseña debe tener al menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: TextFormField(
                      controller: _confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirmar Contraseña',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                            });
                          },
                        ),
                      ),
                      obscureText: !_isConfirmPasswordVisible,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Confirma tu contraseña';
                        }
                        if (value != _passwordController.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Trial request checkbox placed just above the terms acceptance as requested
                  Container(
                    constraints: const BoxConstraints(maxWidth: 350),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _wantsTrial,
                          onChanged: (val) async {
                            final newVal = val ?? false;
                            if (newVal) {
                              // Show a professional confirmation dialog when requesting trial
                              await showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Prueba gratuita'),
                                  content: const Text('Has solicitado una prueba gratuita. Recuerda que sólo puedes solicitar una única prueba por dispositivo.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Aceptar')),
                                  ],
                                ),
                              );
                            }
                            setState(() {
                              _wantsTrial = newVal;
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              // Toggle when tapping the label area for better UX
                              final newVal = !_wantsTrial;
                              if (newVal) {
                                await showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('Prueba gratuita'),
                                    content: const Text('Has solicitado una prueba gratuita. Recuerda que sólo puedes solicitar una única prueba por dispositivo.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Aceptar')),
                                    ],
                                  ),
                                );
                              }
                              setState(() {
                                _wantsTrial = newVal;
                              });
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text('Prueba gratuita', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                                SizedBox(height: 2),
                                Text('48 horas gratuitas. Sólo 1 prueba por dispositivo.', style: TextStyle(fontSize: 12, color: Colors.black54)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Checkbox(
                          value: _acceptedTerms,
                          onChanged: (val) {
                            setState(() {
                              _acceptedTerms = val ?? false;
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const TermsOfUseScreen(),
                              ),
                            );
                          },
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(color: Colors.black, fontSize: 14),
                              children: [
                                TextSpan(text: 'Acepto los '),
                                TextSpan(
                                  text: 'Términos de Uso',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextSpan(text: ' de BusPoints.'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_acceptedTerms)
                    const Padding(
                      padding: EdgeInsets.only(left: 8.0, bottom: 8.0),
                      child: Text(
                        'Debes aceptar los Términos de Uso para registrarte.',
                        style: TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 200,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _signUp,
                      child: const Text('Registrarse', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  TextButton(
                    onPressed: widget.onToggleAuthMode,
                    child: const Text('¿Ya tienes una cuenta? Inicia sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
