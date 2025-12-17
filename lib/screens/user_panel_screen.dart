import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserPanelScreen extends StatefulWidget {
  const UserPanelScreen({super.key});

  @override
  State<UserPanelScreen> createState() => _UserPanelScreenState();
}

class _UserPanelScreenState extends State<UserPanelScreen> {
  int savedCount = 0;
  int favoriteCount = 0;
  int ratingsCount = 0;
  int historyCount = 0;
  int addedCount = 0;
  int reportsCount = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;
    final saved = await firestore.collection('users').doc(uid).collection('saved_places').get();
    final fav = await firestore.collection('users').doc(uid).collection('favorite_places').get();
    final ratings = await firestore.collection('places_ratings').where('userId', isEqualTo: uid).get();
    final history = await firestore.collection('users').doc(uid).collection('history_places').get();
    // Suponiendo colecciones 'added_pois' y 'reports' para aportaciones
    final added = await firestore.collection('users').doc(uid).collection('added_pois').get();
    final reports = await firestore.collection('users').doc(uid).collection('reports').get();
    setState(() {
      savedCount = saved.size;
      favoriteCount = fav.size;
      ratingsCount = ratings.size;
      historyCount = history.size;
      addedCount = added.size;
      reportsCount = reports.size;
      loading = false;
    });
  }

  Widget _buildStat(String label, int value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(label),
        trailing: Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildReward(String title, String desc, bool achieved) {
    return ListTile(
      leading: Icon(achieved ? Icons.emoji_events : Icons.lock, color: achieved ? Colors.amber : Colors.grey),
      title: Text(title),
      subtitle: Text(desc),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de usuario')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Estadísticas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  _buildStat('Lugares guardados', savedCount, Icons.bookmark),
                  _buildStat('Favoritos', favoriteCount, Icons.favorite),
                  _buildStat('Valoraciones/comentarios', ratingsCount, Icons.star),
                  _buildStat('PDIs consultados', historyCount, Icons.history),
                  _buildStat('PDIs añadidos', addedCount, Icons.add_location),
                  _buildStat('Reportes realizados', reportsCount, Icons.report),
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Recompensas', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  _buildReward('Explorador', 'Has consultado más de 10 PDIs', historyCount >= 10),
                  _buildReward('Colaborador', 'Has añadido al menos 1 PDI', addedCount >= 1),
                  _buildReward('Crítico', 'Has realizado 5 valoraciones', ratingsCount >= 5),
                  _buildReward('Reportero', 'Has reportado 3 incidencias', reportsCount >= 3),
                ],
              ),
            ),
    );
  }
}
