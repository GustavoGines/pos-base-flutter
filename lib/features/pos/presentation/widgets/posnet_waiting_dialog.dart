import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/utils/currency_formatter.dart';

class PosnetWaitingDialog extends StatefulWidget {
  final double amount;
  final String? description;
  final String? deviceId;
  final String? externalReference;
  final ApiClient? client;
  final String? baseUrl;

  const PosnetWaitingDialog({
    super.key,
    required this.amount,
    this.description,
    this.deviceId,
    this.externalReference,
    this.client,
    this.baseUrl,
  });

  @override
  State<PosnetWaitingDialog> createState() => _PosnetWaitingDialogState();
}

class _PosnetWaitingDialogState extends State<PosnetWaitingDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _externalReference;
  String? _paymentIntentId;
  bool _isApproved = false;
  String? _mpPaymentId;

  Timer? _pollingTimer;
  PusherChannelsClient? _pusher;
  bool _isResolved = false;

  @override
  void initState() {
    super.initState();
    _externalReference = widget.externalReference;
    _createPointIntent();
  }

  ApiClient _getClient() {
    if (widget.client != null) return widget.client!;
    return context.read<ApiClient>();
  }

  Future<String> _getApiUrl() async {
    if (widget.baseUrl != null && widget.baseUrl!.isNotEmpty) {
      return widget.baseUrl!;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
  }

  Future<void> _createPointIntent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = _getClient();
      final apiUrl = await _getApiUrl();

      final body = <String, dynamic>{
        'amount': widget.amount,
        'description': widget.description ?? 'Cobro POS Mostrador',
        if (widget.deviceId != null && widget.deviceId!.isNotEmpty)
          'device_id': widget.deviceId,
        if (_externalReference != null && _externalReference!.isNotEmpty)
          'external_reference': _externalReference,
      };

      final response = await client.post(
        Uri.parse('$apiUrl/pos/mp/create-point-intent'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['success'] == true) {
          setState(() {
            _externalReference = data['external_reference']?.toString();
            _paymentIntentId = data['payment_intent_id']?.toString();
            _isLoading = false;
          });
          _startDualListener();
          return;
        } else {
          final msg = (data is Map && data['message'] != null)
              ? data['message'].toString()
              : 'Error al enviar orden al Posnet';
          setState(() {
            _errorMessage = msg;
            _isLoading = false;
          });
          return;
        }
      } else {
        String msg = 'Error en el servidor (${response.statusCode})';
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            if (data['message'] != null) {
              msg = data['message'].toString();
            } else if (data['errors'] != null && data['errors'] is Map) {
              final errMap = data['errors'] as Map;
              final firstKey = errMap.keys.firstOrNull;
              if (firstKey != null && errMap[firstKey] is List) {
                msg = (errMap[firstKey] as List).first.toString();
              }
            }
          }
        } catch (_) {}
        setState(() {
          _errorMessage = msg;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo conectar con el Posnet: $e';
        _isLoading = false;
      });
    }
  }

  void _startDualListener() {
    if (_externalReference == null || _externalReference!.isEmpty) return;

    _initPusher();

    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollStatus();
    });
  }

  Future<void> _initPusher() async {
    try {
      final apiUrl = await _getApiUrl();
      final uri = Uri.parse(apiUrl);
      final isSecure = apiUrl.startsWith('https');
      String pusherHost = uri.host;
      if (pusherHost.startsWith('api.')) {
        pusherHost = pusherHost.replaceFirst('api.', 'ws.');
      } else if (pusherHost.startsWith('api-')) {
        pusherHost = pusherHost.replaceFirst('api-', 'ws-');
      }

      final int pusherPort = isSecure ? 443 : 8080;

      final options = PusherChannelsOptions.fromHost(
        scheme: isSecure ? 'wss' : 'ws',
        host: pusherHost,
        port: pusherPort,
        key: 'kz786cdfeldnzispymxq',
      );

      _pusher = PusherChannelsClient.websocket(
        options: options,
        connectionErrorHandler: (error, trace, refresh) {},
      );

      final paymentChannel =
          _pusher!.publicChannel('pos.payments.$_externalReference');

      _pusher!.onConnectionEstablished.listen((_) {
        paymentChannel.subscribe();
      });

      paymentChannel.bind('PaymentApproved').listen(_onPusherEvent);
      paymentChannel.bind('App\\Events\\PaymentApprovedEvent').listen(_onPusherEvent);

      await _pusher!.connect();
    } catch (e) {
      debugPrint('Error conectando Reverb en PosnetWaitingDialog: $e');
    }
  }

  void _onPusherEvent(dynamic event) {
    if (_isResolved) return;
    try {
      if (event == null || event.data == null) return;
      final data = jsonDecode(event.data.toString());
      if (data is Map) {
        final status = data['status'];
        final extRef = data['external_reference']?.toString();
        if (status == 'approved' &&
            (extRef == null || extRef == _externalReference)) {
          final paymentId = data['mp_payment_id']?.toString() ??
              data['payment_id']?.toString() ??
              data['id']?.toString();
          _onPaymentApproved(paymentId);
        }
      }
    } catch (e) {
      debugPrint('Error parseando evento de Pusher: $e');
    }
  }

  Future<void> _pollStatus() async {
    if (_isResolved || _externalReference == null) return;

    try {
      final client = _getClient();
      final apiUrl = await _getApiUrl();

      final response = await client.get(
        Uri.parse('$apiUrl/pos/mp/status/$_externalReference'),
        headers: {'Accept': 'application/json'},
      );

      if (_isResolved || !mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['status'] == 'approved') {
          final paymentId = data['mp_payment_id']?.toString();
          _onPaymentApproved(paymentId);
        }
      }
    } catch (e) {
      debugPrint('Error durante sondeo de status Posnet: $e');
    }
  }

  void _onPaymentApproved(String? paymentId) async {
    if (_isResolved) return;
    _isResolved = true;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _disconnectPusher();

    _mpPaymentId = paymentId;

    try {
      AudioPlayer().play(AssetSource('beep.mp3')).catchError((_) {});
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isApproved = true;
      });
    }

    await Future.delayed(const Duration(milliseconds: 1000));

    if (mounted) {
      Navigator.of(context).pop({
        'status': 'approved',
        'mp_payment_id': _mpPaymentId,
        'mp_order_id': _paymentIntentId,
        'external_reference': _externalReference,
      });
    }
  }

  void _cancelOperation() {
    if (_isResolved) return;
    _isResolved = true;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _disconnectPusher();

    if (mounted) {
      Navigator.of(context).pop(null);
    }
  }

  void _disconnectPusher() {
    try {
      _pusher?.disconnect();
      _pusher = null;
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _disconnectPusher();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF009EE3).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      color: Color(0xFF009EE3),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Mercado Pago Point',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  if (!_isApproved && !_isLoading)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: _cancelOperation,
                      tooltip: 'Cancelar',
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Contenido
              if (_isLoading) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(color: Color(0xFF009EE3)),
                const SizedBox(height: 20),
                const Text(
                  'Enviando orden de cobro al Posnet...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 20),
              ] else if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                const Icon(Icons.error_outline_rounded,
                    color: Colors.red, size: 52),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.red),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Cerrar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF009EE3),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _createPointIntent,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ] else if (_isApproved) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF2E7D32),
                    size: 64,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '¡Pago Aprobado!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'ID Operación: ${_mpPaymentId ?? "Confirmado"}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 20),
              ] else ...[
                Text(
                  '\$${widget.amount.toCurrency()}',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF009EE3),
                  ),
                ),
                const SizedBox(height: 20),

                // Icono animado/spinner de espera de tarjeta
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.credit_card_rounded,
                    color: Color(0xFF009EE3),
                    size: 54,
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Esperando tarjeta en el Posnet...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Acerque, inserte o deslice la tarjeta en el dispositivo físico',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 14),

                if (_externalReference != null)
                  Text(
                    'Ref: $_externalReference',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                const SizedBox(height: 16),

                // Spinner sutil
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF009EE3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Sondeando dispositivo en tiempo real...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _cancelOperation,
                    child: const Text('Cancelar Operación'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  }
}
