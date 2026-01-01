import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/services/firestore_service.dart';

class FavoritesHistoryScreen extends StatefulWidget {
  const FavoritesHistoryScreen({super.key});

  @override
  State<FavoritesHistoryScreen> createState() => _FavoritesHistoryScreenState();
}

class _FavoritesHistoryScreenState extends State<FavoritesHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('No has iniciado sesión.')),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Favoritos e Historial'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.favorite, color: Colors.redAccent), text: 'Favoritos'),
              Tab(icon: Icon(Icons.history, color: Colors.blueGrey), text: 'Historial'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildPlacesList(context, user.uid, 'favorite_places', 'No tienes favoritos.'),
            _buildPlacesList(context, user.uid, 'history_places', 'No hay historial reciente.'),
          ],
        ),
      ),
    );
  }

  Widget _buildPlacesList(BuildContext context, String uid, String collection, String emptyText) {
    final colRef = FirebaseFirestore.instance.collection('users').doc(uid).collection(collection);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: colRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Text(emptyText));

        final docs = snap.data!.docs;
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final title = (data['name'] ?? data['pdiName'] ?? '') as String;
            final subtitle = (data['category'] ?? '') as String;

            return ListTile(
              title: Text(title, overflow: TextOverflow.ellipsis),
              subtitle: subtitle.isNotEmpty ? Text(subtitle.replaceAll('_', ' ')) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    tooltip: 'Eliminar',
                    onPressed: () async {
                      // ignore: use_build_context_synchronously
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Eliminar'),
                          content: Text(collection == 'history_places'
                              ? '¿Eliminar este historial?'
                              : '¿Eliminar este elemento?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
                          ],
                        ),
                      );
                      if (!mounted) return;
                      if (confirm != true) return;

                      try {
                        await colRef.doc(doc.id).delete();
                        if (!mounted) return;
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elemento eliminado'), backgroundColor: Colors.green));
                      } catch (e) {
                        if (!mounted) return;
                        // ignore: use_build_context_synchronously
                        await showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: const Text('Error'), content: Text('No se pudo eliminar: $e'), actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar'))]));
                      }
                    },
                  ),

                  // Admin-only: delete canonical POI if linked
                  Builder(builder: (ctx) {
                    final poiId = data['poiId'] ?? data['docId'];
                    if (poiId == null) return const SizedBox.shrink();
                    return FutureBuilder<bool>(
                      future: (() async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return false;
                        try {
                          return await FirestoreService().isAdmin(user.uid);
                        } catch (_) {
                          return false;
                        }
                      })(),
                      builder: (context, asnap) {
                        if (!asnap.hasData || asnap.data != true) return const SizedBox.shrink();
                        return IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                          tooltip: 'Eliminar PDI (solo admins)',
                          onPressed: () async {
                            final formKey = GlobalKey<FormState>();
                            final controller = TextEditingController();
                            // ignore: use_build_context_synchronously
                            final confirmed = await showDialog<bool>(
                              context: context,
                              barrierDismissible: false,
                              builder: (dctx) => AlertDialog(
                                title: const Text('Eliminar PDI (PERMANENTE)'),
                                content: Form(
                                  key: formKey,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Esta acción eliminará permanentemente el PDI. Escribe "ELIMINAR" para confirmar.'),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: controller,
                                        decoration: const InputDecoration(labelText: 'Escribe ELIMINAR para confirmar'),
                                        validator: (v) => v?.trim() == 'ELIMINAR' ? null : 'Debes escribir ELIMINAR',
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Cancelar')),
                                  ElevatedButton(onPressed: () {
                                    if (formKey.currentState?.validate() ?? false) Navigator.of(dctx).pop(true);
                                  }, child: const Text('Eliminar')),
                                ],
                              ),
                            );
                            if (!mounted) return;
                            if (confirmed != true) return;

                            try {
                              // Prefer deleting from Pdis_full if the canonical doc exists there.
                              final fullRef = FirebaseFirestore.instance.collection('Pdis_full').doc(poiId.toString());
                              final fullSnap = await fullRef.get();
                              if (fullSnap.exists) {
                                await fullRef.delete();
                              } else {
                                await FirebaseFirestore.instance.collection('pois').doc(poiId.toString()).delete();
                              }
                              if (!mounted) return;
                              // ignore: use_build_context_synchronously
                              await showDialog<void>(context: context, builder: (dctx) => AlertDialog(title: const Text('Eliminado'), content: const Text('PDI eliminado correctamente.'), actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Cerrar'))]));
                            } catch (e) {
                              if (!mounted) return;
                              // ignore: use_build_context_synchronously
                              await showDialog<void>(context: context, builder: (dctx) => AlertDialog(title: const Text('Error'), content: Text('No se pudo eliminar el PDI: $e'), actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Cerrar'))]));
                            }
                          },
                        );
                      },
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

