import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../core/config/app_config.dart';

/// Widget que muestra el QR para que empleados descarguen la app Android.
///
/// Estrategia:
///   1. Consulta al License Server el último release `component=android`.
///   2. Muestra la versión disponible junto al QR.
///   3. Si la consulta falla, usa la URL fallback `pos_mobile_latest.apk`
///      para que el QR siempre funcione sin depender de la red.
class MobileAppQrSection extends StatefulWidget {
  final String r2PublicBaseUrl;

  const MobileAppQrSection({
    super.key,
    required this.r2PublicBaseUrl,
  });

  @override
  State<MobileAppQrSection> createState() => _MobileAppQrSectionState();
}

class _MobileAppQrSectionState extends State<MobileAppQrSection> {
  String? _apkUrl;
  String? _apkVersion;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadApkInfo();
  }

  Future<void> _loadApkInfo() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final updateChannel = prefs.getString('update_channel') ?? 'stable';

      final uri =
          Uri.parse('${AppConfig.kLicenseServerUrl}/api/check-update').replace(
        queryParameters: {
          'component': 'android',
          'current_version': '0.0.0',
          'channel': updateChannel,
        },
      );

      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['data'] != null) {
          final releaseData = data['data'] as Map<String, dynamic>;
          setState(() {
            _apkUrl = releaseData['download_url'] as String?;
            _apkVersion = releaseData['version'] as String?;
          });
          return;
        }
      }
    } on TimeoutException {
      debugPrint('[QR] License server tardó demasiado, usando URL fallback.');
    } catch (e) {
      debugPrint('[QR] Error consultando license server: $e');
    }

    // Fallback: URL fija del `latest.apk` en R2 — siempre disponible
    setState(() {
      _apkUrl = '${widget.r2PublicBaseUrl}/mobile/pos_mobile_latest.apk';
      _apkVersion = null; // versión desconocida en fallback
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2D45).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone_android,
                    color: Color(0xFF1E2D45), size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'App Móvil (Terminal & Gestión)',
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A2E)),
                    ),
                    if (_apkVersion != null)
                      Text(
                        'Versión ${'$_apkVersion'} disponible',
                        style: TextStyle(
                            fontSize: 12, color: Colors.green.shade700),
                      ),
                  ],
                ),
              ),
              // Botón de recargar
              IconButton(
                onPressed: _loadApkInfo,
                icon: const Icon(Icons.refresh_outlined),
                tooltip: 'Recargar',
                color: Colors.grey.shade500,
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_isLoading && _apkUrl == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_apkUrl != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── QR Code ────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: QrImageView(
                      data: _apkUrl!,
                      version: QrVersions.auto,
                      size: 190,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.all(12),
                    ),
                  ),
                ),
                const SizedBox(width: 28),

                // ── Instrucciones ──────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStep(
                        '1',
                        'Escaneá el QR',
                        'Abrí la cámara de tu celular Android y apuntala al código.',
                      ),
                      const SizedBox(height: 16),
                      _buildStep(
                        '2',
                        'Descargá el APK',
                        'El navegador descargará el archivo POS Móvil automáticamente.',
                      ),
                      const SizedBox(height: 16),
                      _buildStep(
                        '3',
                        'Instalá la app',
                        'Abrí el archivo descargado. Si se pide permiso para instalar apps desconocidas, habilitalo.',
                      ),
                      const SizedBox(height: 20),

                      // URL copiable
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _apkUrl!,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: Color(0xFF444444)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(
                                    ClipboardData(text: _apkUrl!));
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content:
                                      Text('URL copiada al portapapeles'),
                                  duration: Duration(seconds: 2),
                                ));
                              },
                              child: const Icon(Icons.copy_outlined,
                                  size: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStep(String number, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFF1E2D45),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF1A1A2E))),
              const SizedBox(height: 2),
              Text(description,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
