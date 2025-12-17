import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:myapp/models/user_model.dart'; // Import the updated model

class ProfileScreen extends StatelessWidget {
  // --- MÉTODOS DE VALORACIONES (antes de build) ---
  Widget _buildUserReviewsTab(BuildContext context, String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('reviews')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No tienes valoraciones aprobadas.'));
        }
        final reviews = snapshot.data!.docs;
        return ListView.builder(
          itemCount: reviews.length,
          itemBuilder: (context, index) {
            final review = reviews[index];
            final data = review.data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: Icon(Icons.star, color: Colors.amber[700]),
                title: Text(data['comment'] ?? ''),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(data['rating']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (data['createdAt'] != null)
                      Text('Fecha: ${data['createdAt'] is Timestamp
                          ? (data['createdAt'] as Timestamp).toDate().toString().substring(0, 16)
                          : data['createdAt'].toString()}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      tooltip: 'Editar',
                      onPressed: () => _showEditReviewDialog(context, review),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      tooltip: 'Borrar',
                      onPressed: () => _deleteReview(context, review),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditReviewDialog(BuildContext context, QueryDocumentSnapshot review) {
    final data = review.data() as Map<String, dynamic>;
    final controller = TextEditingController(text: data['comment'] ?? '');
    final ratingController = TextEditingController(text: data['rating']?.toString() ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar valoración'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Comentario'),
            ),
            TextFormField(
              controller: ratingController,
              decoration: const InputDecoration(labelText: 'Puntuación (1-5)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newComment = controller.text.trim();
              final newRating = int.tryParse(ratingController.text.trim()) ?? data['rating'];
              await review.reference.update({'comment': newComment, 'rating': newRating});
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Valoración actualizada')),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _deleteReview(BuildContext context, QueryDocumentSnapshot review) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar valoración'),
        content: const Text('¿Seguro que quieres eliminar esta valoración?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await review.reference.delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Valoración eliminada')),
      );
    }
  }
  const ProfileScreen({super.key});

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  void _showEditDialog(BuildContext context, String field, String value, String uid) {
    final controller = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar ${field == 'email' ? 'Correo Electrónico' : 'Teléfono'}'),
        content: TextFormField(
          controller: controller,
          keyboardType: field == 'email' ? TextInputType.emailAddress : TextInputType.phone,
          decoration: InputDecoration(
            labelText: field == 'email' ? 'Correo Electrónico' : 'Teléfono',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newValue = controller.text.trim();
              final usersRef = FirebaseFirestore.instance.collection('users');
              if (field == 'email') {
                final emailDup = await usersRef.where('email', isEqualTo: newValue).get();
                if (emailDup.docs.any((doc) => doc.id != uid)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ya existe una cuenta con ese correo electrónico'), backgroundColor: Colors.red),
                  );
                  return;
                }
              } else {
                final phoneDup = await usersRef.where('phone', isEqualTo: newValue).get();
                if (phoneDup.docs.any((doc) => doc.id != uid)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ya existe una cuenta con ese teléfono'), backgroundColor: Colors.red),
                  );
                  return;
                }
              }
              await usersRef.doc(uid).update({field: newValue});
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Datos actualizados')),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Perfil')),
        body: const Center(child: Text('No has iniciado sesión.')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mi Perfil'),
          elevation: 0,
          bottom: const TabBar(
            labelColor: Colors.blue,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.blue,
            tabs: [
              Tab(icon: Icon(Icons.person), text: 'Perfil'),
              Tab(icon: Icon(Icons.place), text: 'Mis lugares'),
              Tab(icon: Icon(Icons.star), text: 'Valoraciones'),
              Tab(icon: Icon(Icons.emoji_events), text: 'Recompensas'),
            ],
          ),
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                  child: Text('No se pudo cargar el perfil.'));
            }

            final user = UserModel.fromFirestore(snapshot.data!);

            return TabBarView(
              children: [
                // PERFIL
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: <Widget>[
                      _buildProfileHeader(context, user),
                      const SizedBox(height: 32),
                      _buildMembershipCard(context, user),
                      const SizedBox(height: 24),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.email, color: Colors.blueGrey),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(user.email, style: const TextStyle(fontSize: 16)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Editar correo',
                                    onPressed: () => _showEditDialog(context, 'email', user.email, user.uid),
                                  ),
                                ],
                              ),
                              const Divider(),
                              Row(
                                children: [
                                  const Icon(Icons.phone, color: Colors.blueGrey),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(user.phone, style: const TextStyle(fontSize: 16)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Editar teléfono',
                                    onPressed: () => _showEditDialog(context, 'phone', user.phone, user.uid),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildStatsCard(context, user.uid),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar Sesión'),
                      ),
                    ],
                  ),
                ),
                // MIS LUGARES
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildMyPlacesCard(context, user.uid),
                ),
                // VALORACIONES
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildUserReviewsTab(context, user.uid),
                ),
                // RECOMPENSAS
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildRewardsCard(context, user.approvedPoisCount),
                ),
              ],
            );
          },
        ),
      ),
    );
  // ...existing code...
  }

  Widget _buildProfileHeader(BuildContext context, UserModel user) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            user.name.isNotEmpty
                ? user.name.substring(0, 1).toUpperCase()
                : 'U',
            style: TextStyle(
                fontSize: 40,
                color: Theme.of(context).colorScheme.onPrimaryContainer),
          ),
        ),
        const SizedBox(height: 16),
        Text(user.name,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(user.email,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildMembershipCard(BuildContext context, UserModel user) {
    final bool isActive = user.isSubscriptionActive;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Membresía',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(isActive ? Icons.check_circle : Icons.cancel,
                    color: isActive ? Colors.green : Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(isActive ? 'Activa' : 'Vencida',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isActive ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            const Text('Historial de Suscripción:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (user.subscriptionHistory.isEmpty)
              const Text('  • No hay registros de suscripción.')
            else
              ...user.subscriptionHistory.reversed.map((sub) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: Text(
                        '  • ${_formatDate(sub.startDate)} a ${_formatDate(sub.endDate)}'),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, String uid) {
    return FutureBuilder(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').doc(uid).collection('saved_places').get(),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('favorite_places').get(),
        // Solo reviews aprobadas:
        FirebaseFirestore.instance.collectionGroup('reviews')
          .where('userId', isEqualTo: uid)
          .where('status', isEqualTo: 'approved')
          .get(),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('history_places').get(),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('added_pois').get(),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('reports').get(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final data = snapshot.data as List;
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estadísticas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.2,
                  children: [
                    _buildStatItem(context, Icons.bookmark, data[0].size.toString(), 'Guardados'),
                    _buildStatItem(context, Icons.favorite, data[1].size.toString(), 'Favoritos'),
                    _buildStatItem(context, Icons.star, data[2].size.toString(), 'Valoraciones'),
                    _buildStatItem(context, Icons.history, data[3].size.toString(), 'Visitados'),
                    _buildStatItem(context, Icons.add_location, data[4].size.toString(), 'Añadidos'),
                    _buildStatItem(context, Icons.report, data[5].size.toString(), 'Reportes'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatItem(BuildContext context, IconData icon, String count, String label) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(height: 4),
        Text(count, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildMyPlacesCard(BuildContext context, String uid) {
    return DefaultTabController(
      length: 3,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            const TabBar(
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
              tabs: [
                Tab(icon: Icon(Icons.bookmark), text: 'Guardados'),
                Tab(icon: Icon(Icons.favorite), text: 'Favoritos'),
                Tab(icon: Icon(Icons.history), text: 'Historial'),
              ],
            ),
            SizedBox(
              height: 200,
              child: TabBarView(
                children: [
                  _buildPlaceList(context, uid, 'saved_places'),
                  _buildPlaceList(context, uid, 'favorite_places'),
                  _buildPlaceList(context, uid, 'history_places'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceList(BuildContext context, String uid, String collection) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        // Si no hay datos o está vacío, mostrar "Vacío" (incluso si hay error)
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Vacío'));
        }
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final place = snapshot.data!.docs[index];
            return ListTile(
              leading: const Icon(Icons.location_on, color: Colors.blue),
              title: Text(place['name'] ?? ''),
              subtitle: Text(place['category'] ?? '', style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            );
          },
        );
      },
    );
  }

  Widget _buildRewardsCard(BuildContext context, int prizeCount) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black.withAlpha(26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Text(
              'Recompensas',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                FaIcon(FontAwesomeIcons.trophy,
                    size: 40, color: Colors.amber.shade700),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$prizeCount',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade800),
                    ),
                    Text(
                      'Premios Ganados',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.grey[600]),
                    ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '¡Ganas 2 días de membresía por cada PDI aprobado!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[500]),
            )
          ],
        ),
      ),
    );
  }
}
