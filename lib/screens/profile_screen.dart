import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:myapp/models/user_model.dart'; // Import the updated model

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        elevation: 0,
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

          // Use the new UserModel
          final user = UserModel.fromFirestore(snapshot.data!);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: <Widget>[
                _buildProfileHeader(context, user),
                const SizedBox(height: 32),
                _buildMembershipCard(context, user),
                const SizedBox(height: 24),
                // Keep the prizes card as it is still relevant
                _buildPrizesCard(context, user.approvedPoisCount),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar Sesión'),
                ),
              ],
            ),
          );
        },
      ),
    );
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

  Widget _buildPrizesCard(BuildContext context, int prizeCount) {
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
