
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

void showContactDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return const ContactFormDialog();
    },
  );
}

class ContactFormDialog extends StatefulWidget {
  const ContactFormDialog({super.key});

  @override
  State<ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends State<ContactFormDialog> {
  User? _currentUser;
  bool _userDataLoaded = false;
  @override
  void initState() {
    super.initState();
    _currentUser = FirebaseAuth.instance.currentUser;
    if (_currentUser != null) {
      FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).get().then((doc) {
        final data = doc.data();
        _nameController.text = data?['name'] ?? _currentUser!.displayName ?? '';
        _emailController.text = data?['email'] ?? _currentUser!.email ?? '';
        _phoneController.text = data?['phone'] ?? '';
        setState(() {
          _userDataLoaded = true;
        });
      });
    } else {
      _userDataLoaded = true;
    }
  }
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSending = true);

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final email = _emailController.text.trim();
      final message = _messageController.text.trim();
      final currentUser = FirebaseAuth.instance.currentUser;

      // Guardar el mensaje en contact_messages (para el admin)
      await FirebaseFirestore.instance.collection('contact_messages').add({
        'name': name,
        'phone': phone.isEmpty ? null : phone,
        'email': email.isEmpty ? null : email,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });

      // Si el usuario está registrado, guardar copia en user_messages (bandeja enviados)
      if (currentUser != null) {
        // Obtener el UID del admin
        final adminQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'admin')
            .limit(1)
            .get();

        if (adminQuery.docs.isNotEmpty) {
          final adminUid = adminQuery.docs.first.id;
          
          await FirebaseFirestore.instance.collection('user_messages').add({
            'fromUid': currentUser.uid,
            'toUid': adminUid,
            'fromName': name,
            'toName': 'Administrador',
            'fromEmail': email.isEmpty ? currentUser.email ?? '' : email,
            'toEmail': 'admin@buspoints.com',
            'message': message,
            'timestamp': FieldValue.serverTimestamp(),
            'read': true,
            'fromAdmin': false,
            'isContact': true,
          });
        }
      }

      if (mounted) {
        // Cerrar el diálogo
        Navigator.of(context).pop();
        
        // Mostrar mensaje de confirmación
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Builder(builder: (context) {
                // Make icon size responsive to avoid overflow on very small screens
                final screenWidth = MediaQuery.of(context).size.width;
                final iconSize = (screenWidth * 0.06).clamp(20.0, 40.0);
                return Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: iconSize),
                    const SizedBox(width: 12),
                    const Flexible(
                      child: Text(
                        '¡Mensaje Enviado!',
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    ),
                  ],
                );
              }),
              content: const Text(
                'Gracias por contactarnos. Hemos recibido tu mensaje y te responderemos lo antes posible.',
                style: TextStyle(fontSize: 16),
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Cierra el diálogo de confirmación
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: const Text('Aceptar'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        // Mostrar mensaje de error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar el mensaje: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_userDataLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return AlertDialog(
      title: const Text('Contacto'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  hintText: 'Tu nombre',
                  prefixIcon: Icon(Icons.person),
                ),
                enabled: _currentUser == null,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre es obligatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Teléfono *',
                  hintText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone),
                ),
                enabled: _currentUser == null,
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El teléfono es obligatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email *',
                  hintText: 'Tu email',
                  prefixIcon: Icon(Icons.email),
                ),
                enabled: _currentUser == null,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) {
                    return 'El email es obligatorio';
                  }
                  // Mínimo 3 caracteres, @, 3 caracteres, .
                  if (!RegExp(r'^[^@\s]{3,}@[A-Za-z0-9]{3,}\.[A-Za-z]{2,}$').hasMatch(email)) {
                    return 'Formato de email inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Mensaje *',
                  hintText: 'Escribe tu mensaje aquí',
                  prefixIcon: Icon(Icons.message),
                ),
                maxLines: 4,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El mensaje es obligatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              const Text(
                '* Todos los campos son obligatorios',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _sendMessage,
          child: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar'),
        ),
      ],
    );
  }
}
