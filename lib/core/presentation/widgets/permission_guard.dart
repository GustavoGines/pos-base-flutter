import '../../../../core/network/api_client.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../features/auth/presentation/widgets/admin_pin_dialog.dart';

/// Proveedor heredado de PIN de administrador para pantallas desbloqueadas por excepción.
class InheritedAdminPin extends InheritedWidget {
  final String? adminPin;

  const InheritedAdminPin({
    super.key,
    required this.adminPin,
    required super.child,
  });

  static String? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<InheritedAdminPin>()?.adminPin;
  }

  @override
  bool updateShouldNotify(InheritedAdminPin oldWidget) => adminPin != oldWidget.adminPin;
}

class PermissionGuard extends StatefulWidget {
  final String permissionKey;
  final Widget child;

  const PermissionGuard({
    super.key,
    required this.permissionKey,
    required this.child,
  });

  @override
  State<PermissionGuard> createState() => _PermissionGuardState();
}

class _PermissionGuardState extends State<PermissionGuard> {
  ApiClient? _apiClient;
  String? _temporaryUnlockedPin;
  bool _hasInjectedPin = false;
  bool _hasPrompted = false;
  Object? _lastUserIdentity;

  static String? _extractInjectedPin(BuildContext context) {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    if (rawArgs is Map && rawArgs['unlocked_pin'] is String) {
      final pin = (rawArgs['unlocked_pin'] as String).trim();
      return pin.isNotEmpty ? pin : null;
    }
    return null;
  }

  static bool _isAuthActive(AuthProvider auth) {
    try {
      return auth.isAuthenticated;
    } catch (_) {
      try {
        return auth.currentUser != null;
      } catch (_) {
        return true;
      }
    }
  }

  void _injectScreenPin(String pin) {
    if (pin.trim().isEmpty) return;
    try {
      _apiClient ??= context.read<ApiClient>();
    } catch (_) {}
    _hasInjectedPin = true;
    _apiClient?.setGlobalEphemeralPin(pin, this);
  }

  void _cleanupScreenPin() {
    if (_hasInjectedPin) {
      _apiClient?.setGlobalEphemeralPin(null, this);
      _hasInjectedPin = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndAutoPrompt();
    });
  }

  void _checkAndAutoPrompt() async {
    if (!mounted) return;
    try {
      _apiClient ??= context.read<ApiClient>();
    } catch (_) {}
    final auth = context.read<AuthProvider>();
    if (!_isAuthActive(auth)) return;
    
    final injectedPin = _extractInjectedPin(context);

    if (auth.isAdmin || auth.hasPermission(widget.permissionKey) || _temporaryUnlockedPin != null || injectedPin != null) {
      final validPin = _temporaryUnlockedPin ?? injectedPin;
      if (validPin != null && validPin.isNotEmpty) {
        _injectScreenPin(validPin);
      }

      return;
    }

    if (_hasPrompted) return;
    _hasPrompted = true;

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const AdminPinDialog(
        actionDescription: 'Acceso temporal a pantalla protegida',
      ),
    );

    if (pin != null && pin.isNotEmpty && mounted) {
      _injectScreenPin(pin);
      setState(() {
        _temporaryUnlockedPin = pin;
      });
    } else if (mounted) {
      // Si el usuario cancela el diálogo, lo devolvemos a la pantalla anterior
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _apiClient ??= context.read<ApiClient>();
    } catch (_) {}
  }

  @override
  void dispose() {
    _cleanupScreenPin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      _apiClient ??= context.read<ApiClient>();
    } catch (_) {}

    final auth = context.watch<AuthProvider>();

    // Si la sesión no está activa (logout), invalidar el PIN temporal y bloquear pantalla
    if (!_isAuthActive(auth)) {
      if (_temporaryUnlockedPin != null || _hasInjectedPin) {
        _temporaryUnlockedPin = null;
        _cleanupScreenPin();
      }
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Detectar cambio de usuario autenticado
    Object? currentIdentity;
    try {
      currentIdentity = auth.currentUser?['id'] ?? auth.currentUser;
    } catch (_) {}

    if (_lastUserIdentity != null && currentIdentity != null && _lastUserIdentity != currentIdentity) {
      _temporaryUnlockedPin = null;
      _cleanupScreenPin();
    }
    _lastUserIdentity = currentIdentity;

    // Buscar si el PIN fue inyectado de forma segura desde la pantalla anterior (ej. menú de usuario)
    final injectedPin = _extractInjectedPin(context);

    // 1. Acceso permitido por perfil o previamente desbloqueado con PIN en esta sesión de pantalla
    if (auth.isAdmin || auth.hasPermission(widget.permissionKey) || _temporaryUnlockedPin != null || injectedPin != null) {
      final validPin = _temporaryUnlockedPin ?? injectedPin;
      if (validPin != null && validPin.isNotEmpty) {
        _injectScreenPin(validPin);
      }

      return InheritedAdminPin(
        adminPin: _temporaryUnlockedPin ?? injectedPin,
        child: widget.child,
      );
    }

    // 2. Pantalla de carga mientras se muestra el diálogo
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
