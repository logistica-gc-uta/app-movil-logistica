import 'package:app_movil_logistica/core/config/app_config.dart';
import 'package:flutter/material.dart';

class LogisticaApp extends StatelessWidget {
  const LogisticaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Logística UTA',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        appBar: AppBar(title: const Text('Logística UTA')),
        body: const Center(child: Text('API: ${AppConfig.apiBaseUrl}')),
      ),
    );
  }
}
