import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../widgets/rescue_pin_change_dialog.dart';
import '../../../../core/utils/snack_bar_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../cash_register/presentation/providers/cash_register_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../updater/data/services/update_service.dart';
import '../../../updater/presentation/widgets/update_dialog.dart';
import '../../../updater/data/models/update_info.dart';
import '../../../updater/data/services/mobile_update_service.dart';
import '../../../updater/presentation/widgets/mobile_update_dialog.dart';
import '../../../../core/config/app_config.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _pin = '';
  String? _errorDetail;
  static const int _pinLength = 4;

  // ── FocusNode dedicado al listener del teclado físico ────────────
  late final FocusNode _keyboardFocus;
  
  UpdateInfo? _frontendUpdate;
  UpdateInfo? _backendUpdate;
  String _appVersion = '';
  bool _updateCheckCompleted = false;

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
      _checkForUpdates(); // Chequeo pasivo OTA
    });
  }

  Future<void> _checkForUpdates() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _appVersion = packageInfo.version);
    }

    try {
      final isMobile = AppConfig.isMobile;

      if (isMobile) {
        final update = await MobileUpdateService.checkForUpdate();
        if (mounted) {
          setState(() {
            _frontendUpdate = update;
            _backendUpdate = null;
            _updateCheckCompleted = true;
          });
          
          if (update != null && update.isCritical) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => MobileUpdateDialog(updateInfo: update),
            );
          }
        }
        return;
      }

      final result = await UpdateService().checkUpdate(throwErrors: true);
      // ✨ Siempre: alimentar el notificador global para el badge de la AppBar ✨
      UpdateService.updateNotifier.value = result;

      // Si el usuario sigue pacientemente en la pantalla de login:
      if (mounted) {
        // Actualización crítica del frontend → diálogo bloqueante
        if (result.frontendUpdate != null && result.frontendUpdate!.isCritical) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => UpdateDialog(updateInfo: result.frontendUpdate!),
          );
          return;
        }

        // Actualizaciones no críticas → badges en pantalla de login
        setState(() {
          _frontendUpdate = result.frontendUpdate;
          _backendUpdate = result.backendUpdate;
          _updateCheckCompleted = true;
        });
      } else {
        // El usuario entró rápido y el login ya se destruyó → popup global
        final globalContext = AppConfig.navigatorKey.currentContext;
        if (globalContext != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (result.frontendUpdate != null) {
              showDialog(
                context: globalContext,
                barrierDismissible: !result.frontendUpdate!.isCritical,
                builder: (_) => UpdateDialog(updateInfo: result.frontendUpdate!),
              );
            } else if (result.backendUpdate != null) {
              showDialog(
                context: globalContext,
                barrierDismissible: !result.backendUpdate!.isCritical,
                builder: (_) => UpdateDialog(updateInfo: result.backendUpdate!),
              );
            }
          });
        }
      }
    } catch (e) {
      // Fallo de red u otro error silencioso: no mostramos 'AL DÍA'
    }
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
        // [Bugfix] Evitar flashes visuales de "Pantalla Bloqueo" y "Turno de caja"
        // si la app arrancó sin red y se reconectó justo en este momento.
        // Forzamos la actualización del estado global ANTES de navegar al home.
        final settingsProv = context.read<SettingsProvider>();
        final cashProv = context.read<CashRegisterProvider>();
        
        await settingsProv.loadSettings(isSilent: true);
        
        final assignedId = settingsProv.assignedRegisterId;
        debugPrint('=== LOGIN: Verificando turno activo (registerId: ${assignedId > 0 ? assignedId : "null (fallback a Caja Principal)"}) ===');
        await cashProv.checkCurrentShift(registerId: assignedId > 0 ? assignedId : null);
        debugPrint('=== LOGIN: Turno detectado: ${cashProv.currentShift != null ? "ID:${cashProv.currentShift!.id} (${cashProv.currentShift!.status})" : "NINGUNO"} ===');


        // ── PROTOCOLO DE RESCATE: forzar cambio de PIN antes de entrar ────
        if (provider.requiresPinChange && mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const RescuePinChangeDialog(),
          );
        }
        // ─────────────────────────────────────────────────────────────────

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
    final currentUrl = prefs.getString('pos_api') ?? 'http://127.0.0.1/Sistema_POS/pos-backend/public/api';
    
    // Mostrar la URL tal cual, sin intentar extraer solo la IP con regex frágiles
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
              'Ingresa la URL o IP completa de la API:',
              style: TextStyle(color: Colors.blueGrey, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'URL del Servidor',
                prefixIcon: const Icon(Icons.wifi),
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
              String newUrl = ctrl.text.trim();
              if (newUrl.isNotEmpty) {
                // --- AUTO-FORMATO UX ---
                if (!newUrl.startsWith('http')) {
                  if (!newUrl.contains('/')) {
                    final isIp = RegExp(r'^([0-9]{1,3}\.){3}[0-9]{1,3}$').hasMatch(newUrl) || newUrl == 'localhost';
                    if (isIp) {
                      newUrl = 'http://$newUrl/Sistema_POS/pos-backend/public/api';
                    } else {
                      newUrl = 'https://$newUrl/pos-backend/public/api';
                    }
                  } else {
                    newUrl = 'http://$newUrl';
                  }
                }
                
                await prefs.setString('pos_api', newUrl);
                // Asegurar que actualizamos ambas para no romper el Auto-Fallback
                await prefs.setString('pos_api_local', newUrl);
                
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
// Remove this Positioned block entirely from here, it will be placed at the end of the Stack

              SafeArea(
                child: Center(
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
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Column(
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
                        const SizedBox(height: 16),
                        // Botón de configuración de servidor visible dentro del panel
                        IconButton(
                          icon: const Icon(Icons.settings_ethernet, color: Colors.blueGrey, size: 28),
                          tooltip: 'Configurar Servidor',
                          onPressed: _showServerConfigDialog,
                        ),
                      ],
                    ), // Cierre de la Column
                    if (_appVersion.isNotEmpty)
                      Positioned(
                        top: -30,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'v$_appVersion',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                  ),
                                  if (_updateCheckCompleted && _frontendUpdate == null && _backendUpdate == null) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.cloud_done_rounded, size: 14, color: Color(0xFF10B981)),
                                    const SizedBox(width: 2),
                                    const Text(
                                      'AL DÍA',
                                      style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ],
                              ),
                          ),
                        ),
                      ),
                  ],
                ), // Cierre del Stack
              ),
                ),
              ),
              ), // Cierre de SafeArea
              Positioned(
                top: 24,
                right: 24,
                child: SafeArea(
                  child: Row(
                    children: [
                      // Badge de update de Frontend (App) - Solo en Escritorio
                    if (_frontendUpdate != null && (!AppConfig.isMobile))
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF673AB7),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (_) => UpdateDialog(
                              updateInfo: _frontendUpdate!,
                              isFullSystemUpdate: _backendUpdate != null,
                            ),
                          );
                          if (result == true) {
                            setState(() {
                              _frontendUpdate = null;
                              if (_backendUpdate == null) _updateCheckCompleted = true;
                            });
                            _checkForUpdates();
                          }
                        },
                        icon: const Icon(Icons.monitor, size: 18),
                        label: Text(
                          _backendUpdate != null ? 'Actualiz. Integral' : 'Actualiz. App',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (_frontendUpdate != null && _backendUpdate != null && (!AppConfig.isMobile)) const SizedBox(width: 10),

                    // Badge de update de Backend (Servidor) — informativo, se aplica solo si no es móvil
                    if (_backendUpdate != null && (!AppConfig.isMobile))
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _frontendUpdate != null
                              ? Colors.grey.shade400
                              : const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          if (_frontendUpdate != null) {
                            SnackBarService.warning(context,
                                'Primero debés actualizar la App para poder actualizar el Servidor con seguridad.');
                            return;
                          }
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (_) => UpdateDialog(updateInfo: _backendUpdate!),
                          );
                          if (result == true) {
                            setState(() {
                              _backendUpdate = null;
                              if (_frontendUpdate == null) _updateCheckCompleted = true;
                            });
                            _checkForUpdates();
                          }
                        },
                        icon: const Icon(Icons.dns_rounded, size: 18),
                        label: const Text('Actualiz. Servidor',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ],
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
