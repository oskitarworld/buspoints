import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/services/firestore_web_compat.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'create_user_screen.dart';

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar Usuarios'),
        backgroundColor: Colors.red[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign),
            tooltip: 'Enviar push a todos',
            onPressed: () {
              final messageController = TextEditingController();
              final formKey = GlobalKey<FormState>();
              bool isSending = false;
              showDialog(
                context: context,
                builder: (ctx) {
                  return StatefulBuilder(
                    builder: (context, setState) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: Row(
                          children: [
                            const Icon(Icons.campaign, color: Colors.blue),
                            const SizedBox(width: 12),
                            const Expanded(child: Text('Enviar notificación a todos')),
                          ],
                        ),
                        content: Form(
                          key: formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                controller: messageController,
                                decoration: InputDecoration(
                                  labelText: 'Mensaje',
                                  hintText: 'Escribe tu mensaje aquí...',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(Icons.edit),
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                ),
                                maxLines: 5,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'El mensaje no puede estar vacío';
                                  }
                                  if (value.trim().length < 5) {
                                    return 'El mensaje debe tener al menos 5 caracteres';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: isSending ? null : () => Navigator.of(ctx).pop(),
                            child: const Text('Cancelar'),
                          ),
                          ElevatedButton.icon(
                            icon: isSending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.send),
                            label: Text(isSending ? 'Enviando...' : 'Enviar a todos'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(ctx).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: isSending
                                ? null
                                : () async {
                                    if (formKey.currentState?.validate() ?? false) {
                                      setState(() => isSending = true);
                                      try {
                                        final currentUser = FirebaseAuth.instance.currentUser;
                                        if (currentUser == null) throw Exception('No hay usuario autenticado');
                                        final adminDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
                                        final adminData = adminDoc.data();
                                        final adminName = adminData?['name'] ?? currentUser.displayName ?? 'Administrador';

                                        // Create a system notification (non-respondable) for broadcast
                                        final firestore = FirebaseFirestore.instance;
                                        final notifRef = await firestore.collection('system_notifications').add({
                                          'fromUid': currentUser.uid,
                                          'fromName': adminName,
                                          'message': messageController.text.trim(),
                                          'timestamp': FieldValue.serverTimestamp(),
                                          'fromAdmin': true,
                                          'to': 'all',
                                          'respondable': false,
                                        });

                                        // Create per-user copies for efficient reads and per-user unread counts
                                        // Use batched writes in chunks of 500
                                        final usersSnap = await firestore.collection('users').get();
                                        const int batchSize = 500;
                                        final docs = usersSnap.docs;
                                        for (var i = 0; i < docs.length; i += batchSize) {
                                          final chunk = docs.sublist(i, (i + batchSize) > docs.length ? docs.length : i + batchSize);
                                          final batch = firestore.batch();
                                          for (var u in chunk) {
                                            final uid = u.id;
                                            final userNotifRef = firestore.collection('users').doc(uid).collection('notifications').doc(notifRef.id);
                                            batch.set(userNotifRef, {
                                              'fromUid': currentUser.uid,
                                              'fromName': adminName,
                                              'message': messageController.text.trim(),
                                              'timestamp': FieldValue.serverTimestamp(),
                                              'read': false,
                                              'systemNotifId': notifRef.id,
                                            });
                                          }
                                          await batch.commit();
                                        }

                                        if (ctx.mounted) Navigator.of(ctx).pop();
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Mensaje broadcast enviado a todos'), backgroundColor: Colors.green[700]),
                                          );
                                        }
                                      } catch (e) {
                                        setState(() => isSending = false);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error al enviar broadcast: $e'), backgroundColor: Colors.red));
                                        }
                                      }
                                    }
                                  },
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateUserScreen()),
            ),
            tooltip: 'Crear Nuevo Usuario',
          ),
        ],
      ),
      body: const UserList(),
    );
  }
}

class UserList extends StatefulWidget {
  const UserList({super.key});

  @override
  State<UserList> createState() => _UserListState();
}

class _UserListState extends State<UserList> {
  String _searchQuery = '';
  String _filterRole = 'todos';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Barra de búsqueda y filtros
        Container(
          padding: const EdgeInsets.all(16.0),
          color: Colors.grey[100],
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o email...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Filtrar por rol: ',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'todos', label: Text('Todos')),
                        ButtonSegment(value: 'user', label: Text('Usuario')),
                        ButtonSegment(value: 'admin', label: Text('Admin')),
                      ],
                      selected: {_filterRole},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() {
                          _filterRole = newSelection.first;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Lista de usuarios
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: resilientStream(FirebaseFirestore.instance.collection('users').snapshots(), name: 'manage_users_list'),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Error al cargar usuarios.'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              var users = snapshot.data!.docs;

              // Aplicar filtros
              if (_searchQuery.isNotEmpty) {
                users = users.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery) ||
                      email.contains(_searchQuery);
                }).toList();
              }

              if (_filterRole != 'todos') {
                users = users.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return (data['role'] ?? 'user') == _filterRole;
                }).toList();
              }

              if (users.isEmpty) {
                return const Center(
                    child:
                        Text('No hay usuarios que coincidan con los filtros.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final userDoc = users[index];
                  return UserListItem(userDoc: userDoc);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class UserListItem extends StatelessWidget {
  final dynamic userDoc;
  const UserListItem({super.key, required this.userDoc});

  @override
  Widget build(BuildContext context) {
    final data = userDoc.data() as Map<String, dynamic>;
    final String name = data['name'] ?? 'Usuario';
    final String email = data['email'] ?? '';
    final String role = data['role'] ?? 'user';
    final bool subscriptionActive = data['subscriptionActive'] ?? false;
    final bool frozen = data['frozen'] ?? false;
    final String? photoUrl = data['photoURL'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showManageUserDialog(context, data, userDoc.id),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Avatar del usuario
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.red[100],
                backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                    ? NetworkImage(photoUrl)
                    : null,
                child: photoUrl == null || photoUrl.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[800],
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              // Información del usuario
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (role == 'admin')
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'ADMIN',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Badges de estado
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (subscriptionActive)
                          _buildBadge('Suscripción activa', Colors.green),
                        if (!subscriptionActive)
                          _buildBadge('Sin suscripción', Colors.orange),
                        if (frozen) _buildBadge('Cuenta congelada', Colors.red),
                      ],
                    ),
                  ],
                ),
              ),
              // Acciones rápidas: ver detalles (envío de mensajes individuales deshabilitado)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Envío de notificaciones a usuarios individuales eliminado por política.
                  Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha((0.1 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha((0.3 * 255).round())),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: Colors.red[800],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _showManageUserDialog(
      BuildContext context, Map<String, dynamic> data, String userId) {
    final String name = data['name'] ?? 'Usuario';
    final String email = data['email'] ?? '';
    final String phone = data['phone'] ?? 'No disponible';
    final String role = data['role'] ?? 'user';
    final bool subscriptionActive = data['subscriptionActive'] ?? false;
    final bool frozen = data['frozen'] ?? false;
    final String? photoUrl = data['photoURL'];

    // Formatear la fecha de inicio de suscripción
    String subscriptionStart = 'No disponible';
    if (data['subscriptionStart'] != null) {
      try {
        DateTime? startDate;

        // Intentar diferentes formatos de fecha
        if (data['subscriptionStart'] is Timestamp) {
          startDate = (data['subscriptionStart'] as Timestamp).toDate();
        } else if (data['subscriptionStart'] is String) {
          startDate = DateTime.tryParse(data['subscriptionStart']);
        }

        if (startDate != null) {
          subscriptionStart =
              '${startDate.day}/${startDate.month}/${startDate.year}';
        }
      } catch (e) {
        subscriptionStart = 'Formato no válido';
      }
    }

    // Formatear la fecha de fin de suscripción
    String subscriptionEnd = 'No disponible';
    if (data['subscriptionEnd'] != null) {
      try {
        DateTime? endDate;

        // Intentar diferentes formatos de fecha
        if (data['subscriptionEnd'] is Timestamp) {
          endDate = (data['subscriptionEnd'] as Timestamp).toDate();
        } else if (data['subscriptionEnd'] is String) {
          endDate = DateTime.tryParse(data['subscriptionEnd']);
        }

        if (endDate != null) {
          subscriptionEnd = '${endDate.day}/${endDate.month}/${endDate.year}';
        }
      } catch (e) {
        subscriptionEnd = 'Formato no válido';
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 500,
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header con avatar y nombre
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.red[100],
                        backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                            ? NetworkImage(photoUrl)
                            : null,
                        child: photoUrl == null || photoUrl.isEmpty
                            ? Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[800],
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Información del usuario
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(Icons.phone, 'Teléfono', phone),
                        const Divider(height: 24),
                        _buildInfoRow(
                          Icons.admin_panel_settings,
                          'Rol',
                          role == 'admin' ? 'Administrador' : 'Usuario',
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          Icons.card_membership,
                          'Suscripción',
                          subscriptionActive ? 'Activa' : 'Inactiva',
                          valueColor:
                              subscriptionActive ? Colors.green : Colors.orange,
                        ),
                        if (subscriptionActive &&
                            subscriptionStart != 'No disponible') ...[
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.play_circle_outline,
                            'Fecha inicio',
                            subscriptionStart,
                            valueColor: Colors.blue,
                          ),
                        ],
                        const Divider(height: 24),
                        _buildInfoRow(
                          Icons.event,
                          subscriptionActive ? 'Vencimiento' : 'Última fecha',
                          subscriptionEnd,
                          valueColor: subscriptionActive ? null : Colors.grey,
                        ),
                        if (frozen) ...[
                          const Divider(height: 24),
                          _buildInfoRow(
                            Icons.lock,
                            'Estado',
                            'Cuenta congelada',
                            valueColor: Colors.red,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Botones de acción
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar Datos Personales'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Theme.of(ctx).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showEditUserDialog(context, data, userId);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Enviar mensaje directo al usuario (desde admin)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text('Enviar Mensaje'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Theme.of(ctx).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showSendMessageDialog(context, data, userId);
                        },
                      ),
                      const SizedBox(height: 12),

                      ElevatedButton.icon(
                        icon: const Icon(Icons.card_membership),
                        label: const Text('Administrar Suscripción'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: Theme.of(ctx).primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showManageSubscriptionDialog(context, data, userId);
                        },
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: Icon(frozen ? Icons.lock_open : Icons.lock),
                        label: Text(frozen ? 'Descongelar Cuenta' : 'Congelar Cuenta'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: frozen ? Colors.orange[700] : Colors.red[700],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _toggleFreezeAccount(context, userId, frozen);
                        },
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Eliminar Usuario'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _showDeleteUserDialog(context, userId, name);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cerrar'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? Colors.black87,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  void _showEditUserDialog(
      BuildContext context, Map<String, dynamic> data, String userId) {
    final nameController = TextEditingController(text: data['name'] ?? '');
    final emailController = TextEditingController(text: data['email'] ?? '');
    final phoneController = TextEditingController(text: data['phone'] ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Editar Datos Personales'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'El nombre no puede estar vacío';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'El email no puede estar vacío';
                      }
                      if (!RegExp(r'^.+@.+\..+$').hasMatch(value)) {
                        return 'Email no válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      prefixIcon: Icon(Icons.phone),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'El teléfono no puede estar vacío';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              child: const Text('Guardar'),
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .update({
                      'name': nameController.text.trim(),
                      'email': emailController.text.trim(),
                      'phone': phoneController.text.trim(),
                    });
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Datos actualizados correctamente.')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al actualizar: $e')),
                      );
                    }
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showSendMessageDialog(BuildContext context, Map<String, dynamic> data, String userId) {
    final messageController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        bool isSending = false;
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Enviar mensaje al usuario'),
            content: TextField(
              controller: messageController,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Escribe tu mensaje...'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: isSending
                    ? null
                    : () async {
                        final msg = messageController.text.trim();
                        if (msg.isEmpty) return;
                        setState(() => isSending = true);
                        try {
                          final current = FirebaseAuth.instance.currentUser;
                          final fromUid = current?.uid ?? 'system';
                          final fromName = current?.displayName ?? 'Administrador';
                          await FirebaseFirestore.instance.collection('user_messages').add({
                            'fromUid': fromUid,
                            'toUid': userId,
                            'fromName': fromName,
                            'toName': data['name'] ?? '',
                            'fromEmail': current?.email ?? '',
                            'toEmail': data['email'] ?? '',
                            'message': msg,
                            'timestamp': FieldValue.serverTimestamp(),
                            'read': false,
                            'fromAdmin': true,
                          });
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mensaje enviado'), backgroundColor: Colors.green));
                        } catch (e) {
                          setState(() => isSending = false);
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error enviando mensaje: $e'), backgroundColor: Colors.red));
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(ctx).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))) : const Text('Enviar'),
              ),
            ],
          );
        });
      },
    );
  }

  void _showManageSubscriptionDialog(
      BuildContext context, Map<String, dynamic> data, String userId) {
    final bool currentStatus = data['subscriptionActive'] ?? false;
    DateTime? selectedDate;

    // Obtener fecha de inicio si existe
    String? startDateText;
    if (data['subscriptionStart'] != null) {
      try {
        DateTime? startDate;
        if (data['subscriptionStart'] is Timestamp) {
          startDate = (data['subscriptionStart'] as Timestamp).toDate();
        } else if (data['subscriptionStart'] is String) {
          startDate = DateTime.tryParse(data['subscriptionStart']);
        }
        if (startDate != null) {
          startDateText =
              '${startDate.day}/${startDate.month}/${startDate.year}';
        }
      } catch (e) {
        startDateText = null;
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Administrar Suscripción'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado actual: ${currentStatus ? "Activa" : "Inactiva"}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: currentStatus ? Colors.green : Colors.orange,
                    ),
                  ),
                  if (startDateText != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
            Icon(Icons.play_circle_outline,
              size: 18, color: Theme.of(ctx).primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Inicio: $startDateText',
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(ctx).primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text('Selecciona una nueva fecha de vencimiento:'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      selectedDate != null
                          ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                          : 'Seleccionar fecha',
                    ),
                    onPressed: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Acciones rápidas:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildQuickActionChip('1 mes', 30, (date) {
                        setState(() => selectedDate = date);
                      }),
                      _buildQuickActionChip('3 meses', 90, (date) {
                        setState(() => selectedDate = date);
                      }),
                      _buildQuickActionChip('6 meses', 180, (date) {
                        setState(() => selectedDate = date);
                      }),
                      _buildQuickActionChip('1 año', 365, (date) {
                        setState(() => selectedDate = date);
                      }),
                    ],
                  ),
                ],
              ),
              actions: [
                if (currentStatus)
                  TextButton.icon(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text('Desactivar',
                        style: TextStyle(color: Colors.red)),
                    onPressed: () async {
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(userId)
                            .update({
                          'subscriptionActive': false,
                        });
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Suscripción desactivada')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
                  ),
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
                ElevatedButton(
                  onPressed: selectedDate == null
                      ? null
                      : () async {
                          try {
                            // Si no hay fecha de inicio previa, establecer la actual
                            Map<String, dynamic> updateData = {
                              'subscriptionActive': true,
                              'subscriptionEnd':
                                  selectedDate!.toIso8601String(),
                            };

                            // Solo establecer fecha de inicio si no existe
                            if (data['subscriptionStart'] == null) {
                              updateData['subscriptionStart'] =
                                  DateTime.now().toIso8601String();
                            }

                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(userId)
                                .update(updateData);
                            if (ctx.mounted) {
                              Navigator.of(ctx).pop();
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Suscripción actualizada correctamente')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error al actualizar: $e')),
                              );
                            }
                          }
                        },
                  child: const Text('Activar/Actualizar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildQuickActionChip(
      String label, int days, Function(DateTime) onSelected) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        final newDate = DateTime.now().add(Duration(days: days));
        onSelected(newDate);
      },
    );
  }

  void _toggleFreezeAccount(
      BuildContext context, String userId, bool currentlyFrozen) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title:
              Text(currentlyFrozen ? 'Descongelar Cuenta' : 'Congelar Cuenta'),
          content: Text(
            currentlyFrozen
                ? '¿Estás seguro de que quieres descongelar esta cuenta? El usuario podrá volver a acceder.'
                : '¿Estás seguro de que quieres congelar esta cuenta? El usuario no podrá acceder hasta que sea descongelada.',
          ),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: currentlyFrozen ? Colors.orange : Colors.red,
              ),
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .update({
                    'frozen': !currentlyFrozen,
                  });
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          currentlyFrozen
                              ? 'Cuenta descongelada correctamente'
                              : 'Cuenta congelada correctamente',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: Text(currentlyFrozen ? 'Descongelar' : 'Congelar'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteUserDialog(
      BuildContext context, String userId, String userName) {
    final confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Eliminar Usuario'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '¡ADVERTENCIA! Esta acción no se puede deshacer.',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text('Estás a punto de eliminar al usuario: $userName'),
              const SizedBox(height: 16),
              const Text('Escribe "ELIMINAR" para confirmar:'),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'ELIMINAR',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () async {
                if (confirmController.text.trim() == 'ELIMINAR') {
                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .delete();
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Usuario eliminado correctamente')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al eliminar: $e')),
                      );
                    }
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Debes escribir "ELIMINAR" para confirmar')),
                  );
                }
              },
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );
  }

  // _showSendMessageDialog removed: sending individual messages from admin panel is disabled by policy.

  
}
