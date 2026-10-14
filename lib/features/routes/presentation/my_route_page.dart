import 'package:app_movil_logistica/features/auth/data/auth_session.dart';
import 'package:flutter/material.dart';

class MyRoutePage extends StatelessWidget {
  const MyRoutePage({super.key, required this.user, required this.onLogout});

  final AuthUser user;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Ruta del Día'),
        actions: [
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
      body: Center(child: Text('Hola, ${user.name}')),
    );
  }
}
