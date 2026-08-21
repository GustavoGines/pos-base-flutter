import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';

class MobileMenuScreen extends StatelessWidget {
  const MobileMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Herramientas Móviles'),
        backgroundColor: const Color(0xFF1E2D45),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Bloquear Pantalla',
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/login');
              context.read<AuthProvider>().logout();
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFF1E2D45),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            _buildMenuCard(
              context,
              title: 'Escáner Inalámbrico',
              subtitle: 'Envía códigos a la PC en tiempo real',
              icon: Icons.qr_code_scanner,
              color: Colors.blueAccent,
              onTap: () => Navigator.pushNamed(context, '/mobile-scanner'),
            ),
            const SizedBox(height: 16),
            _buildMenuCard(
              context,
              title: 'Control de Precios y Stock',
              subtitle: 'Consultar y editar precios/stock',
              icon: Icons.inventory_2,
              color: Colors.green,
              onTap: () => Navigator.pushNamed(context, '/mobile-audit'),
            ),
            const SizedBox(height: 16),
            _buildMenuCard(
              context,
              title: 'Panel de Ventas',
              subtitle: 'Resumen de ventas en vivo',
              icon: Icons.bar_chart,
              color: Colors.orange,
              onTap: () => Navigator.pushNamed(context, '/mobile-dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white.withValues(alpha: 0.05),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.white.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
