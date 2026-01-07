import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:myapp/models/user_model.dart';

class CreateUserScreen extends StatefulWidget {
  const CreateUserScreen({super.key});

  @override
  State<CreateUserScreen> createState() => _CreateUserScreenState();
}

class _CreateUserScreenState extends State<CreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Prefill the phone field with the Spanish country code but keep it editable.
    if (_phoneController.text.isEmpty) {
      _phoneController.text = '+34';
    }
  }
  String? _selectedRole = 'user';
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim();
      String phone = _phoneController.text.trim();
      // Basic normalization to E.164-ish: remove non-digit except leading +,
      // and if the number doesn't start with +, assume Spanish country code +34.
      String normalized = phone.replaceAll(RegExp(r'[^0-9+]'), '');
      if (normalized.isEmpty) {
        _showErrorSnackBar('Por favor, introduce un teléfono.');
        setState(() => _isLoading = false);
        return;
      }
      if (!normalized.startsWith('+')) {
  // Strip leading zeros to avoid +34061234567 mistakes
  normalized = normalized.replaceFirst(RegExp(r'^0+'), '');
  normalized = '+34$normalized';
      }
      phone = normalized;
      final usersRef = FirebaseFirestore.instance.collection('users');
      // Validar duplicados de nombre (timeout corto para evitar bloqueos largos)
      final nameDup = await usersRef.where('name', isEqualTo: name).get().timeout(const Duration(seconds: 5));
      if (nameDup.docs.isNotEmpty) {
        _showErrorSnackBar('Ya existe un usuario con ese nombre.');
        setState(() => _isLoading = false);
        return;
      }
      // Validar duplicados de email (timeout corto para evitar bloqueos largos)
      final emailDup = await usersRef.where('email', isEqualTo: email).get().timeout(const Duration(seconds: 5));
      if (emailDup.docs.isNotEmpty) {
        _showErrorSnackBar('Ya existe una cuenta con ese correo electrónico.');
        setState(() => _isLoading = false);
        return;
      }
      // Validar duplicados de teléfono (timeout corto para evitar bloqueos largos)
      final phoneDup = await usersRef.where('phone', isEqualTo: phone).get().timeout(const Duration(seconds: 5));
      if (phoneDup.docs.isNotEmpty) {
        _showErrorSnackBar('Ya existe una cuenta con ese teléfono.');
        setState(() => _isLoading = false);
        return;
      }
      // Use a backend callable function to create the user atomically and
      // enforce uniqueness of email and phone.
      HttpsCallableResult? result;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('createUser');
        result = await callable.call(<String, dynamic>{
          'name': name,
          'email': email,
          'phone': phone,
          'password': _passwordController.text,
          'role': _selectedRole ?? 'user',
        }).timeout(const Duration(seconds: 15));
        // result.data should contain { uid: '...' }
      } on FirebaseFunctionsException catch (e) {
        _showErrorSnackBar('Error al crear usuario: ${e.message}');
        setState(() => _isLoading = false);
        return;
      }
      // Prepare subscription history based on role
      List<Map<String, dynamic>> subscriptionHistory = [];
      if (_selectedRole == 'user') {
        final now = DateTime.now();
        final newSubscription = Subscription(
          startDate: now,
          endDate: DateTime(now.year + 1, now.month, now.day),
        );
        subscriptionHistory.add(newSubscription.toMap());
      }

      // The user document is created server-side by the callable. Show success.
      if (!mounted) return;
  final dataMap = result.data as Map<String, dynamic>;
    final String? uid = dataMap['uid'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(uid != null ? 'Usuario creado correctamente (uid: $uid).' : 'Usuario creado correctamente.'),
            backgroundColor: Colors.green),
      );
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'La dirección de correo electrónico ya está en uso por otra cuenta.';
          break;
        case 'weak-password':
          errorMessage = 'La contraseña proporcionada es demasiado débil.';
          break;
        case 'permission-denied':
          errorMessage = 'No tienes permiso para realizar esta acción.';
          break;
        default:
          errorMessage = 'Ocurrió un error inesperado. Por favor, inténtalo de nuevo más tarde.';
      }
      _showErrorSnackBar(errorMessage);
    } on TimeoutException {
      _showErrorSnackBar('La operación tardó demasiado. Por favor, inténtalo de nuevo.');
    } catch (e) {
      _showErrorSnackBar('Ocurrió un error inesperado: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Usuario'),
        backgroundColor: Colors.blue[800],
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue[50]!,
              Colors.blue[100]!,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    // Header Card
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.blue[600]!,
                              Colors.blue[800]!,
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(20),
                        child: const Column(
                          children: [
                            Icon(Icons.person_add, size: 48, color: Colors.white),
                            SizedBox(height: 12),
                            Text(
                              'Nuevo Usuario',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Crea un usuario aprobado directamente',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Form Card
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            // Nombre
                            TextFormField(
                              controller: _nameController,
                              decoration: InputDecoration(
                                labelText: 'Nombre',
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              validator: (value) =>
                                  (value == null || value.isEmpty) ? 'Por favor, introduce un nombre.' : null,
                            ),
                            const SizedBox(height: 16),
                            // Email
                            TextFormField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                labelText: 'Correo Electrónico',
                                prefixIcon: const Icon(Icons.email),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) => (value == null || !value.contains('@'))
                                  ? 'Por favor, introduce un correo electrónico válido.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            // Teléfono
                            TextFormField(
                              controller: _phoneController,
                              decoration: InputDecoration(
                                labelText: 'Teléfono',
                                prefixIcon: const Icon(Icons.phone),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (value) => (value == null || value.isEmpty)
                                  ? 'Por favor, introduce un teléfono.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            // Contraseña
                            TextFormField(
                              controller: _passwordController,
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordVisible = !_isPasswordVisible;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              obscureText: !_isPasswordVisible,
                              validator: (value) => (value == null || value.length < 6)
                                  ? 'La contraseña debe tener al menos 6 caracteres.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            // Confirmar Contraseña
                            TextFormField(
                              controller: _confirmPasswordController,
                              decoration: InputDecoration(
                                labelText: 'Confirmar Contraseña',
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              obscureText: !_isConfirmPasswordVisible,
                              validator: (value) =>
                                  (value != _passwordController.text) ? 'Las contraseñas no coinciden.' : null,
                            ),
                            const SizedBox(height: 16),
                            // Rol
                            DropdownButtonFormField<String>(
                              initialValue: _selectedRole,
                              decoration: InputDecoration(
                                labelText: 'Rol',
                                prefixIcon: const Icon(Icons.admin_panel_settings),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              items: ['user', 'company', 'employee', 'admin'].map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Row(
                                    children: [
                                        Icon(
                                          value == 'user'
                                              ? Icons.person
                                              : value == 'admin'
                                                  ? Icons.admin_panel_settings
                                                  : Icons.business,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          value == 'user'
                                              ? 'Usuario'
                                              : value == 'admin'
                                                  ? 'Administrador'
                                                  : value == 'company'
                                                      ? 'Cuenta Empresa'
                                                      : 'Empleado',
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                setState(() {
                                  _selectedRole = newValue;
                                });
                              },
                              validator: (value) =>
                                  (value == null) ? 'Por favor, selecciona un rol.' : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    // Submit Button
                    _isLoading
                        ? Container(
                            height: 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                colors: [Colors.blue[600]!, Colors.blue[800]!],
                              ),
                            ),
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          )
                        : SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                backgroundColor: Colors.blue[700],
                                elevation: 4,
                              ),
                              onPressed: _createUser,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_add, size: 24),
                                  SizedBox(width: 12),
                                  Text(
                                    'Crear Usuario',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
