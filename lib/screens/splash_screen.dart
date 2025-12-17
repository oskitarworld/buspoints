
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:myapp/widgets/auth_gate.dart'; // Import AuthGate from its own file

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  // Display time before starting the fade (in seconds)
  static const int _displaySeconds = 3;
  // Fade duration
  static const Duration _fadeDuration = Duration(milliseconds: 600);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: _fadeDuration);
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // After the display period, start the fade and navigate when complete.
    Future.delayed(const Duration(seconds: _displaySeconds), () {
      if (!mounted) return;
      _controller.forward();
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (BuildContext context) => const AuthGate()),
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: FadeTransition(
          opacity: _opacity,
          child: Image.asset(
            'assets/images/pantalla_inicio.png',
            fit: BoxFit.fitWidth, // Ancho completo; barras negras arriba/abajo si hace falta
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
