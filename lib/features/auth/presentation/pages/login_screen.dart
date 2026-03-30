import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../../../../core/utils/snack_bar_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _pin = '';
  String? _errorDetail;
  static const int _pinLength = 4;

  // ── FocusNode dedicado al listener del teclado físico ────────────
  late final FocusNode _keyboardFocus;

  @override
  void initState() {
    super.initState();
    _keyboardFocus = FocusNode(debugLabel: 'PinKeyboard');

    // Bulletproof #2: Esperar que el primer frame esté completamente
    // renderizado antes de pedir el foco. En Windows, autofocus puede
    // ser silenciosamente ignorado si la ventana aún no tiene el foco
    // del SO en el primer build tick.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────
  // Handler del teclado físico (API moderna: onKeyEvent)
  // Mapea: fila superior de números + Numpad lateral + Backspace +
  //        Escape + Enter/NumpadEnter
  // ─────────────────────────────────────────────────────────────────
  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    // Solo procesamos KeyDownEvent — evita doble disparo (down + up + repeat)
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // ── Dígitos: fila superior (digit0-9) + Numpad (numpad0-9) ──────
    // event.character es la forma más robusta: captura ambas fuentes
    // y respeta el layout del teclado del sistema operativo.
    final char = event.character;
    if (char != null && RegExp(r'^\d$').hasMatch(char)) {
      _onKeypadTap(char);
      return KeyEventResult.handled;
    }

    // ── Borrar último dígito: Backspace ──────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _onKeypadTap('del');
      return KeyEventResult.handled;
    }

    // ── Limpiar todo: Escape ──────────────────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _onKeypadTap('clr');
      return KeyEventResult.handled;
    }

    // ── Submit: Enter o Numpad Enter ──────────────────────────────────
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_pin.length == _pinLength) _submitPin();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // ─────────────────────────────────────────────────────────────────
  // Fuente única de verdad para la lógica del PIN.
  // Llamado tanto por el teclado físico como por los botones táctiles.
  // ─────────────────────────────────────────────────────────────────
  void _onKeypadTap(String value) {
    // Ignorar entrada mientras se procesa un login (evita doble submit)
    if (context.read<AuthProvider>().isLoading) return;

    if (value == 'clr') {
      setState(() {
        _pin = '';
        _errorDetail = null;
      });
    } else if (value == 'del') {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    } else {
      if (_pin.length < _pinLength) {
        setState(() => _pin += value);
        if (_pin.length == _pinLength) _submitPin();
      }
    }
  }

  bool _isSubmitting = false;

  Future<void> _submitPin() async {
    if (_isSubmitting) return;
    
    setState(() => _isSubmitting = true);
    final provider = context.read<AuthProvider>();
    final success = await provider.verifyPin(_pin);
    
    if (mounted) {
      if (success) {
        // Encolamos la navegación al final del frame para que el Navigator 
        // no colapse ni arroje !_debugLocked si hay builds en curso o si 
        // el LicenseGuard recién reconstruyó la vista.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            SnackBarService.success(context, '¡Bienvenido, ${provider.currentUser?['name']}!');
            Navigator.of(context).pushReplacementNamed('/home');
          }
        });
      } else {
        setState(() => _isSubmitting = false);
        final errorMsg = provider.errorMessage ?? 'Error desconocido';
        SnackBarService.error(context, errorMsg);
        setState(() {
          _pin = '';
          _errorDetail = errorMsg;
        });
        // Re-solicitar foco post-error para que el teclado siga activo
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _keyboardFocus.requestFocus();
        });
      }
    }
  }

  Future<void> _showServerConfigDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUrl = prefs.getString('pos_api') ?? 'http://127.0.0.1:8000/api';
    if (!mounted) return;
    final ctrl = TextEditingController(text: currentUrl);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dns_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Red y Servidor', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Apunta este frontend a la computadora principal (Servidor).\n'
              'Ejemplo: http://192.168.1.50:8000/api',
              style: TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'URL de la API',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final newUrl = ctrl.text.trim();
              if (newUrl.isNotEmpty) {
                await prefs.setString('pos_api', newUrl);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                SnackBarService.success(context,
                    'Configuración guardada.\nReiniciá la app para aplicar.');
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade800),
          ),
        ],
      ),
    );

    // Recapturar foco al cerrar el diálogo de configuración
    if (mounted) _keyboardFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuthProvider>();

    // ── ARQUITECTURA BULLETPROOF ──────────────────────────────────────
    // #1 autofocus: true  → pide foco al montar el widget
    // #2 addPostFrameCallback (initState) → garantiza foco en primer frame
    // #3 GestureDetector (raíz) → re-captura si el usuario toca zona vacía
    return GestureDetector(
      // Bulletproof #3: cualquier tap en zona sin widget → vuelve el foco
      onTap: () => _keyboardFocus.requestFocus(),
      child: Focus(
        focusNode: _keyboardFocus,
        autofocus: true, // Bulletproof #1
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: const Color(0xFF1E2D45),
          body: Stack(
            children: [
              // ── Botón de configuración de red ─────────────────────
              Positioned(
                top: 24,
                right: 24,
                child: IconButton(
                  icon: const Icon(Icons.settings_ethernet, color: Colors.white54, size: 28),
                  tooltip: 'Configurar Servidor',
                  onPressed: _showServerConfigDialog,
                ),
              ),

              Center(
                child: SingleChildScrollView(
                  child: Container(
                    width: 400,
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.point_of_sale_rounded, size: 64, color: Color(0xFF3B82F6)),
                        const SizedBox(height: 16),
                        const Text('Sistema POS',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 8),
                        const Text('Ingreso al sistema',
                            style: TextStyle(fontSize: 14, color: Colors.black54)),
                        const SizedBox(height: 32),

                        // ── Indicadores de PIN ────────────────────────
                        SizedBox(
                          height: 24,
                          child: provider.isLoading
                              ? const SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 3))
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(_pinLength, (index) {
                                    final isActive = index < _pin.length;
                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 8),
                                      width: 24, height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isActive ? const Color(0xFF3B82F6) : Colors.grey.shade200,
                                        border: Border.all(
                                          color: isActive ? const Color(0xFF3B82F6) : Colors.grey.shade400,
                                          width: 2,
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                        ),
                        const SizedBox(height: 16),

                        // ── Mensaje de error ──────────────────────────
                        if (_errorDetail != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              border: Border.all(color: Colors.red.shade200),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorDetail!,
                              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 24),

                        // ── Teclado Numérico Visual ───────────────────
                        // Convive con el teclado físico: ambos llaman
                        // a _onKeypadTap() — single source of truth.
                        SizedBox(
                          width: 280,
                          child: GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                            children: [
                              for (var i = 1; i <= 9; i++) _buildKey(i.toString()),
                              _buildKey('clr', icon: Icons.clear_all),
                              _buildKey('0'),
                              _buildKey('del', icon: Icons.backspace_outlined),
                            ],
                          ),
                        ),

                        // ── Hint visual de teclado físico ────────────
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.keyboard, size: 14, color: Colors.grey.shade400),
                            const SizedBox(width: 4),
                            Text(
                              'También podés usar el teclado físico',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKey(String value, {IconData? icon}) {
    return Material(
      color: Colors.grey.shade100,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        // Los botones táctiles no necesitan requestFocus() porque el
        // GestureDetector raíz ya lo maneja globalmente.
        onTap: () => _onKeypadTap(value),
        child: Container(
          alignment: Alignment.center,
          child: icon != null
              ? Icon(icon, color: Colors.black87, size: 28)
              : Text(
                  value,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
        ),
      ),
    );
  }
}
