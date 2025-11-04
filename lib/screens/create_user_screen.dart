import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  String? _selectedRole = 'user';
  bool _isLoading = false;

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
      // Create user in Firebase Auth
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );

      await userCredential.user?.updateDisplayName(_nameController.text);

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

      // Create user document in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        'name': _nameController.text,
        'email': _emailController.text,
        'role': _selectedRole,
        'status': 'approved',
        'approvedPoisCount': 0,
        'subscriptionHistory': subscriptionHistory,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Usuario creado correctamente.'),
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
    } catch (_) {
      _showErrorSnackBar('Ocurrió un error inesperado. Por favor, inténtalo de nuevo más tarde.');
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
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (value) =>
                      (value == null || value.isEmpty) ? 'Por favor, introduce un nombre.' : null,
                ),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Correo Electrónico'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) => (value == null || !value.contains('@'))
                      ? 'Por favor, introduce un correo electrónico válido.'
                      : null,
                ),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Contraseña'),
                  obscureText: true,
                  validator: (value) => (value == null || value.length < 6)
                      ? 'La contraseña debe tener al menos 6 caracteres.'
                      : null,
                ),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(labelText: 'Confirmar Contraseña'),
                  obscureText: true,
                  validator: (value) =>
                      (value != _passwordController.text) ? 'Las contraseñas no coinciden.' : null,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: const InputDecoration(
                      labelText: 'Rol',
                      border: OutlineInputBorder()),
                  items: ['user', 'admin'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value == 'user'
                          ? 'Usuario'
                          : 'Administrador'),
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
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _createUser,
                        icon: const Icon(Icons.person_add),
                        label: const Text('Crear Usuario'),
                        style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50)),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
