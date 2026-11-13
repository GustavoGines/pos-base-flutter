import 'dart:async';
import 'dart:convert';
import 'package:dart_pusher_channels/dart_pusher_channels.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/core/utils/snack_bar_service.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';

typedef RemoteBarcodeCallback = void Function(String barcode);

class _RemoteScannerConsumer {
  final int id;
  final ModalRoute<dynamic>? route;
  final BuildContext Function() contextGetter;
  final RemoteBarcodeCallback onBarcodeScanned;
  final String? debugLabel;

  _RemoteScannerConsumer({
    required this.id,
    required this.route,
    required this.contextGetter,
    required this.onBarcodeScanned,
    this.debugLabel,
  });

  bool get isMounted {
    try {
      return contextGetter().mounted;
    } catch (_) {
      return false;
    }
  }
}

/// Bus centralizado de escaneo inalámbrico (App Android -> Desktop vía Reverb/Pusher).
///
/// Mantiene **una única conexión WebSocket** en Desktop para `pos.scans.<terminalId>`
/// y `pos.printers.<terminalId>`, despachando cada código recibido exclusivamente al
/// consumidor registrado cuya [ModalRoute] sea la ruta superior activa (`isCurrent`).
///
/// Si existe un consumidor registrado detrás de un modal bloqueante sin lector
/// (por ej. Checkout o PIN de Admin), no ejecuta ninguna acción en segundo plano
/// y notifica con un aviso anti-spam para evitar escaneos inadvertidos.
class RemoteScannerService extends ChangeNotifier {
  RemoteScannerService({
    String initialTerminalId = 'caja-1',
    bool autoConnect = true,
    Duration blockedWarningCooldown = const Duration(seconds: 3),
    DateTime Function()? clock,
    void Function(String barcode)? onBlockedScanHook,
  })  : _terminalId = _normalizeTerminalId(initialTerminalId),
        _autoConnect = autoConnect,
        _blockedWarningCooldown = blockedWarningCooldown,
        _clock = clock ?? DateTime.now,
        _onBlockedScanHook = onBlockedScanHook;

  final bool _autoConnect;
  final Duration _blockedWarningCooldown;
  final DateTime Function() _clock;
  final void Function(String barcode)? _onBlockedScanHook;

  String _terminalId;
  String? _connectedTerminalId;
  PusherChannelsClient? _pusher;
  int _connectEpoch = 0;
  bool _isConnecting = false;
  bool _disposed = false;

  int _nextConsumerId = 0;
  final List<_RemoteScannerConsumer> _consumers = [];
  DateTime? _lastBlockedWarningAt;

  final StreamController<int> _printLabelController =
      StreamController<int>.broadcast();

  String get terminalId => _terminalId;
  bool get isConnected => _pusher != null;
  int get registeredConsumersCount => _consumers.length;
  Stream<int> get onPrintLabelRequested => _printLabelController.stream;

  static String _normalizeTerminalId(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? 'caja-1' : trimmed;
  }

  /// Helper compartido para encontrar coincidencia exacta por EAN o código interno (PLU).
  static Product? findExactProductMatch(
    Iterable<Product> products,
    String rawQuery, {
    bool activeOnly = true,
    bool includeInternalCode = true,
  }) {
    final q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return null;

    Product? internalMatch;
    for (final p in products) {
      if (activeOnly && !p.active) continue;
      if ((p.barcode?.trim().toLowerCase() ?? '') == q) {
        return p;
      }
      if (includeInternalCode &&
          internalMatch == null &&
          p.internalCode.trim().toLowerCase() == q) {
        internalMatch = p;
      }
    }
    return internalMatch;
  }

  /// Actualiza el ID de terminal y reconecta si corresponde.
  void updateTerminalId(String rawTerminalId) {
    final nextId = _normalizeTerminalId(rawTerminalId);
    if (nextId == _terminalId) return;
    _terminalId = nextId;
    if (_pusher != null ||
        _isConnecting ||
        (_autoConnect && _consumers.isNotEmpty)) {
      unawaited(reconnect());
    }
  }

  Future<void> ensureConnected() async {
    if (_disposed || !_autoConnect || AppConfig.isMobile) return;
    if (_pusher != null && _connectedTerminalId == _terminalId) return;
    if (_isConnecting && _connectedTerminalId == _terminalId) return;
    await _connect();
  }

  Future<void> reconnect() async {
    _connectEpoch++;
    _connectedTerminalId = null;
    final oldClient = _pusher;
    _pusher = null;
    try {
      oldClient?.disconnect();
    } catch (_) {}
    await ensureConnected();
  }

  Future<void> _connect() async {
    final int epoch = ++_connectEpoch;
    final String targetTerminal = _terminalId;
    _isConnecting = true;
    _connectedTerminalId = targetTerminal;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed ||
          epoch != _connectEpoch ||
          AppConfig.isMobile ||
          prefs.getBool('disable_pusher') == true) {
        return;
      }

      final currentUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
      final uri = Uri.parse(currentUrl);

      final isSecure = currentUrl.startsWith('https');
      String pusherHost = uri.host;
      if (pusherHost.startsWith('api.')) {
        pusherHost = pusherHost.replaceFirst('api.', 'ws.');
      } else if (pusherHost.startsWith('api-')) {
        pusherHost = pusherHost.replaceFirst('api-', 'ws-');
      }

      // Cloudflare rutea WSS por 443; en red local directa usamos el puerto 8080 de Reverb.
      final int pusherPort = isSecure ? 443 : 8080;

      final options = PusherChannelsOptions.fromHost(
        scheme: isSecure ? 'wss' : 'ws',
        host: pusherHost,
        port: pusherPort,
        key: 'kz786cdfeldnzispymxq',
      );

      final client = PusherChannelsClient.websocket(
        options: options,
        connectionErrorHandler: (error, trace, refresh) {},
      );

      if (_disposed || epoch != _connectEpoch) {
        try {
          client.disconnect();
        } catch (_) {}
        return;
      }

      final prevClient = _pusher;
      _pusher = client;
      try {
        prevClient?.disconnect();
      } catch (_) {}

      final scanChannel = client.publicChannel('pos.scans.$targetTerminal');
      final printerChannel =
          client.publicChannel('pos.printers.$targetTerminal');

      client.onConnectionEstablished.listen((_) {
        if (_disposed || epoch != _connectEpoch) return;
        scanChannel.subscribe();
        printerChannel.subscribe();
      });

      scanChannel.bind('App\\Events\\MobileScanned').listen((event) {
        if (_disposed || epoch != _connectEpoch) return;
        try {
          if (event.data == null) return;
          final data = jsonDecode(event.data.toString());
          final barcode = data['barcode']?.toString();
          if (barcode != null && barcode.trim().isNotEmpty) {
            handleIncomingBarcode(barcode);
          }
        } catch (e) {
          debugPrint('Error parsing MobileScanned event: $e');
        }
      });

      printerChannel.bind('App\\Events\\PrintLabelRequested').listen((event) {
        if (_disposed || epoch != _connectEpoch) return;
        try {
          if (event.data == null) return;
          final data = jsonDecode(event.data.toString());
          final rawId = data['productId'];
          final productId =
              rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
          if (productId != null && !_printLabelController.isClosed) {
            _printLabelController.add(productId);
          }
        } catch (e) {
          debugPrint('Error parsing PrintLabelRequested event: $e');
        }
      });

      await client.connect();

      if (_disposed || epoch != _connectEpoch) {
        try {
          client.disconnect();
        } catch (_) {}
        if (identical(_pusher, client)) {
          _pusher = null;
        }
      }
    } catch (e) {
      debugPrint('Error conectando RemoteScannerService: $e');
    } finally {
      if (epoch == _connectEpoch) {
        _isConnecting = false;
      }
    }
  }

  /// Registra una pantalla o modal receptor de códigos de barras.
  /// Devuelve una función idempotente para desuscribirse al cerrar el widget.
  VoidCallback registerConsumer({
    required BuildContext context,
    ModalRoute<dynamic>? route,
    required RemoteBarcodeCallback onBarcodeScanned,
    String? debugLabel,
  }) {
    if (_disposed) return () {};

    final int id = ++_nextConsumerId;
    final resolvedRoute = route ?? ModalRoute.of(context);

    _consumers.add(
      _RemoteScannerConsumer(
        id: id,
        route: resolvedRoute,
        contextGetter: () => context,
        onBarcodeScanned: onBarcodeScanned,
        debugLabel: debugLabel,
      ),
    );

    unawaited(ensureConnected());

    bool removed = false;
    return () {
      if (removed) return;
      removed = true;
      _consumers.removeWhere((c) => c.id == id);
    };
  }

  /// Despacha un código recibido al consumidor visible superior (`route.isCurrent == true`).
  ///
  /// Retorna `true` si algún consumidor activo lo procesó; `false` si se ignoró
  /// (ya sea porque no hay pantallas con lector registradas o porque hay un modal bloqueante encima).
  bool handleIncomingBarcode(String rawBarcode) {
    if (_disposed) return false;
    final code = rawBarcode.trim();
    if (code.isEmpty) return false;

    _consumers.removeWhere((c) => !c.isMounted);

    for (int i = _consumers.length - 1; i >= 0; i--) {
      final consumer = _consumers[i];
      final route = consumer.route;
      final bool isRouteActive =
          route == null || (route.isActive && route.isCurrent);
      if (isRouteActive) {
        consumer.onBarcodeScanned(code);
        return true;
      }
    }

    // Hay una pantalla/diálogo con escáner debajo, pero tapado por un modal bloqueante
    // sin soporte de lector (por ej. CheckoutDialog, AdminPinDialog, Confirmación).
    if (_consumers.isNotEmpty) {
      final now = _clock();
      final canWarn = _lastBlockedWarningAt == null ||
          now.difference(_lastBlockedWarningAt!) >= _blockedWarningCooldown;
      if (canWarn) {
        _lastBlockedWarningAt = now;
        if (_onBlockedScanHook != null) {
          _onBlockedScanHook!(code);
        } else {
          final ctx =
              AppConfig.navigatorKey.currentContext ?? _firstMountedContext();
          if (ctx != null && ctx.mounted) {
            SnackBarService.warning(
              ctx,
              'Escaneo ignorado ($code): cerrá la ventana actual para usar el lector.',
            );
          }
        }
      }
    }

    return false;
  }

  BuildContext? _firstMountedContext() {
    for (int i = _consumers.length - 1; i >= 0; i--) {
      try {
        final ctx = _consumers[i].contextGetter();
        if (ctx.mounted) return ctx;
      } catch (_) {}
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _connectEpoch++;
    final client = _pusher;
    _pusher = null;
    try {
      client?.disconnect();
    } catch (_) {}
    _consumers.clear();
    _printLabelController.close();
    super.dispose();
  }
}

/// Wrapper liviano y seguro que suscribe un widget/diálogo al [RemoteScannerService]
/// usando su propia [ModalRoute] y lo desuscribe automáticamente en `dispose()`.
///
/// Es tolerante si [RemoteScannerService] no está en el árbol de Providers (ej. tests aislados).
class RemoteScannerListener extends StatefulWidget {
  final Widget child;
  final RemoteBarcodeCallback onBarcodeScanned;
  final bool enabled;
  final String? debugLabel;

  const RemoteScannerListener({
    super.key,
    required this.child,
    required this.onBarcodeScanned,
    this.enabled = true,
    this.debugLabel,
  });

  @override
  State<RemoteScannerListener> createState() => _RemoteScannerListenerState();
}

class _RemoteScannerListenerState extends State<RemoteScannerListener> {
  RemoteScannerService? _service;
  ModalRoute<dynamic>? _route;
  VoidCallback? _unregister;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = Provider.of<RemoteScannerService?>(context, listen: false);
    final route = ModalRoute.of(context);
    _syncRegistration(service, route);
  }

  @override
  void didUpdateWidget(covariant RemoteScannerListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.debugLabel != widget.debugLabel) {
      final service =
          Provider.of<RemoteScannerService?>(context, listen: false);
      final route = ModalRoute.of(context);
      _syncRegistration(service, route, forceRebind: true);
    }
  }

  void _syncRegistration(
    RemoteScannerService? service,
    ModalRoute<dynamic>? route, {
    bool forceRebind = false,
  }) {
    if (!widget.enabled || service == null) {
      _unregister?.call();
      _unregister = null;
      _service = service;
      _route = route;
      return;
    }

    if (!forceRebind &&
        _unregister != null &&
        identical(_service, service) &&
        identical(_route, route)) {
      return;
    }

    _unregister?.call();
    _service = service;
    _route = route;
    _unregister = service.registerConsumer(
      context: context,
      route: route,
      debugLabel: widget.debugLabel,
      onBarcodeScanned: (barcode) {
        if (!mounted || !widget.enabled) return;
        widget.onBarcodeScanned(barcode);
      },
    );
  }

  @override
  void dispose() {
    _unregister?.call();
    _unregister = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
