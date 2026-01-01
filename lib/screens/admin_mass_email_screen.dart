import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

class AdminMassEmailScreen extends StatefulWidget {
  const AdminMassEmailScreen({super.key});

  @override
  State<AdminMassEmailScreen> createState() => _AdminMassEmailScreenState();
}

class _AdminMassEmailScreenState extends State<AdminMassEmailScreen> {
  String _subject = '';
  String _body = '';
  bool _isHtml = true;
  String _targetMode = 'all';
  String _manualEmailsText = '';
  bool _sending = false;

  Future<void> _preview() async {
    final messenger = ScaffoldMessenger.of(context);
    final functions = FirebaseFunctions.instance;
    final payload = <String, dynamic>{'subject': _subject.trim(), _isHtml ? 'html' : 'text': _body, 'preview': true, 'limit': 500};
    if (_targetMode == 'manual') {
      final emails = _manualEmailsText.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      payload['mode'] = 'manual';
      payload['manualEmails'] = emails;
    } else if (_targetMode == 'subscribers' || _targetMode == 'admins') {
      payload['mode'] = 'segment';
      payload['segment'] = _targetMode;
    } else {
      payload['mode'] = 'all';
    }

    try {
      final res = await functions.httpsCallable('adminSendMassEmail').call(payload);
      final data = res.data as Map<String, dynamic>;
      final count = data['count'] ?? 0;
      final sample = (data['sample'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      // Guard against widget disposal while awaiting the callable.
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (c) => AlertDialog(
        title: const Text('Vista previa'),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Se enviará a $count usuarios.'), const SizedBox(height: 8), const Text('Ejemplos:'), const SizedBox(height: 6), ...sample.map((e) => Text(e))])),
        actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cerrar'))],
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error en vista previa: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final functions = FirebaseFunctions.instance;
    final payload = <String, dynamic>{'subject': _subject.trim(), _isHtml ? 'html' : 'text': _body, 'preview': false, 'limit': 0};
    if (_targetMode == 'manual') {
      final emails = _manualEmailsText.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      payload['mode'] = 'manual';
      payload['manualEmails'] = emails;
    } else if (_targetMode == 'subscribers' || _targetMode == 'admins') {
      payload['mode'] = 'segment';
      payload['segment'] = _targetMode;
    } else {
      payload['mode'] = 'all';
    }

    setState(() => _sending = true);
    try {
      final res = await functions.httpsCallable('adminSendMassEmail').call(payload);
      final data = res.data as Map<String, dynamic>;
      final sent = data['sent'] ?? 0;
      final failed = data['failed'] ?? 0;
      messenger.showSnackBar(SnackBar(content: Text('Envío terminado. Enviados: $sent, Fallidos: $failed'), backgroundColor: Colors.green));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Error enviando: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
  // drawer already restricts access; keep simple
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar email masivo')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(decoration: const InputDecoration(labelText: 'Asunto'), onChanged: (v) => _subject = v),
            const SizedBox(height: 8),
            TextField(decoration: const InputDecoration(labelText: 'Cuerpo (HTML soportado)'), maxLines: 8, onChanged: (v) => _body = v),
            const SizedBox(height: 8),
            Row(children: [Checkbox(value: _isHtml, onChanged: (v) => setState(() => _isHtml = v ?? true)), const SizedBox(width: 8), const Text('Enviar como HTML')]),
            const SizedBox(height: 8),
            Row(children: [const Text('Enviar a:'), const SizedBox(width: 12), DropdownButton<String>(value: _targetMode, items: const [DropdownMenuItem(value: 'all', child: Text('Todos')), DropdownMenuItem(value: 'subscribers', child: Text('Suscriptores')), DropdownMenuItem(value: 'admins', child: Text('Admins')), DropdownMenuItem(value: 'manual', child: Text('Seleccionar emails'))], onChanged: (v) => setState(() => _targetMode = v ?? 'all'))]),
            if (_targetMode == 'manual') ...[
              const SizedBox(height: 8),
              TextField(decoration: const InputDecoration(labelText: 'Emails (separados por coma)'), maxLines: 3, onChanged: (v) => _manualEmailsText = v),
            ],
            const SizedBox(height: 12),
            Row(children: [ElevatedButton(onPressed: _sending ? null : _preview, child: const Text('Vista previa')), const SizedBox(width: 12), ElevatedButton(onPressed: _sending ? null : _send, child: const Text('Enviar'))])
          ]),
        ),
      ),
    );
  }
}
