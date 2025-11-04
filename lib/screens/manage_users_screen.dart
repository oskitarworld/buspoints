import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/models/user_model.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'create_user_screen.dart';

class ManageUsersScreen extends StatelessWidget {
  const ManageUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar Usuarios'),
        actions: [
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';

  void _showSearchDialog() async {
    final searchController = TextEditingController(text: _searchQuery);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buscar Usuario'),
        content: TextField(
          controller: searchController,
          decoration: const InputDecoration(
            hintText: 'Nombre o email...',
            icon: Icon(Icons.search),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            child: const Text('Buscar'),
            onPressed: () {
              if (mounted) {
                setState(() => _searchQuery = searchController.text);
              }
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _searchQuery.isEmpty
                      ? 'Mostrando todos los usuarios'
                      : 'Resultados para: "$_searchQuery"'
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _showSearchDialog,
                tooltip: 'Buscar'
              ),
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _searchQuery = ''),
                  tooltip: 'Limpiar Búsqueda'
                ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final users = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['name'] ?? '').toLowerCase();
                final email = (data['email'] ?? '').toLowerCase();
                return name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
              }).toList();

              if (users.isEmpty) return const Center(child: Text('No se encontraron usuarios.'));

              return ListView.builder(
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
  final QueryDocumentSnapshot userDoc;
  const UserListItem({super.key, required this.userDoc});

  String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  void _showSnackBar(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green),
    );
  }

  Future<void> _updateSubscription(BuildContext context, String uid, List<Subscription> history, Subscription oldSub, DateTime newEndDate) async {
    final updatedSub = Subscription(startDate: oldSub.startDate, endDate: newEndDate);
    final index = history.indexWhere((s) => s.startDate == oldSub.startDate && s.endDate == oldSub.endDate);
    if (index != -1) {
      final updatedHistory = List<Subscription>.from(history)..[index] = updatedSub;
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'subscriptionHistory': updatedHistory.map((s) => s.toMap()).toList(),
        });
        if (!context.mounted) return;
        _showSnackBar(context, 'Suscripción actualizada.');
      } catch (e) {
        if (!context.mounted) return;
        _showSnackBar(context, 'Error al actualizar: $e', isError: true);
      }
    }
  }

  Future<void> _renewSubscription(BuildContext context, String uid, List<Subscription> history) async {
    final newSub = Subscription(startDate: DateTime.now(), endDate: DateTime.now().add(const Duration(days: 365)));
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'subscriptionHistory': [...history.map((s) => s.toMap()), newSub.toMap()],
      });
      if (!context.mounted) return;
      _showSnackBar(context, 'Suscripción renovada.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Error al renovar: $e', isError: true);
    }
  }

  Future<void> _deleteUser(BuildContext context, String uid) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      if (!context.mounted) return;
      _showSnackBar(context, 'Usuario eliminado.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Error al eliminar: $e', isError: true);
    }
  }

  Future<void> _updateUserRole(BuildContext context, String uid, String newRole, UserModel user) async {
      Map<String, dynamic> dataToUpdate = {'role': newRole};
      if (newRole == 'user' && user.role == 'admin') {
        final newSub = Subscription(startDate: DateTime.now(), endDate: DateTime.now().add(const Duration(days: 365)));
        dataToUpdate['subscriptionHistory'] = [newSub.toMap()];
      } else if (newRole == 'admin') {
        dataToUpdate['subscriptionHistory'] = [];
      }
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update(dataToUpdate);
      if (!context.mounted) return;
      _showSnackBar(context, 'Rol actualizado.');
    } catch (e) {
      if (!context.mounted) return;
      _showSnackBar(context, 'Error al actualizar rol: $e', isError: true);
    }
  }

  void _confirmDelete(BuildContext context, String uid, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Seguro que quieres eliminar a $name?'),
        actions: [
          TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(ctx).pop()),
          SlideAction(text: 'Deslizar para Eliminar', onSubmit: () { Navigator.of(ctx).pop(); _deleteUser(context, uid); return null; })
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = UserModel.fromFirestore(userDoc);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${user.email} - Rol: ${user.role.toUpperCase()}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Historial de Suscripciones', style: TextStyle(fontWeight: FontWeight.bold)),
                ...user.subscriptionHistory.map((sub) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('  • ${_formatDate(sub.startDate)} - ${_formatDate(sub.endDate)}'),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          onPressed: () async {
                            final newDate = await showDatePicker(context: context, initialDate: sub.endDate, firstDate: sub.startDate, lastDate: DateTime(2100));
                            if (newDate != null) {
                              if (!context.mounted) return;
                              _updateSubscription(context, user.uid, user.subscriptionHistory, sub, newDate);
                            }
                          },
                        ),
                      ],
                    )),
                if (user.subscriptionHistory.isEmpty) const Text('  Sin suscripciones.'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: [
                    if (user.role != 'admin' && !user.isSubscriptionActive)
                      ElevatedButton.icon(
                        onPressed: () => _renewSubscription(context, user.uid, user.subscriptionHistory),
                        icon: const Icon(Icons.autorenew, size: 18),
                        label: const Text('Renovar'),
                      ),
                    ElevatedButton.icon(
                      onPressed: () => _confirmDelete(context, user.uid, user.name),
                      icon: const Icon(Icons.delete, size: 18),
                      label: const Text('Eliminar'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _updateUserRole(context, user.uid, user.role == 'admin' ? 'user' : 'admin', user),
                      icon: const Icon(Icons.admin_panel_settings, size: 18),
                      label: Text(user.role == 'admin' ? 'Quitar Admin' : 'Hacer Admin'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
