
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:myapp/main.dart'; // Importa main.dart para acceder a AuthGate

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(
      const Duration(seconds: 3),
      () => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (BuildContext context) => const AuthGate()), // <<--- CORRECCIÓN AQUÍ
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Puedes cambiar el color de fondo
      body: Center(
        child: Image.asset(
          'assets/images/pantalla_inicio.png',
          fit: BoxFit.cover, // Ajusta la imagen para cubrir la pantalla
          height: double.infinity,
          width: double.infinity,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}
