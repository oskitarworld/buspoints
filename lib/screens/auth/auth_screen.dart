import 'package:flutter/material.dart';
import 'package:myapp/screens/auth/signin_screen.dart';
import 'package:myapp/screens/auth/signup_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;

  void _toggleAuthMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isLogin
        ? SignInScreen(onToggleAuthMode: _toggleAuthMode)
        : SignUpScreen(onToggleAuthMode: _toggleAuthMode);
  }
}
