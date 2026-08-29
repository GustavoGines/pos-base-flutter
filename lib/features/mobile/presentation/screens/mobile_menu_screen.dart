import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/screens/mobile_network_settings_screen.dart';
import 'package:frontend_desktop/features/updater/data/services/mobile_update_service.dart';
import 'package:frontend_desktop/features/updater/presentation/widgets/mobile_update_dialog.dart';

class MobileMenuScreen extends StatefulWidget {
  const MobileMenuScreen({super.key});

  @override
  State<MobileMenuScreen> createState() => _MobileMenuScreenState();
}

class _MobileMenuScreenState extends State<MobileMenuScreen> {
  @override
  void initState() {
    super.initState();
    // Chequear actualizaciones disponibles al abrir la pantalla principal
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final update = await MobileUpdateService.checkForUpdate();
    if (!mounted) return;
    if (update != null) {
      await showDialog(
        context: context,
        barrierDismissible: !update.isCritical,
        builder: (_) => MobileUpdateDialog(updateInfo: update),
      );
    }
  }

  String _getFormattedDate() {
    try {
      final now = DateTime.now();
      final formatter = DateFormat('EEE d MMM', 'es_AR');
      final dateStr = formatter.format(now);
      return dateStr[0].toUpperCase() + dateStr.substring(1);
    } catch (_) {
      return DateFormat('dd/MM/yyyy').format(DateTime.now());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Móvil'),
        backgroundColor: const Color(0xFF1E2D45),
        foregroundColor: Colors.white,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                _getFormattedDate(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración de Red',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MobileNetworkSettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Bloquear Pantalla',
            onPressed: () {
              context.read<AuthProvider>().logout();
              Navigator.pushReplacementNamed(context, '/login');
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
