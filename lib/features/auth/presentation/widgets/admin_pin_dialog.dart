import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';

class AdminPinDialog extends StatefulWidget {
  final String actionDescription;

  const AdminPinDialog({Key? key, required this.actionDescription}) : super(key: key);

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
    final auth = context.read<AuthProvider>();

    // Admins pasan directo siempre
    if (auth.isAdmin) return true;

    // Cajero con permiso específico también pasa directo
    if (permissionKey != null && auth.hasPermission(permissionKey)) return true;

    // Sin permiso → pedir PIN de Admin
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AdminPinDialog(actionDescription: action),
    );

    return result ?? false;
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
    else if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.escape) {
      _onKeypadTap('clr');
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
        SnackBarService.error(context, 'PIN incorrecto o error de conexión.');
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _pin = '';
      });
      _focusNode.requestFocus();

      if (isAuthorized) {
        Navigator.of(context).pop(true);
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
        padding: const EdgeInsets.all(24),
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_rounded, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text('Acceso Restringido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Ingresar PIN de Administrador para:\n${widget.actionDescription}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
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
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? Colors.redAccent : Colors.grey.shade200,
                          ),
                        );
                      }),
                    ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 240,
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
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
    );
  }
}
