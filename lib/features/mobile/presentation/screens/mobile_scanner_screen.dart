import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MobileScannerScreen extends StatefulWidget {
  const MobileScannerScreen({super.key});

  @override
  State<MobileScannerScreen> createState() => _MobileScannerScreenState();
}

class _MobileScannerScreenState extends State<MobileScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isProcessing = false;
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    _audioPlayer.setSource(AssetSource('beep_loud.wav'));
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String code = barcodes.first.rawValue ?? '';
    if (code.isEmpty) return;

    // Evitar escaneos duplicados en menos de 2 segundos
    if (_lastScannedCode == code && _lastScanTime != null) {
      if (DateTime.now().difference(_lastScanTime!).inSeconds < 2) {
        return;
      }
    }

    _lastScannedCode = code;
    _lastScanTime = DateTime.now();

    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // FIX: Extraer providers antes del primer await (Async Gap)
    final apiClient = context.read<ApiClient>();

    try {
      try {
        if (_audioPlayer.state == PlayerState.playing) await _audioPlayer.stop();
        await _audioPlayer.play(AssetSource('beep_loud.wav'));
      } catch (_) {}

      // 🔄 FIX: Usar la URL configurada por el usuario (Smart Auto-Fallback)
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;

      final url = Uri.parse('$apiUrl/mobile/scan');
      final payload = jsonEncode({
        'barcode': code,
        'target_pc': 'caja-1', // Siempre la caja principal (no expuesto al empleado)
      });

      await apiClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Código enviado: $code'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escáner Inalámbrico'),
        backgroundColor: const Color(0xFF1E2D45),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 250,
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }
}
