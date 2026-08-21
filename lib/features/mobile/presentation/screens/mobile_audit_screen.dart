import 'package:flutter/material.dart';

class MobileAuditScreen extends StatelessWidget {
  const MobileAuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Auditoría (Góndola)'),
        backgroundColor: const Color(0xFF1E2D45),
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: const Color(0xFF1E2D45),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.construction, size: 80, color: Colors.orange),
              SizedBox(height: 20),
              Text(
                'Módulo en Construcción',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Próximamente podrás auditar\nprecios y stock desde aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
