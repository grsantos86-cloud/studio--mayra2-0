import 'package:flutter/material.dart';

void main() => runApp(const StudioMayra());

class StudioMayra extends StatelessWidget {
  const StudioMayra({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Studio Mayra 2.0',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'Studio Mayra 2.0 — pronto para build no GitHub!',
            style: TextStyle(fontSize: 20),
          ),
        ),
      ),
    );
  }
}
