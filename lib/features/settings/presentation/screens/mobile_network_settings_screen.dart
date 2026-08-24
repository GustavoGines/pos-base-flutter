import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MobileNetworkSettingsScreen extends StatefulWidget {
  const MobileNetworkSettingsScreen({super.key});

  @override
  State<MobileNetworkSettingsScreen> createState() => _MobileNetworkSettingsScreenState();
}

class _MobileNetworkSettingsScreenState extends State<MobileNetworkSettingsScreen> {
  final _localCtrl = TextEditingController();
  final _remoteCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Ya no recortamos las URLs, dejamos que el usuario vea la ruta real completa.
    final savedLocal = prefs.getString('pos_api_local') ?? prefs.getString('pos_api') ?? '';
    final savedRemote = prefs.getString('pos_api_remote') ?? '';

    _localCtrl.text = savedLocal;
    _remoteCtrl.text = savedRemote;
    
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    final localUrl = _localCtrl.text.trim();
    final remoteUrl = _remoteCtrl.text.trim();

    if (localUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La URL Local es obligatoria')));
      return;
    }

    String cleanLocal = localUrl.trim();
    String cleanRemote = remoteUrl.trim();

    // --- AUTO-FORMATO UX (Solo si no empieza con http) ---
    if (cleanLocal.isNotEmpty && !cleanLocal.startsWith('http')) {
      if (!cleanLocal.contains('/')) {
        cleanLocal = 'http://$cleanLocal/Sistema_POS/pos-backend/public/api';
      } else {
        cleanLocal = 'http://$cleanLocal';
      }
    }
    
    if (cleanRemote.isNotEmpty && !cleanRemote.startsWith('http')) {
      if (!cleanRemote.contains('/')) {
        cleanRemote = 'https://$cleanRemote/Sistema_POS/pos-backend/public/api';
      } else {
        cleanRemote = 'https://$cleanRemote';
      }
    }

    cleanLocal = cleanLocal.endsWith('/') ? cleanLocal.substring(0, cleanLocal.length - 1) : cleanLocal;
    cleanRemote = cleanRemote.endsWith('/') ? cleanRemote.substring(0, cleanRemote.length - 1) : cleanRemote;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pos_api_local', cleanLocal);
    await prefs.setString('pos_api_remote', cleanRemote);
    await prefs.setString('pos_api', cleanLocal);

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Reiniciar Aplicación'),
          content: const Text('Las configuraciones de red han sido guardadas. Para que el Auto-Fallback detecte la nueva red, cierra completamente la app y vuelve a abrirla.'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Red'),
        backgroundColor: const Color(0xFF1E2D45),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Smart Auto-Fallback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('El sistema intentará conectarse primero a la Red Local porque es más rápida. Si falla (ej. estás usando 4G fuera del negocio), cambiará automáticamente a la Red Remota de forma invisible.', style: TextStyle(color: Colors.black54)),
                  const SizedBox(height: 32),
                  TextField(controller: _localCtrl, decoration: InputDecoration(labelText: 'IP Local (WiFi del Negocio)', hintText: 'Solo números, ej: 192.168.1.50', prefixIcon: const Icon(Icons.wifi), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), keyboardType: TextInputType.url),
                  const SizedBox(height: 20),
                  TextField(controller: _remoteCtrl, decoration: InputDecoration(labelText: 'URL Remota (Cloudflare)', hintText: 'Dominio, ej: kiosco.sistema-pos.com', prefixIcon: const Icon(Icons.cloud_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))), keyboardType: TextInputType.url),
                  const SizedBox(height: 40),
                  SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(icon: const Icon(Icons.save), label: const Text('Guardar Configuración'), onPressed: _saveSettings)),
                ],
              ),
            ),
    );
  }
}

