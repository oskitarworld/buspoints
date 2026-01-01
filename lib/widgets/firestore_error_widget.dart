import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Returns a non-blocking widget for snapshot errors, with a friendly
/// message for permission-denied errors and a generic message otherwise.
Widget firestoreErrorWidget(BuildContext context, Object? error) {
  if (error is FirebaseException) {
    if (error.code == 'permission-denied' || (error.message ?? '').toLowerCase().contains('permission')) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Permisos insuficientes para leer estos datos. Inicia sesión con una cuenta con permisos o contacta al administrador.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          ),
        ),
      );
    }
  }
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('Error cargando datos: ${error ?? 'desconocido'}'),
    ),
  );
}
