import 'package:flutter/material.dart';
import 'package:myapp/widgets/app_drawer.dart'; // Import the new AppDrawer
import 'package:myapp/screens/approve_users_screen.dart';
import 'package:myapp/screens/manage_users_screen.dart';
import 'package:myapp/screens/poi_approval_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel de Administración'),
        backgroundColor: Colors.red[800],
      ),
      drawer: const AppDrawer(), // Add the drawer here
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildAdminCard(
            context: context,
            icon: Icons.person_add_alt_1_outlined,
            title: 'Aprobar Usuarios',
            subtitle: 'Revisar y aprobar usuarios pendientes.',
            color: Colors.blue.shade700,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ApproveUsersScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildAdminCard(
            context: context,
            icon: Icons.people_alt_outlined,
            title: 'Gestionar Usuarios',
            subtitle: 'Ver, editar o eliminar usuarios del sistema.',
            color: Colors.purple.shade700,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const ManageUsersScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          _buildAdminCard(
            context: context,
            icon: Icons.location_on_sharp,
            title: 'Aprobar Puntos de Interés',
            subtitle: 'Revisar y aprobar PDI enviados por los usuarios.',
            color: Colors.orange.shade800,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PoiApprovalScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAdminCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: color,
                child: Icon(icon, size: 30, color: Colors.white),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
