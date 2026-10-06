import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/cart_item.dart';

class MercadoPagoQrDialog extends StatefulWidget {
  final double amount;
  final String terminalId;
  final List<CartItem>? cartItems;
  final String? externalReference;
  final ApiClient? client;
  final String? baseUrl;

  const MercadoPagoQrDialog({
    super.key,
    required this.amount,
    required this.terminalId,
    this.cartItems,
    this.externalReference,
    this.client,
    this.baseUrl,
  });

  @override
  State<MercadoPagoQrDialog> createState() => _MercadoPagoQrDialogState();
}

class _MercadoPagoQrDialogState extends State<MercadoPagoQrDialog> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _qrData;
  String? _externalReference;
  String? _orderId;
  bool _isApproved = false;
  String? _mpPaymentId;

  Timer? _pollingTimer;
  PusherChannelsClient? _pusher;
  bool _isResolved = false;

  @override
  void initState() {
    super.initState();
    _externalReference = widget.externalReference;
    _createOrder();
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

  Future<void> _createOrder() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final client = _getClient();
      final apiUrl = await _getApiUrl();

      final List<Map<String, dynamic>> itemsPayload;
      if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
        itemsPayload = widget.cartItems!.map((ci) {
          final sku = ci.product.barcode ??
              (ci.product.internalCode.isNotEmpty
                  ? ci.product.internalCode
                  : 'PROD-${ci.product.id}');
          return {
            'sku': sku,
            'title': ci.product.name,
            'unit_price': ci.unitPrice,
            'quantity': ci.quantity,
          };
        }).toList();
      } else {
        itemsPayload = [
          {
            'sku': 'POS-ITEM',
            'title': 'Cobro POS Mostrador',
            'unit_price': widget.amount,
            'quantity': 1,
          }
        ];
      }

      final body = <String, dynamic>{
        'pos_id': widget.terminalId.isNotEmpty ? widget.terminalId : 'caja-1',
        'amount': widget.amount,
        'items': itemsPayload,
        if (_externalReference != null && _externalReference!.isNotEmpty)
          'external_reference': _externalReference,
      };

      final response = await client.post(
        Uri.parse('$apiUrl/pos/mp/create-order'),
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
            _qrData = data['qr_data']?.toString();
            _externalReference = data['external_reference']?.toString();
            _orderId = data['order_id']?.toString();
            _isLoading = false;
          });
          _startDualListener();
          return;
        } else {
          final msg = (data is Map && data['message'] != null)
              ? data['message'].toString()
              : 'Error al generar la orden de Mercado Pago';
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
          if (data is Map && data['message'] != null) {
            msg = data['message'].toString();
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
        _errorMessage = 'No se pudo conectar con Mercado Pago: $e';
        _isLoading = false;
      });
    }
  }

  void _startDualListener() {
    if (_externalReference == null || _externalReference!.isEmpty) return;

    // 1. WebSocket Listener (Reverb / Pusher)
    _initPusher();

    // 2. Short-Polling Fallback (cada 2 segundos)
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
      final terminalId =
          widget.terminalId.isNotEmpty ? widget.terminalId : 'caja-1';
      final terminalChannel = _pusher!.publicChannel('pos.terminal.$terminalId');

      _pusher!.onConnectionEstablished.listen((_) {
        paymentChannel.subscribe();
        terminalChannel.subscribe();
      });

      paymentChannel.bind('PaymentApproved').listen(_onPusherEvent);
      paymentChannel.bind('App\\Events\\PaymentApprovedEvent').listen(_onPusherEvent);

      terminalChannel.bind('PaymentApproved').listen(_onPusherEvent);
      terminalChannel.bind('App\\Events\\PaymentApprovedEvent').listen(_onPusherEvent);

      await _pusher!.connect();
    } catch (e) {
      debugPrint('Error conectando Reverb en MercadoPagoQrDialog: $e');
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
      debugPrint('Error durante sondeo de status MP: $e');
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
        'mp_order_id': _orderId,
        'external_reference': _externalReference,
      });
    }
  }

  Future<void> _cancelOrder() async {
    if (_isResolved) return;
    _isResolved = true;

    _pollingTimer?.cancel();
    _pollingTimer = null;
    _disconnectPusher();

    if (_externalReference != null && _externalReference!.isNotEmpty) {
      try {
        final client = _getClient();
        final apiUrl = await _getApiUrl();
        await client.post(
          Uri.parse('$apiUrl/pos/mp/cancel-order'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'external_reference': _externalReference}),
        );
      } catch (e) {
        debugPrint('Error cancelando orden de MP: $e');
      }
    }

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
          width: 420,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // ── Header con branding Mercado Pago
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF009EE3).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: Color(0xFF009EE3),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Mercado Pago QR',
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
                      onPressed: _cancelOrder,
                      tooltip: 'Cancelar',
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Contenido según Estado
              if (_isLoading) ...[
                const SizedBox(height: 30),
                const CircularProgressIndicator(color: Color(0xFF009EE3)),
                const SizedBox(height: 20),
                const Text(
                  'Generando orden de cobro en Mercado Pago...',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 30),
              ] else if (_errorMessage != null) ...[
                const SizedBox(height: 16),
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
                      onPressed: _createOrder,
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
                // Estado Waiting: Monto + QR + Ref
                Text(
                  '\$${widget.amount.toCurrency()}',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF009EE3),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Escaneá con Mercado Pago o cualquier billetera interoperable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 16),

                if (_qrData != null && _qrData!.isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(
                      data: _qrData!,
                      version: QrVersions.auto,
                      size: 210,
                      backgroundColor: Colors.white,
                    ),
                  ),
                const SizedBox(height: 14),

                if (_externalReference != null)
                  Text(
                    'Ref: $_externalReference',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                const SizedBox(height: 14),

                // Indicador de sondeo / espera
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
                        'Esperando confirmación del pago...',
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
                const SizedBox(height: 20),

                // Botón cancelar orden
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
                    onPressed: _cancelOrder,
                    child: const Text('Cancelar Cobro QR'),
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
