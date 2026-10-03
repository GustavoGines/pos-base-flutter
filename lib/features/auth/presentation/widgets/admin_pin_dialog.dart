import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/utils/snack_bar_service.dart';

class AdminPinDialog extends StatefulWidget {
  final String actionDescription;

  const AdminPinDialog({super.key, required this.actionDescription});

  /// Intercepta proactivamente una acción sensible:
  /// 1. Si el usuario es Administrador o tiene el permiso: ejecuta [onAuthorized] de inmediato.
  /// 2. Si carece de permiso: despliega AdminPinDialog.
  /// 3. Si el supervisor valida su PIN: envuelve la llamada a [onAuthorized] dentro de
  ///    [ApiClient.withAdminPin], transmitiendo el header X-Admin-Pin al backend.
  static Future<bool> protectAction(
    BuildContext context, {
    required String action,
    required String permissionKey,
    required Future<void> Function() onAuthorized,
  }) async {
    AuthProvider? auth;
    ApiClient? client;
    try {
      auth = context.read<AuthProvider>();
    } catch (_) {}
    try {
      client = context.read<ApiClient>();
    } catch (_) {}

    if (auth == null || auth.isAdmin || auth.hasPermission(permissionKey)) {
      await onAuthorized();
      return true;
    }

    

    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AdminPinDialog(actionDescription: action),
    );

    if (pin == null || pin.isEmpty) {
      return false; // Operación cancelada por el usuario
    }

    if (client != null) {
      await client.withAdminPin(pin, onAuthorized);
    } else {
      await onAuthorized();
    }
    return true;
  }

  /// Helper estático para interceptar acciones.
  /// Retorna true si:
  ///   1. El usuario ya es Admin, o
  ///   2. El cajero tiene el permiso [permissionKey] en su array, o
  ///   3. El cajero introdujo correctamente el PIN del Admin.
  static Future<bool> verify(
    BuildContext context, {
    required String action,
    String? permissionKey,
  }) async {
    AuthProvider? auth;
    try {
      auth = context.read<AuthProvider>();
    } catch (_) {}

    // Si no hay provider de autenticación (ej: test unitario aislado), permitir
    if (auth == null) return true;

    // Admins pasan directo siempre
    if (auth.isAdmin) return true;

    // Cajero con permiso específico también pasa directo
    if (permissionKey != null && auth.hasPermission(permissionKey)) return true;

    // Si ya desbloqueó la pantalla con un PIN, pasa directo
    

    // Sin permiso -> pedir PIN de Admin
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AdminPinDialog(actionDescription: action),
    );

    return result != null;
  }

  /// Helper estático para interceptar acciones que necesitan inyectar el PIN en una nueva ruta.
  /// Retorna:
  ///   - 'ALREADY_AUTHORIZED' si el usuario ya es Admin o tiene el permiso.
  ///   - El PIN ingresado si el usuario introdujo correctamente el PIN del Admin.
  ///   - null si se canceló.
  static Future<String?> verifyAndGetPin(
    BuildContext context, {
    required String action,
    String? permissionKey,
  }) async {
    AuthProvider? auth;
    try {
      auth = context.read<AuthProvider>();
    } catch (_) {}

    // Si no hay provider de autenticación (ej: test unitario aislado), permitir
    if (auth == null) return 'ALREADY_AUTHORIZED';

    // Admins pasan directo siempre
    if (auth.isAdmin) return 'ALREADY_AUTHORIZED';

    // Cajero con permiso específico también pasa directo
    if (permissionKey != null && auth.hasPermission(permissionKey)) return 'ALREADY_AUTHORIZED';

    // Si ya desbloqueó la pantalla con un PIN, lo reutilizamos
    

    // Sin permiso -> pedir PIN de Admin y retornarlo
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AdminPinDialog(actionDescription: action),
    );

    return result;
  }

  @override
  State<AdminPinDialog> createState() => _AdminPinDialogState();
}

class _AdminPinDialogState extends State<AdminPinDialog> {
  String _pin = '';
  static const int _pinLength = 4;
  bool _isLoading = false;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _focusNode.dispose();
    super.dispose();
  }

  void _onKeypadTap(String value) {
    if (_isLoading) return;
    
    if (value == 'clr') {
      setState(() => _pin = '');
    } else if (value == 'del') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    } else {
      if (_pin.length < _pinLength) {
        setState(() => _pin += value);
        if (_pin.length == _pinLength) {
          _verifyAdminPin();
        }
      }
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;
    final ch = event.character;

    bool handled = true;

    // Números (0-9) y Numpad (0-9)
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _onKeypadTap(ch);
    } else if (key == LogicalKeyboardKey.numpad0 || key == LogicalKeyboardKey.digit0) {
      _onKeypadTap('0');
    } else if (key == LogicalKeyboardKey.numpad1 || key == LogicalKeyboardKey.digit1) {
      _onKeypadTap('1');
    } else if (key == LogicalKeyboardKey.numpad2 || key == LogicalKeyboardKey.digit2) {
      _onKeypadTap('2');
    } else if (key == LogicalKeyboardKey.numpad3 || key == LogicalKeyboardKey.digit3) {
      _onKeypadTap('3');
    } else if (key == LogicalKeyboardKey.numpad4 || key == LogicalKeyboardKey.digit4) {
      _onKeypadTap('4');
    } else if (key == LogicalKeyboardKey.numpad5 || key == LogicalKeyboardKey.digit5) {
      _onKeypadTap('5');
    } else if (key == LogicalKeyboardKey.numpad6 || key == LogicalKeyboardKey.digit6) {
      _onKeypadTap('6');
    } else if (key == LogicalKeyboardKey.numpad7 || key == LogicalKeyboardKey.digit7) {
      _onKeypadTap('7');
    } else if (key == LogicalKeyboardKey.numpad8 || key == LogicalKeyboardKey.digit8) {
      _onKeypadTap('8');
    } else if (key == LogicalKeyboardKey.numpad9 || key == LogicalKeyboardKey.digit9) {
      _onKeypadTap('9');
    }
    // Backspace
    else if (key == LogicalKeyboardKey.backspace) {
      _onKeypadTap('del');
    }
    // Delete o Clear
    else if (key == LogicalKeyboardKey.delete) {
      _onKeypadTap('clr');
    }
    // Escape: si hay PIN ingresado lo borra; si está vacío cierra el modal
    else if (key == LogicalKeyboardKey.escape) {
      if (_pin.isNotEmpty) {
        _onKeypadTap('clr');
      } else {
        Navigator.of(context).pop(null);
      }
    } else {
      handled = false;
    }

    return handled;
  }

  Future<void> _verifyAdminPin() async {
    setState(() => _isLoading = true);

    final provider = context.read<AuthProvider>();

    // ── IMPORTANTE: Usar authorizePin, NO verifyPin ──────────────────────────
    // verifyPin emite un session_token nuevo e invalida la sesión del admin
    // en su terminal principal. authorizePin solo valida el PIN sin tocar tokens.
    final adminUser = await provider.authorizePin(_pin);

    bool isAuthorized = false;

    if (adminUser != null) {
      final role = adminUser['role'] as String? ?? '';
      if (role == 'admin') {
        isAuthorized = true;
      } else {
        if (mounted) {
          SnackBarService.error(context, 'El PIN introducido no pertenece a un Administrador.');
        }
      }
    } else {
      if (mounted) {
        final errorMsg = provider.lastPinError ?? 'PIN incorrecto o error de conexión.';
        SnackBarService.error(context, errorMsg);
      }
    }

    if (mounted) {
      final String verifiedPin = _pin;
      setState(() {
        _isLoading = false;
        _pin = '';
      });
      _focusNode.requestFocus();

      if (isAuthorized) {
          try {
            context.read<ApiClient>().markPinAsVerified(verifiedPin);
          } catch (_) {}
          Navigator.of(context).pop(verifiedPin);
        }
    }
  }

  Widget _buildKey(String value, {IconData? icon}) {
    return Material(
      color: Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _onKeypadTap(value),
        child: Container(
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, color: Colors.blueGrey, size: 24)
              : Text(
                  value,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_rounded, size: 44, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text('Acceso Restringido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                'Ingresar PIN de Administrador para:\n${widget.actionDescription}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 16,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(_pinLength, (index) {
                          final isActive = index < _pin.length;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isActive ? Colors.redAccent : Colors.grey.shade200,
                            ),
                          );
                        }),
                      ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 240,
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    for (var i = 1; i <= 9; i++) _buildKey(i.toString()),
                    _buildKey('clr', icon: Icons.clear_all),
                    _buildKey('0'),
                    _buildKey('del', icon: Icons.backspace_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
