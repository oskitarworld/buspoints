import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:myapp/constants/categories.dart';

class AdminPdisReviewScreen extends StatefulWidget {
  const AdminPdisReviewScreen({super.key});

  @override
  State<AdminPdisReviewScreen> createState() => _AdminPdisReviewScreenState();
}

class _AdminPdisReviewScreenState extends State<AdminPdisReviewScreen> {
  final List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _items.clear(); });
    // capture messenger before any awaits to avoid using BuildContext after an await
    final messenger = ScaffoldMessenger.of(context);
    try {
      final functions = FirebaseFunctions.instance;
      final res = await functions.httpsCallable('adminListPdis').call();
      final payload = res.data as Map<String, dynamic>?;
      final items = payload != null && payload['items'] is List ? (payload['items'] as List) : <dynamic>[];
      for (final it in items) {
        try {
          final m = Map<String, dynamic>.from(it as Map);
          final coll = m['collection'] as String? ?? '';
          final id = m['id'] as String? ?? '';
          final dat = Map<String, dynamic>.from(m['data'] as Map? ?? {});
          _items.add({'collection': coll, 'id': id, 'data': dat});
        } catch (e) {
          // ignore
        }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error cargando PDIs: $e'), backgroundColor: Colors.red));
    }
    setState(() { _loading = false; });
  }

  Future<void> _openItem(Map<String, dynamic> item) async {
    final collection = item['collection'] as String;
    final id = item['id'] as String;
    final data = Map<String, dynamic>.from(item['data'] as Map);
    String newCategory = (data['category'] ?? '').toString();

    await showDialog<void>(context: context, builder: (ctx) {
      return AlertDialog(
        title: Text('${data['name'] ?? data['title'] ?? id}'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...data.entries.map((e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 110, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Expanded(child: Text(e.value == null ? '' : e.value.toString())),
              ]),
            )),
            const SizedBox(height: 12),
            // Category dropdown using shared categories list
            StatefulBuilder(builder: (context, setState) {
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Categoría (editable)'),
                initialValue: kAvailableCategories.contains(newCategory) ? newCategory : null,
                items: kAvailableCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) { setState(() { newCategory = v ?? ''; }); },
              );
            }),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cerrar')),
          TextButton(onPressed: () async {
            Navigator.of(ctx).pop();
            await _saveCategoryChange(collection, id, newCategory);
          }, child: const Text('Guardar')),
        ],
      );
    });
  }

  Future<void> _saveCategoryChange(String collection, String id, String newCategory) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final functions = FirebaseFunctions.instance;
      await functions.httpsCallable('adminUpdatePdi').call(<String, dynamic>{ 'collection': collection, 'id': id, 'newCategory': newCategory });
      // remove from local list
      setState(() { _items.removeWhere((it) => it['collection'] == collection && it['id'] == id); });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error guardando: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Revisión PDIs (Admin)')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _loadAll,
        child: _items.isEmpty ? ListView(children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No hay PDIs en la lista'),
                  const SizedBox(height: 12),
                    ElevatedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final Uri wa = Uri.parse('https://wa.me/?text=Te%20recomiendo%20BusPoints,%20una%20app%20para%20encontrar%20PDIs%20y%20paradas%20por%20Europa.%20https://buspoints.net');
                      try {
                        final launched = await launchUrl(wa, mode: LaunchMode.externalApplication);
                        if (!launched) {
                          await SharePlus.instance.share(ShareParams(text: 'Te recomiendo BusPoints, una app para encontrar PDIs y paradas por Europa. https://buspoints.net'));
                        }
                      } catch (e) {
                        try {
                          await SharePlus.instance.share(ShareParams(text: 'Te recomiendo BusPoints, una app para encontrar PDIs y paradas por Europa. https://buspoints.net'));
                        } catch (_) {
                          messenger.showSnackBar(SnackBar(content: Text('Error abriendo WhatsApp: $e')));
                        }
                      }
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('Recomiéndanos en WhatsApp'),
                    style: ElevatedButton.styleFrom(),
                  ),
                ],
              ),
            ),
          ),
        ]) : ListView.separated(
          itemCount: _items.length,
          separatorBuilder: (_,__) => const Divider(height: 1),
          itemBuilder: (context, idx) {
            final it = _items[idx];
            final coll = it['collection'] as String;
            final id = it['id'] as String;
            final data = it['data'] as Map<String, dynamic>;
            final title = (data['name'] ?? data['title'] ?? id).toString();
            final subtitle = (data['category'] ?? '').toString();
            return ListTile(
              title: Text(title),
              subtitle: Text('$coll — $subtitle'),
              trailing: const Icon(Icons.edit),
              onTap: () => _openItem(it),
            );
          },
        ),
      ),
    );
  }
}
