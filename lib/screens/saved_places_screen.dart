import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedPlacesScreen extends StatelessWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('No has iniciado sesión.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lugares guardados'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('saved_places')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No tienes lugares guardados.'));
          }
          final places = snapshot.data!.docs;
          return ListView.separated(
            padding: const EdgeInsets.all(16.0),
            itemCount: places.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final place = places[index].data() as Map<String, dynamic>;
              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const Icon(Icons.place, color: Colors.redAccent, size: 32),
                  title: Text(place['name'] ?? 'Sin nombre', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (place['description'] != null && place['description'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(place['description'], style: const TextStyle(fontSize: 15)),
                        ),
                      if (place['category'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text('Categoría: ${place['category']}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ),
                      if (place['position'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text('Ubicación: ${place['position']}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    tooltip: 'Eliminar de guardados',
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('saved_places')
                          .doc(places[index].id)
                          .delete();
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
