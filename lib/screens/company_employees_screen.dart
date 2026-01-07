import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';

class CompanyEmployeesScreen extends StatefulWidget {
  final String? companyId;
  const CompanyEmployeesScreen({super.key, this.companyId});

  @override
  State<CompanyEmployeesScreen> createState() => _CompanyEmployeesScreenState();
}

class _CompanyEmployeesScreenState extends State<CompanyEmployeesScreen> {
  String? _companyId;
  final _emailController = TextEditingController();
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _companyResolveError;
  List<Map<String, dynamic>>? _fallbackEmployees;
  bool _loadingFallback = false;
  String? _fallbackError;

  @override
  void initState() {
    super.initState();
    _companyId = widget.companyId;
    _initCompanyIdIfNeeded();
    // If a companyId was provided (e.g. when navigating), load server data immediately
    if (_companyId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadEmployeesFallback();
      });
    }
  }

  Future<void> _initCompanyIdIfNeeded() async {
    if (_companyId != null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // 1) Try user's doc first (preferred: user.companyId or user.companyIds)
      final uDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (uDoc.exists) {
        final d = uDoc.data();
          if (d != null) {
          if (d['companyId'] != null) {
            setState(() { _companyId = d['companyId'] as String?; });
            await _loadEmployeesFallback();
            return;
          }
          if (d['companyIds'] != null && d['companyIds'] is List && (d['companyIds'] as List).isNotEmpty) {
            setState(() { _companyId = (d['companyIds'] as List).first as String?; });
            await _loadEmployeesFallback();
            return;
          }
          // If this user itself is a company account, use their uid as companyId
          if (d['role'] == 'company') {
            setState(() { _companyId = user.uid; });
            await _loadEmployeesFallback();
            return;
          }
        }
      }

      // 2) Query companies by several common ownership/admin fields
      // Try ownerUid, owner, admins (array-contains), owners (array-contains)
      // Try querying companies where this user is owner/admin/owner list.
      // Wrap every query in try/catch because security rules may deny these reads.
      try {
        final q1 = await FirebaseFirestore.instance.collection('companies').where('ownerUid', isEqualTo: user.uid).limit(1).get();
        if (q1.docs.isNotEmpty) { setState(() { _companyId = q1.docs.first.id; }); await _loadEmployeesFallback(); return; }
      } catch (_) {}
      try {
        final q2 = await FirebaseFirestore.instance.collection('companies').where('owner', isEqualTo: user.uid).limit(1).get();
        if (q2.docs.isNotEmpty) { setState(() { _companyId = q2.docs.first.id; }); await _loadEmployeesFallback(); return; }
      } catch (_) {}
      try {
        final q3 = await FirebaseFirestore.instance.collection('companies').where('admins', arrayContains: user.uid).limit(1).get();
        if (q3.docs.isNotEmpty) { setState(() { _companyId = q3.docs.first.id; }); await _loadEmployeesFallback(); return; }
      } catch (_) {}
      try {
        final q4 = await FirebaseFirestore.instance.collection('companies').where('owners', arrayContains: user.uid).limit(1).get();
        if (q4.docs.isNotEmpty) { setState(() { _companyId = q4.docs.first.id; }); await _loadEmployeesFallback(); return; }
      } catch (_) {}

      // 3) As last resort, try token custom claims (companyIds)
      try {
        final idTokenResult = await user.getIdTokenResult();
        final claims = idTokenResult.claims ?? {};
        if (claims['companyIds'] != null) {
          final cis = claims['companyIds'];
          if (cis is List && cis.isNotEmpty) {
              setState(() { _companyId = cis.first as String?; });
              await _loadEmployeesFallback();
              return;
            }
            if (cis is String && cis.isNotEmpty) {
              setState(() { _companyId = cis; });
              await _loadEmployeesFallback();
              return;
            }
        }
      } catch (e) {
        // ignore token errors, continue
      }
    } catch (e) {
      debugPrint('Error resolving companyId: $e');
      setState(() { _companyResolveError = 'Error: $e'; });
    }
    if (_companyId == null) {
      setState(() {
        _companyResolveError = _companyResolveError ?? 'No se ha podido localizar la empresa. Comprueba que tu usuario es el owner/admin de una empresa o selecciona la empresa manualmente.';
      });
    }
  }

  Future<void> _invite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    if (_companyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se ha podido resolver la empresa')));
      return;
    }
    setState(() { _loading = true; });
    try {
      // Explicitly target the region where functions are deployed (us-central1)
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('companyInviteEmployee');
          final name = _nameController.text.trim();
            final res = await callable.call({'companyId': _companyId, 'email': email, 'name': name});
      if (!mounted) return;
      final data = res.data as Map<String, dynamic>?;
      final status = data != null && data['status'] != null ? data['status'] as String : null;
  if (status == 'no_such_user') {
        if (!mounted) return;
        await showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Invitar empleado'), content: const Text('Este usuario no existe en la aplicación.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
      } else if (status == 'no_active_subscription') {
        if (!mounted) return;
        await showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Invitar empleado'), content: const Text('El usuario no tiene una suscripción activa. No se puede añadir.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
      } else if (status == 'already_member') {
        if (!mounted) return;
        await showDialog(context: context, builder: (_) => AlertDialog(title: const Text('Invitar empleado'), content: const Text('El usuario ya forma parte del equipo.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
      } else if (status == 'added') {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trabajador añadido correctamente.')));
        _emailController.clear();
            _nameController.clear();
        // Optimistic UI: add the invited entry locally so the list shows the
        // newly invited user immediately even if we can't read the employees
        // collection due to security rules. We'll store minimal info (displayName/email)
        // under _fallbackEmployees so it appears in the UI.
        try {
          final localName = (name.isNotEmpty) ? name : email;
          final entry = {'id': email, 'data': {'displayName': localName, 'email': email, 'role': 'employee', 'active': false}};
          _fallbackEmployees ??= <Map<String, dynamic>>[];
          _fallbackEmployees!.insert(0, entry);
          if (mounted) setState(() {});
        } catch (_) {}
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Resultado: $status')));
      }
      } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error inesperado')));
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _loadEmployeesFallback() async {
    if (_companyId == null) return;
    setState(() { _loadingFallback = true; _fallbackError = null; _fallbackEmployees = null; });
    try {
      // Use the same explicit region for list fallback
      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
      final res = await functions.httpsCallable('companyListEmployees').call({'companyId': _companyId});
      final dataRaw = res.data as Map?;
      if (dataRaw == null || dataRaw['status'] != 'ok' || dataRaw['employees'] == null) {
        if (!mounted) return;
        setState(() { _fallbackError = 'No hay empleados registrados o error en la función (${dataRaw?['status']})'; });
      } else {
        final List items = dataRaw['employees'] as List? ?? [];
        final parsed = items.map<Map<String, dynamic>>((e) {
          final id = (e is Map && e['id'] != null) ? e['id'].toString() : '';
          final rawMd = (e is Map && e['data'] != null) ? e['data'] as Map? : null;
          final md = rawMd != null ? Map<String, dynamic>.from((rawMd).cast<String, dynamic>()) : <String, dynamic>{};
          return {'id': id, 'data': md};
        }).toList();
        if (mounted) setState(() { _fallbackEmployees = parsed; _fallbackError = null; });
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) setState(() { _fallbackError = 'Error functions: ${e.message ?? e.code}'; });
    } catch (e) {
      if (mounted) setState(() { _fallbackError = 'Error: $e'; });
    } finally {
      if (mounted) setState(() { _loadingFallback = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de empleados'),
        actions: [
          // Debug: quick button to connect to local emulator for fast testing
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.usb),
              tooltip: 'Conectar a emulador',
              onPressed: _showEmulatorDialog,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invitar trabajador', style: Theme.of(context).textTheme.titleMedium ?? const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            // Nombre y apellidos del trabajador
            Row(children: [
              Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(hintText: 'Nombre y apellidos'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: _emailController, decoration: const InputDecoration(hintText: 'email@ejemplo.com'))),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _loading ? null : _invite, child: _loading ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Añadir trabajador'))
            ]),
            const SizedBox(height: 20),
            const Text('Empleados', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
        child: _companyId == null
          ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(_companyResolveError ?? 'No se ha podido localizar la empresa.', textAlign: TextAlign.center),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.business),
                          label: const Text('Seleccionar empresa manualmente'),
                          onPressed: _selectCompanyManual,
                        ),
                      ],
                    )
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadEmployeesFallback();
                    },
                    child: _loadingFallback
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            children: [
                              if (_fallbackError != null) Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(_fallbackError!, style: const TextStyle(color: Colors.red)),
                              ),
                              Expanded(
                                child: (_fallbackEmployees != null && _fallbackEmployees!.isNotEmpty)
                                    ? ListView.builder(
                                        itemCount: _fallbackEmployees!.length,
                                        itemBuilder: (context, index) {
                                          final row = _fallbackEmployees![index];
                                          final id = row['id']?.toString() ?? '';
                                          final raw = row['data'];
                                          final md = (raw is Map) ? Map<String, dynamic>.from(raw.cast<String, dynamic>()) : <String, dynamic>{};
                                          // Show delete button before the status icon
                                          return ListTile(
                                            leading: const Icon(Icons.person),
                                            title: Text(md['displayName'] ?? md['email'] ?? id),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                // Delete/trash button
                                                IconButton(
                                                  icon: const Icon(Icons.delete, color: Colors.red),
                                                  tooltip: 'Eliminar empleado',
                                                  onPressed: () async {
                                                    final messenger = ScaffoldMessenger.of(context);
                                                    // If this entry is only an optimistic local invite (email id), remove locally
                                                    if (id.contains('@')) {
                                                      _fallbackEmployees!.removeAt(index);
                                                      if (mounted) setState(() {});
                                                      return;
                                                    }
                                                    final confirm = await showDialog<bool>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: const Text('Eliminar empleado'),
                                                        content: Text('¿Eliminar a ${md['displayName'] ?? id} de la empresa?'),
                                                        actions: [
                                                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                                                          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Eliminar')),
                                                        ],
                                                      ),
                                                    );
                                                    if (confirm != true) return;
                                                    try {
                                                      final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
                                                      final callable = functions.httpsCallable('companyRemoveEmployee');
                                                      messenger.showSnackBar(const SnackBar(content: Text('Eliminando...')));
                                                      final res = await callable.call({'companyId': _companyId, 'uid': id});
                                                      final data = res.data as Map<String, dynamic>?;
                                                      final status = data != null ? data['status'] as String? : null;
                                                      if (status == 'ok') {
                                                        // remove from local fallback list if present
                                                        if (_fallbackEmployees != null) {
                                                          _fallbackEmployees!.removeWhere((e) => (e['id']?.toString() ?? '') == id);
                                                        }
                                                        messenger.showSnackBar(const SnackBar(content: Text('Empleado eliminado')));
                                                        if (mounted) setState(() {});
                                                      } else if (status == 'not_member') {
                                                        messenger.showSnackBar(const SnackBar(content: Text('El usuario no es miembro de la empresa')));
                                                      } else {
                                                        messenger.showSnackBar(SnackBar(content: Text('Resultado: $status')));
                                                      }
                                                    } catch (e) {
                                                      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Error eliminando empleado: $e')));
                                                    }
                                                  },
                                                ),
                                                md['active'] == true ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.hourglass_top, color: Colors.orange),
                                              ],
                                            ),
                                          );
                                        },
                                      )
                                    : ListView(
                                        children: const [
                                          SizedBox(height: 32),
                                          Center(child: Text('No hay empleados registrados.')),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                  ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _showEmulatorDialog() async {
    final hostController = TextEditingController(text: '10.0.2.2');
    final firestorePortController = TextEditingController(text: '8080');
    final functionsPortController = TextEditingController(text: '5001');
    final result = await showDialog<bool?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Conectar a emulador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: hostController, decoration: const InputDecoration(labelText: 'Host (IP)')),
            TextField(controller: firestorePortController, decoration: const InputDecoration(labelText: 'Firestore port')),
            TextField(controller: functionsPortController, decoration: const InputDecoration(labelText: 'Functions port')),
            const SizedBox(height: 8),
            const Text('Nota: usa 10.0.2.2 para emulador Android o la IP de tu Mac para dispositivo físico.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Conectar')),
        ],
      ),
    );
    if (result != true) return;
    final host = hostController.text.trim();
    final fp = int.tryParse(firestorePortController.text.trim()) ?? 8080;
    final fup = int.tryParse(functionsPortController.text.trim()) ?? 5001;
    try {
      FirebaseFirestore.instance.useFirestoreEmulator(host, fp);
    } catch (e) {
      debugPrint('Error connecting Firestore emulator: $e');
    }
    try {
      FirebaseFunctions.instanceFor(region: 'us-central1').useFunctionsEmulator(host, fup);
    } catch (e) {
      debugPrint('Error connecting Functions emulator: $e');
    }
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Conectado a emulador $host:$fp (Firestore) y $host:$fup (Functions)')));
  }

  Future<void> _selectCompanyManual() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final firestore = FirebaseFirestore.instance;
      final results = <QueryDocumentSnapshot>[];
      // Run several queries and merge unique results
      try {
        final q1 = await firestore.collection('companies').where('ownerUid', isEqualTo: user.uid).get();
        results.addAll(q1.docs);
      } catch (_) {}
      try {
        final q2 = await firestore.collection('companies').where('owner', isEqualTo: user.uid).get();
        results.addAll(q2.docs);
      } catch (_) {}
      try {
        final q3 = await firestore.collection('companies').where('admins', arrayContains: user.uid).get();
        results.addAll(q3.docs);
      } catch (_) {}
      try {
        final q4 = await firestore.collection('companies').where('owners', arrayContains: user.uid).get();
        results.addAll(q4.docs);
      } catch (_) {}

      // Deduplicate by id
      final map = <String, QueryDocumentSnapshot>{};
        for (final d in results) {
          map[d.id] = d;
        }
      final list = map.values.toList();

      if (list.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se han encontrado empresas asociadas a tu cuenta')));
        return;
      }

      // Show selection dialog
      if (!mounted) return;
      final picked = await showDialog<String?>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Selecciona una Empresa'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final doc = list[i];
                  final name = (doc.data() as Map<String, dynamic>?)?['name'] ?? doc.id;
                  return ListTile(
                    title: Text(name.toString()),
                    subtitle: Text(doc.id),
                    onTap: () => Navigator.of(ctx).pop(doc.id),
                  );
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar'))],
          );
        },
      );

      if (picked != null) {
        setState(() { _companyId = picked; _companyResolveError = null; });
        await _loadEmployeesFallback();
      }
      } catch (e) {
        debugPrint('selectCompanyManual error: $e');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error buscando empresas: $e')));
      }
  }
}
