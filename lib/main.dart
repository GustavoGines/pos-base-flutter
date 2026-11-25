import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// Providers
import 'features/settings/domain/entities/business_settings.dart';
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/catalog/presentation/providers/catalog_provider.dart';
import 'features/cash_register/presentation/providers/cash_register_provider.dart';
import 'features/pos/presentation/providers/pos_provider.dart';
import 'features/sales_history/presentation/providers/sales_history_provider.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/customers/providers/customer_provider.dart';
import 'features/trash/providers/trash_provider.dart';
import 'features/reports/presentation/providers/reports_provider.dart';
import 'core/providers/local_terminal_provider.dart';
import 'core/services/remote_scanner_service.dart';
import 'features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'features/reports/data/datasources/inventory_alerts_datasource.dart';
import 'features/mobile/presentation/screens/mobile_menu_screen.dart';
import 'features/mobile/presentation/screens/mobile_scanner_screen.dart';
import 'features/mobile/presentation/screens/mobile_audit_screen.dart';
import 'features/mobile/presentation/screens/mobile_dashboard_screen.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/updater/data/services/ota_startup_checker.dart';

import 'core/presentation/widgets/app_modal_shell.dart';
import 'core/presentation/widgets/license_guard.dart';
import 'core/presentation/widgets/caja4u_startup_splash.dart';
import 'core/presentation/widgets/plan_upgrade_dialog.dart';
import 'core/network/api_client.dart';
import 'core/utils/receipt_printer_service.dart';
import 'core/constants/app_permissions.dart';
import 'core/presentation/widgets/permission_guard.dart';
import 'features/auth/presentation/widgets/admin_pin_dialog.dart';

// Screens
import 'features/settings/presentation/pages/settings_screen.dart';
import 'features/cash_register/presentation/pages/cash_register_management_screen.dart';
import 'features/pos/presentation/pages/pos_screen.dart';
import 'features/catalog/presentation/pages/catalog_screen.dart';

import 'features/cash_register/presentation/pages/cash_register_screen.dart';
import 'features/cash_register/presentation/pages/close_shift_screen.dart';
import 'package:frontend_desktop/features/logistics/presentation/screens/logistics_dashboard_screen.dart';
import 'features/logistics/data/delivery_note_repository.dart';
import 'features/logistics/presentation/providers/logistics_provider.dart';
import 'package:frontend_desktop/features/sales_history/presentation/pages/sales_history_screen.dart';
import 'features/auth/presentation/pages/login_screen.dart';
import 'features/reports/presentation/pages/general_audit_screen.dart';
import 'features/customers/presentation/screens/customers_screen.dart';
import 'features/trash/presentation/screens/trash_screen.dart';
import 'features/reports/presentation/pages/reports_screen.dart';
import 'features/quotes/presentation/pages/quotes_list_screen.dart';
import 'features/quotes/presentation/providers/quote_provider.dart';
import 'features/quotes/data/quote_repository.dart';
import 'features/offers/presentation/providers/offer_provider.dart';
import 'features/offers/data/offer_repository.dart';
import 'features/checks/presentation/providers/check_provider.dart';
import 'features/checks/data/repositories/check_repository_impl.dart';
import 'features/checks/data/datasources/check_remote_datasource.dart';
import 'features/checks/presentation/screens/check_wallet_screen.dart';
import 'features/updater/presentation/widgets/ota_result_dialog.dart';
import 'features/updater/data/services/update_service.dart';
import 'features/updater/presentation/widgets/update_dialog.dart';

// Proveedores
import 'features/suppliers/presentation/screens/suppliers_screen.dart';
import 'features/suppliers/providers/supplier_provider.dart';

// Movimientos de Caja y Gastos
import 'features/cash_movements/providers/cash_movement_provider.dart';
import 'features/cash_movements/providers/expense_category_provider.dart';

// Repositories & DataSources
import 'features/reports/data/datasources/reports_remote_datasource.dart';
import 'features/settings/data/datasources/settings_remote_datasource.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/usecases/get_settings_usecase.dart';
import 'features/settings/domain/usecases/update_settings_usecase.dart';

import 'features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'features/catalog/data/repositories/catalog_repository_impl.dart';
import 'features/catalog/domain/usecases/get_products_usecase.dart';

import 'features/cash_register/data/datasources/cash_register_remote_datasource.dart';
import 'features/cash_register/data/repositories/cash_register_repository_impl.dart';
import 'features/cash_register/domain/usecases/get_all_shifts_usecase.dart';
import 'features/cash_register/domain/usecases/open_shift_usecase.dart';
import 'features/cash_register/domain/usecases/get_current_shift_usecase.dart';
import 'features/cash_register/domain/usecases/close_shift_usecase.dart';
import 'features/cash_register/domain/usecases/get_registers_usecase.dart';

import 'features/pos/data/datasources/pos_remote_datasource.dart';
import 'features/pos/data/repositories/pos_repository_impl.dart';
import 'features/pos/domain/usecases/process_sale_usecase.dart';
import 'features/pos/domain/usecases/search_products_usecase.dart';

import 'features/sales_history/data/datasources/sales_history_remote_datasource.dart';

import 'features/auth/data/datasources/auth_remote_datasource.dart';
import 'features/auth/domain/repositories/auth_repository.dart';

import 'features/users/data/datasources/users_remote_datasource.dart';
import 'features/users/data/repositories/users_repository.dart';
import 'features/users/presentation/providers/users_provider.dart';
import 'features/users/presentation/pages/users_manager_screen.dart';
import 'features/cash_movements/presentation/screens/cash_movements_screen.dart';

class FadePageRouteTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageRouteTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> enterCurve = animation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    final Animation<double> exitCurve = secondaryAnimation.drive(
      CurveTween(curve: Curves.easeInOutCubic),
    );

    return ScaleTransition(
      scale: exitCurve.drive(Tween<double>(begin: 1.0, end: 0.97)),
      child: FadeTransition(
        opacity: exitCurve.drive(Tween<double>(begin: 1.0, end: 0.72)),
        child: FadeTransition(
          opacity: enterCurve,
          child: ScaleTransition(
            scale: enterCurve.drive(Tween<double>(begin: 0.985, end: 1.0)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Silently refreshes the SettingsProvider (plan, license_key) on every
/// navigation event so Feature Gating reacts immediately to background
/// heartbeat updates without a full app restart.
class LicenseRefreshObserver extends NavigatorObserver {
  final BuildContext Function() contextGetter;
  final ValueNotifier<String?> routeNotifier;

  LicenseRefreshObserver(this.contextGetter, this.routeNotifier);

  void _refresh(Route? route) {
    // CRÍTICO: Ignorar popups, dialogos, y dropdowns para no reiniciar estados globales.
    // Solo recargamos settings cuando el usuario navega a una nueva PANTALLA real.
    if (route != null && route is! PageRoute) return;

    try {
      // Actualizar el notificador de ruta para el Muro de Fuego
      if (route != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          routeNotifier.value = route.settings.name;
        });
      }

      // Fire-and-forget: do NOT await, never block navigation.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        contextGetter().read<SettingsProvider>().refreshSettingsSilently();
      });
    } catch (_) {
      // Context might be unmounted during startup - silently ignore.
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) => _refresh(route);

  @override
  void didPop(Route route, Route? previousRoute) => _refresh(previousRoute);

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _refresh(newRoute);
}

/// Verifica si un archivo `shared_preferences.json` en disco es íntegro:
/// - No está vacío.
/// - No contiene bytes nulos (`0x00`, típicos de apagado forzado o suspensión abrupta en NTFS).
/// - Es un JSON válido decodificable como `Map<String, dynamic>`.
bool _isValidWindowsPreferencesFile(File file) {
  try {
    if (!file.existsSync()) return false;
    final bytes = file.readAsBytesSync();
    if (bytes.isEmpty || bytes.contains(0)) {
      return false;
    }
    final content = utf8.decode(bytes, allowMalformed: false).trim();
    if (content.isEmpty) return false;
    final decoded = json.decode(content);
    return decoded is Map<String, dynamic>;
  } catch (_) {
    return false;
  }
}

/// Respalda un archivo de preferencias corrupto a `.bak` y escribe un JSON válido por defecto.
void _backupAndResetPreferencesFileSync(File file, {Map<String, dynamic>? fallbackData}) {
  try {
    if (file.existsSync()) {
      final bakFile = File('${file.path}.bak');
      try {
        file.copySync(bakFile.path);
      } catch (_) {}
    } else {
      file.parent.createSync(recursive: true);
    }
    final defaultMap = fallbackData ?? <String, dynamic>{};
    file.writeAsStringSync(json.encode(defaultMap), flush: true);
  } catch (e) {
    debugPrint('[Bootstrap] Error reparando archivo de preferencias ${file.path}: $e');
  }
}

/// Sanitiza y auto-recupera `shared_preferences.json` en Windows antes de que
/// `shared_preferences_windows` intente hacer `json.decode()`, previniendo
/// la "Pantalla blanca de la muerte" por archivos truncados o llenos de bytes `0x00`.
/// También migra claves desde `%APPDATA%\com.example\frontend_desktop` si están sanas.
void _sanitizeAndMigrateWindowsSharedPreferencesSync({bool forceReset = false}) {
  if (!AppConfig.isDesktop || !Platform.isWindows) return;
  try {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;

    final legacyFile = File(
      p.join(appData, 'com.example', 'frontend_desktop', 'shared_preferences.json'),
    );
    final newDir = Directory(p.join(appData, 'Dev4U', 'Caja4U'));
    final newFile = File(p.join(newDir.path, 'shared_preferences.json'));

    final bool legacyExists = legacyFile.existsSync();
    final bool legacyValid = legacyExists && _isValidWindowsPreferencesFile(legacyFile);
    if (legacyExists && !legacyValid) {
      debugPrint('[Bootstrap] Detectado archivo legado corrupto (${legacyFile.path}). Reparando...');
      _backupAndResetPreferencesFileSync(legacyFile);
    }

    if (forceReset) {
      final defaultUrl = AppConfig.hasLocalLaragonServer()
          ? AppConfig.kLocalhostLaragonUrl
          : AppConfig.kApiBaseUrl;
      _backupAndResetPreferencesFileSync(
        newFile,
        fallbackData: <String, dynamic>{
          'flutter.pos_api': defaultUrl,
          'flutter.pos_api_local': defaultUrl,
        },
      );
      return;
    }

    final bool newExists = newFile.existsSync();
    final bool newValid = newExists && _isValidWindowsPreferencesFile(newFile);

    if (newExists && !newValid) {
      debugPrint(
        '[Bootstrap] CRÍTICO: Detectado shared_preferences.json corrupto o con bytes 0x00 en ${newFile.path}. '
        'Respaldando a .bak y auto-recuperando...',
      );
      Map<String, dynamic> recoveredData = <String, dynamic>{};
      if (legacyValid) {
        try {
          recoveredData = Map<String, dynamic>.from(
            json.decode(legacyFile.readAsStringSync()) as Map,
          );
        } catch (_) {}
      }
      if (recoveredData.isEmpty && AppConfig.hasLocalLaragonServer()) {
        recoveredData['flutter.pos_api'] = AppConfig.kLocalhostLaragonUrl;
        recoveredData['flutter.pos_api_local'] = AppConfig.kLocalhostLaragonUrl;
      }
      _backupAndResetPreferencesFileSync(newFile, fallbackData: recoveredData);
      return;
    }

    if (!newExists) {
      if (legacyValid) {
        newDir.createSync(recursive: true);
        legacyFile.copySync(newFile.path);
      }
      return;
    }

    // Si ambos existen y son válidos, fusionar claves del archivo legado:
    // - Si el archivo legado (v1.8.5) fue modificado más recientemente que el nuevo,
    //   o si en el nuevo archivo la IP es la IP por defecto de fábrica (192.168.1.200)
    //   y en el legado el cliente había configurado su propia IP (ej. 192.168.1.150),
    //   las claves de red y terminal del cliente en el archivo legado SIEMPRE prevalecen.
    if (legacyValid && newValid) {
      final legacyMap = json.decode(legacyFile.readAsStringSync());
      final newMap = json.decode(newFile.readAsStringSync());

      if (legacyMap is Map<String, dynamic> && newMap is Map<String, dynamic>) {
        bool modified = false;
        final bool legacyIsNewer =
            legacyFile.lastModifiedSync().isAfter(newFile.lastModifiedSync());

        const networkAndTerminalKeys = <String>{
          'flutter.pos_api',
          'flutter.pos_api_local',
          'flutter.pos_api_remote',
          'flutter.backend_install_path',
          'flutter.assigned_register_id',
        };

        for (final entry in legacyMap.entries) {
          final key = entry.key;
          final legacyVal = entry.value;
          if (!newMap.containsKey(key)) {
            newMap[key] = legacyVal;
            modified = true;
          } else if (networkAndTerminalKeys.contains(key) && legacyVal != null) {
            final currentNewVal = newMap[key]?.toString() ?? '';
            final legacyValStr = legacyVal.toString();
            // Si en el nuevo archivo quedó la IP por defecto del instalador (.200)
            // o el archivo legado es más reciente y tiene otra IP configurada por el cliente,
            // respetamos siempre la configuración real del cliente.
            final bool newIsFactoryDefault =
                currentNewVal.contains('192.168.1.200');
            if (legacyValStr.isNotEmpty &&
                currentNewVal != legacyValStr &&
                (newIsFactoryDefault || legacyIsNewer)) {
              newMap[key] = legacyVal;
              modified = true;
            }
          }
        }
        if (modified) {
          newFile.writeAsStringSync(json.encode(newMap), flush: true);
        }
      }
    }
  } catch (e) {
    debugPrint('Advertencia sanitizando/migrando SharedPreferences en Windows: $e');
  }
}

/// Obtiene la instancia de `SharedPreferences` de forma blindada.
/// Si el plugin lanza cualquier excepción (ej. FormatException residual),
/// purga y regenera el archivo en disco y reintenta limpiamente.
Future<SharedPreferences> _getSafeSharedPreferences() async {
  if (AppConfig.isDesktop && Platform.isWindows) {
    _sanitizeAndMigrateWindowsSharedPreferencesSync();
  }
  try {
    return await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('[Bootstrap] Falló SharedPreferences.getInstance(): $e. Ejecutando auto-rescate...');
    if (AppConfig.isDesktop && Platform.isWindows) {
      _sanitizeAndMigrateWindowsSharedPreferencesSync(forceReset: true);
    }
    return await SharedPreferences.getInstance();
  }
}

/// Actualiza silenciosamente en clientes de producción el acceso directo del Escritorio
/// (ej. "Sistema POS.lnk" -> "Caja4U.lnk") manteniendo intacto el destino Sistema_POS.exe,
/// y refresca la caché de íconos de Windows.
void _migrateWindowsDesktopShortcutAndIconCache() {
  if (!Platform.isWindows) return;
  try {
    final exePath = Platform.resolvedExecutable;
    final exeDir = p.dirname(exePath);
    final icoCandidate = p.join(exeDir, 'app_icon.ico');
    final iconTarget = File(icoCandidate).existsSync() ? icoCandidate : exePath;

    final psContent = r'''
$ErrorActionPreference = 'SilentlyContinue'
$exePath = $env:CAJA4U_EXE_PATH
$iconPath = $env:CAJA4U_ICON_PATH
$wsh = New-Object -ComObject WScript.Shell
$folders = @(
  [Environment]::GetFolderPath('Desktop'),
  [Environment]::GetFolderPath('CommonDesktopDirectory'),
  [Environment]::GetFolderPath('Programs'),
  [Environment]::GetFolderPath('CommonPrograms')
) | Select-Object -Unique

foreach ($dir in $folders) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { continue }
  Get-ChildItem -LiteralPath $dir -Filter '*.lnk' -Recurse | ForEach-Object {
    $lnk = $_
    $sc = $wsh.CreateShortcut($lnk.FullName)
    if ($sc.TargetPath -and ($sc.TargetPath -ieq $exePath -or $sc.TargetPath -like '*\Sistema_POS.exe')) {
      $sc.Description = 'Caja4U - Punto de Venta'
      if ($iconPath -and (Test-Path -LiteralPath $iconPath)) {
        $sc.IconLocation = "$iconPath,0"
      }
      $sc.Save()
      if ($lnk.Name -ieq 'Sistema POS.lnk') {
        $newPath = Join-Path $lnk.DirectoryName 'Caja4U.lnk'
        if (-not (Test-Path -LiteralPath $newPath)) {
          Rename-Item -LiteralPath $lnk.FullName -NewName 'Caja4U.lnk' -Force
        } else {
          Remove-Item -LiteralPath $lnk.FullName -Force
        }
      }
    } elseif ($lnk.Name -ieq 'Servidor POS.lnk' -or $lnk.Name -ieq 'Servidor Caja4U.lnk') {
      if ($iconPath -and (Test-Path -LiteralPath $iconPath)) {
        $sc.IconLocation = "$iconPath,0"
        $sc.Save()
      }
      if ($lnk.Name -ieq 'Servidor POS.lnk') {
        $newSrvPath = Join-Path $lnk.DirectoryName 'Servidor Caja4U.lnk'
        if (-not (Test-Path -LiteralPath $newSrvPath)) {
          Rename-Item -LiteralPath $lnk.FullName -NewName 'Servidor Caja4U.lnk' -Force
        } else {
          Remove-Item -LiteralPath $lnk.FullName -Force
        }
      }
    }
  }
}
ie4uinit.exe -ClearIconCache
ie4uinit.exe -show
''';

    final tempScript = File(
      p.join(Directory.systemTemp.path, 'caja4u_brand_migrate.ps1'),
    );
    tempScript.writeAsStringSync(psContent, flush: true);

    Process.run(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        tempScript.path,
      ],
      environment: {
        'CAJA4U_EXE_PATH': exePath,
        'CAJA4U_ICON_PATH': iconTarget,
      },
    ).then((_) {
      try {
        if (tempScript.existsSync()) tempScript.deleteSync();
      } catch (_) {}
    }).ignore();
  } catch (_) {}
}

/// Notificador global para capturar errores fatales no controlados durante el arranque
/// y mostrar una pantalla de recuperación en lugar de una ventana blanca vacía.
final ValueNotifier<String?> _globalFatalErrorNotifier = ValueNotifier<String?>(null);

/// Se pone en `true` cuando [MainApp] terminó su carga inicial (con éxito o con error).
/// La pantalla de inicio animada espera esta señal para retirarse.
final ValueNotifier<bool> _startupReadyNotifier = ValueNotifier<bool>(false);

void main() async {
  // CRÍTICO: Inicialización obligatoria para assets y plugins en desktop
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Sanitizar inmediatamente el archivo de preferencias en disco antes de que cualquier
  // plugin o servicio lo lea.
  if (AppConfig.isDesktop && Platform.isWindows) {
    _sanitizeAndMigrateWindowsSharedPreferencesSync();
  }

  // 2. Manejadores globales de errores para evitar "Pantalla blanca de la muerte"
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError Global] ${details.exceptionAsString()}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[PlatformDispatcher Global Error] $error\n$stack');
    if (error is SocketException ||
        error is TimeoutException ||
        error is NetworkException ||
        error is SessionExpiredException) {
      return true;
    }
    if (error is FormatException && error.toString().contains('Unexpected character')) {
      if (AppConfig.isDesktop && Platform.isWindows) {
        _sanitizeAndMigrateWindowsSharedPreferencesSync(forceReset: true);
      }
      _globalFatalErrorNotifier.value =
          'Se detectó un archivo de configuración local dañado por un apagado brusco.\n'
          'Presione "Reiniciar Configuración" o "Reintentar" para continuar.';
      return true;
    }
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Caja4uStartupSplash.backgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Hubo un problema al mostrar este componente',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // 3. Montar el árbol de widgets INMEDIATAMENTE para que nunca quede un lienzo blanco
  runApp(const AppBootstrap());
}

/// Contenedor raíz de arranque seguro: monta de inmediato la ventana con estética Caja4U,
/// ejecuta la inicialización asíncrona (WindowManager, Impresora, SharedPreferences, DI)
/// protegida contra fallos y ofrece botones de auto-rescate ("Reiniciar Configuración" / "Reintentar").
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  Widget? _initializedApp;
  String? _bootstrapError;
  bool _isBootstrapping = true;
  bool _windowInitialized = false;
  bool _splashDismissed = false;

  @override
  void initState() {
    super.initState();
    _startupReadyNotifier.value = false;
    Caja4uStartupSplash.isOverlayActiveNotifier.value = true;
    _globalFatalErrorNotifier.addListener(_onGlobalFatalError);
    _runBootstrap();
  }

  @override
  void dispose() {
    Caja4uStartupSplash.isOverlayActiveNotifier.value = false;
    _globalFatalErrorNotifier.removeListener(_onGlobalFatalError);
    super.dispose();
  }

  void _onGlobalFatalError() {
    final err = _globalFatalErrorNotifier.value;
    if (err != null && mounted && _initializedApp == null) {
      setState(() {
        _bootstrapError = err;
        _isBootstrapping = false;
      });
    }
  }

  Future<void> _resetConfigurationAndRetry() async {
    setState(() {
      _isBootstrapping = true;
      _bootstrapError = null;
      _globalFatalErrorNotifier.value = null;
    });
    try {
      if (AppConfig.isDesktop && Platform.isWindows) {
        _sanitizeAndMigrateWindowsSharedPreferencesSync(forceReset: true);
      }
      final prefs = await _getSafeSharedPreferences();
      await prefs.clear();
      final defaultUrl = AppConfig.hasLocalLaragonServer()
          ? AppConfig.kLocalhostLaragonUrl
          : AppConfig.kApiBaseUrl;
      await prefs.setString('pos_api', defaultUrl);
      await prefs.setString('pos_api_local', defaultUrl);
    } catch (e) {
      debugPrint('[Bootstrap] Error reiniciando configuración: $e');
    }
    await _runBootstrap();
  }

  Future<void> _runBootstrap() async {
    if (mounted) {
      setState(() {
        _isBootstrapping = true;
        _bootstrapError = null;
      });
    }

    try {
      if (AppConfig.isDesktop && !_windowInitialized) {
        _windowInitialized = true;
        try {
          await windowManager.ensureInitialized();
          const WindowOptions windowOptions = WindowOptions(
            size: Size(1280, 720),
            minimumSize: Size(1000, 700),
            center: true,
            title: 'Caja4U  •  by Dev4U',
            titleBarStyle: TitleBarStyle.normal,
          );
          windowManager.waitUntilReadyToShow(windowOptions, () async {
            await windowManager.setTitle('Caja4U  •  by Dev4U');
            await windowManager.show();
            await windowManager.focus();
            await windowManager.maximize();
          });
        } catch (e) {
          debugPrint('[Bootstrap] Advertencia inicializando windowManager: $e');
        }
      }

      if (AppConfig.isDesktop) {
        try {
          await ReceiptPrinterService.instance
              .initialize()
              .timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint('[Bootstrap] Advertencia inicializando impresora: $e');
        }
      }

      final prefs = await _getSafeSharedPreferences();

      if (AppConfig.isDesktop && Platform.isWindows) {
        final iconCacheRefreshed =
            prefs.getBool('caja4u_desktop_brand_v3_migrated') ?? false;
        if (!iconCacheRefreshed) {
          _migrateWindowsDesktopShortcutAndIconCache();
          await prefs.setBool('caja4u_desktop_brand_v3_migrated', true);
        }
      }

      String localUrl = prefs.getString('pos_api_local') ??
          prefs.getString('pos_api') ??
          AppConfig.kApiBaseUrl;
      if (localUrl == 'http://127.0.0.1/pos-backend/public/api' ||
          localUrl == 'http://localhost/pos-backend/public/api') {
        localUrl = AppConfig.kLocalhostLaragonUrl;
        await prefs.setString('pos_api_local', localUrl);
        await prefs.setString('pos_api', localUrl);
      }
      final String remoteUrl = prefs.getString('pos_api_remote') ?? '';

      String activeApiUrl = localUrl;

      // ── Smart Auto-Fallback Network (Mobile/Tablet) ──
      final bool hasValidRemote =
          remoteUrl.trim().length > 10 && remoteUrl.contains('http');

      if (hasValidRemote && AppConfig.isMobile) {
        try {
          final response = await http
              .get(Uri.parse('$localUrl/settings'))
              .timeout(const Duration(milliseconds: 2000));
          if (response.statusCode >= 500) throw Exception('Local server error');
          activeApiUrl = localUrl;
          debugPrint('SmartNetwork: Conectado a LOCAL -> $activeApiUrl');
        } catch (e) {
          activeApiUrl = remoteUrl;
          debugPrint(
              'SmartNetwork: Red Local falló. Cambiando a REMOTO -> $activeApiUrl');
        }
      } else {
        activeApiUrl = localUrl;
      }

      await prefs.setString('pos_api', activeApiUrl);
      final savedApiUrl = activeApiUrl;

      // 🔁 RESCUE TRIGGER OTA 🔁
      if (AppConfig.isMobile) {
        const currentAppVersion = '2.2.0';
        const rescueSecret = 'pos-rescue-2026-GGLabs';
        final lastVersion = prefs.getString('app_version') ?? '1.0.0';
        if (lastVersion != currentAppVersion) {
          try {
            http.get(
              Uri.parse('$savedApiUrl/system/rescue-migrate'),
              headers: {'X-Rescue-Token': rescueSecret},
            ).ignore();
            await prefs.setString('app_version', currentAppVersion);
            debugPrint(
                'Rescue Trigger: Migración solicitada ($lastVersion -> $currentAppVersion)');
          } catch (e) {
            debugPrint('Rescue Trigger falló: $e');
          }
        }
      }

      // Inicialización de Dependencias Base (DI)
      final String apiUrl = savedApiUrl;
      final httpClient = ApiClient(http.Client());
      if (hasValidRemote) {
        httpClient.configureFailover(
          primaryUrl: activeApiUrl,
          fallbackUrl: activeApiUrl == localUrl ? remoteUrl : localUrl,
        );
      }

      final authRepo = AuthRepository(
          remoteDataSource:
              AuthRemoteDataSource(baseUrl: apiUrl, client: httpClient));
      final authProvider = AuthProvider(repository: authRepo)
        ..apiClient = httpClient;
      try {
        await authProvider.restoreSessionFromPrefs();
      } catch (e) {
        debugPrint('[Bootstrap] Advertencia restaurando sesión local: $e');
      }

      final settingsRepo = SettingsRepositoryImpl(
          remoteDataSource:
              SettingsRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));
      final getSettingsUseCase = GetSettingsUseCase(settingsRepo);
      final updateSettingsUseCase = UpdateSettingsUseCase(settingsRepo);

      final catalogRepo = CatalogRepositoryImpl(
          remoteDataSource:
              CatalogRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));
      final getProductsUseCase = GetProductsUseCase(catalogRepo);

      final cashRegisterRepo = CashRegisterRepositoryImpl(
          remoteDataSource: CashRegisterRemoteDataSourceImpl(
              baseUrl: apiUrl, client: httpClient));

      final posRepo = PosRepositoryImpl(
          remoteDataSource:
              PosRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));

      final salesHistoryDataSource =
          SalesHistoryRemoteDataSource(baseUrl: apiUrl, client: httpClient);

      final reportsDataSource =
          ReportsRemoteDataSource(baseUrl: apiUrl, client: httpClient);

      final inventoryAlertsDataSource =
          InventoryAlertsDataSource(baseUrl: apiUrl, client: httpClient);

      final deliveryNoteRepo =
          DeliveryNoteRepository(baseUrl: apiUrl, client: httpClient);

      final usersRepo = UsersRepository(
          dataSource: UsersRemoteDataSource(baseUrl: apiUrl, client: httpClient));

      final checkRepo = CheckRepositoryImpl(
          remoteDataSource:
              CheckRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));

      final appWidget = MultiProvider(
        providers: [
          ChangeNotifierProvider(
              create: (_) => LocalTerminalProvider(), lazy: false),
          ChangeNotifierProxyProvider<LocalTerminalProvider,
              RemoteScannerService>(
            create: (_) => RemoteScannerService(),
            update: (_, localTerminal, scanner) {
              final service = scanner ?? RemoteScannerService();
              service.updateTerminalId(localTerminal.terminalId);
              return service;
            },
            lazy: true,
          ),
          ChangeNotifierProvider.value(
            value: authProvider,
          ),
          ChangeNotifierProvider(
              create: (_) => SettingsProvider(
                    getSettingsUseCase: getSettingsUseCase,
                    updateSettingsUseCase: updateSettingsUseCase,
                  ),
              lazy: false),
          ChangeNotifierProvider(
              create: (_) =>
                  SalesHistoryProvider(dataSource: salesHistoryDataSource),
              lazy: false),
          Provider<SalesHistoryRemoteDataSource>.value(
              value: salesHistoryDataSource),
          ChangeNotifierProvider(
              create: (_) => CatalogProvider(
                    getProductsUseCase: getProductsUseCase,
                    repository: catalogRepo,
                  ),
              lazy: false),
          ChangeNotifierProvider(
              create: (_) => ReportsProvider(
                  dataSource: reportsDataSource,
                  balanceDataSource: inventoryAlertsDataSource),
              lazy: false),
          ChangeNotifierProvider(
            create: (_) =>
                InventoryAlertsProvider(dataSource: inventoryAlertsDataSource),
            lazy: false,
          ),
          ChangeNotifierProvider(
            create: (_) => CashRegisterProvider(
              getCurrentShiftUseCase: GetCurrentShiftUseCase(cashRegisterRepo),
              getAllShiftsUseCase: GetAllShiftsUseCase(cashRegisterRepo),
              openShiftUseCase: OpenShiftUseCase(cashRegisterRepo),
              closeShiftUseCase: CloseShiftUseCase(cashRegisterRepo),
              getRegistersUseCase: GetRegistersUseCase(cashRegisterRepo),
              printerService: ReceiptPrinterService.instance,
            ),
            lazy: false,
          ),
          ChangeNotifierProxyProvider<SettingsProvider, PosProvider>(
            create: (_) => PosProvider(
              processSaleUseCase: ProcessSaleUseCase(posRepo),
              searchProductsUseCase: SearchProductsUseCase(posRepo),
              repository: posRepo,
            ),
            update: (_, settings, pos) {
              pos!.updateSettings(settings.settings);
              return pos;
            },
            lazy: false,
          ),
          ChangeNotifierProvider(
            create: (_) => UsersProvider(repository: usersRepo),
            lazy: true,
          ),
          Provider.value(value: usersRepo),
          Provider<ApiClient>.value(value: httpClient),
          ChangeNotifierProxyProvider<SettingsProvider, CustomerProvider>(
            create: (_) => CustomerProvider(baseUrl: apiUrl, client: httpClient),
            update: (_, settingsProvider, customerProvider) {
              customerProvider!
                  .setAccess(settingsProvider.features.currentAccounts);
              return customerProvider;
            },
            lazy: false,
          ),
          ChangeNotifierProvider(
              create: (_) => TrashProvider(baseUrl: apiUrl, client: httpClient),
              lazy: false),
          ChangeNotifierProvider(
            create: (_) => QuoteProvider(
              repository: QuoteRepository(baseUrl: apiUrl, client: httpClient),
            ),
            lazy: true,
          ),
          ChangeNotifierProvider(
            create: (_) => OfferProvider(
              repository: OfferRepository(baseUrl: apiUrl, client: httpClient),
            ),
            lazy: false,
          ),
          ChangeNotifierProvider(
            create: (_) => LogisticsProvider(repository: deliveryNoteRepo),
            lazy: true,
          ),
          ChangeNotifierProvider(
            create: (_) => CheckProvider(repository: checkRepo),
            lazy: true,
          ),
          ChangeNotifierProvider(
            create: (_) => SupplierProvider(baseUrl: apiUrl, client: httpClient),
            lazy: true,
          ),
          ChangeNotifierProvider(
            create: (_) => CashMovementProvider(baseUrl: apiUrl, client: httpClient),
            lazy: true,
          ),
          ChangeNotifierProvider(
            create: (_) => ExpenseCategoryProvider(baseUrl: apiUrl, client: httpClient),
            lazy: true,
          ),
        ],
        child: const MainApp(),
      );

      if (mounted) {
        setState(() {
          _initializedApp = appWidget;
          _isBootstrapping = false;
          _bootstrapError = null;
        });
      }
    } catch (e, stack) {
      debugPrint('[Bootstrap Fatal Error] $e\n$stack');
      if (mounted) {
        setState(() {
          _isBootstrapping = false;
          _bootstrapError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // La animación de inicio se monta como capa superior sobre el arranque real:
    // la carga sigue en paralelo debajo y la capa se retira con un fundido.
    // IMPORTANTE: la estructura (Directionality > Stack > contenido) se mantiene fija
    // aunque la capa se retire, para que Flutter NO vuelva a montar la app
    // (lo que repetiría toda la inicialización y perdería el estado).
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          KeyedSubtree(
            key: const ValueKey('caja4u_app_content'),
            child: IgnorePointer(
              ignoring: !_splashDismissed,
              child: FocusScope(
                canRequestFocus: _splashDismissed,
                child: _buildContent(),
              ),
            ),
          ),
          if (!_splashDismissed)
            ValueListenableBuilder<bool>(
              valueListenable: _startupReadyNotifier,
              builder: (context, mainAppReady, _) => Caja4uStartupSplash(
                isReady: mainAppReady || _bootstrapError != null,
                onDismissed: () {
                  if (mounted) setState(() => _splashDismissed = true);
                  Caja4uStartupSplash.isOverlayActiveNotifier.value = false;
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_initializedApp != null && _bootstrapError == null) {
      return _initializedApp!;
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Caja4U  •  by Dev4U',
      home: Scaffold(
        backgroundColor: Caja4uStartupSplash.backgroundColor,
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.18),
                        blurRadius: 36,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/caja4u_logo_full.png',
                      width: 200,
                      height: 170,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.point_of_sale_rounded,
                        size: 72,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_isBootstrapping && _bootstrapError == null) ...[
                  RepaintBoundary(
                    child: ExcludeSemantics(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: const SizedBox(
                          width: 180,
                          height: 4,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.white12,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Preparando entorno de Caja4U...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white60,
                      letterSpacing: 0.4,
                    ),
                  ),
                ] else ...[
                  const Icon(Icons.error_outline_rounded,
                      color: Colors.redAccent, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Hubo un problema al iniciar el sistema',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _bootstrapError ?? 'Error inesperado en la configuración local.',
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _runBootstrap,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reintentar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _resetConfigurationAndRetry,
                        icon: const Icon(Icons.restore_rounded, color: Colors.amber),
                        label: const Text(
                          'Reiniciar Configuración',
                          style: TextStyle(color: Colors.amber),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.amber),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
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

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool _isInitializing = true;
  String? _initError;

  bool _isShowingSessionDialog = false;
  bool _isShowingNetworkDialog = false;
  final GlobalKey<NavigatorState> _splashNavigatorKey =
      GlobalKey<NavigatorState>();

  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _initializeApp();

      // ── GANCHOS DE SEGURIDAD GLOBAL (Single Active Session) ──
      // Atrapa cualquier Error 401 (SESSION_EXPIRED) del ApiClient de manera centralizada.
      // Así se protege automáticamente toda la aplicación sin tocar pantalla por pantalla.
      final authProv = context.read<AuthProvider>();
      authProv.apiClient?.onSessionExpired = () {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted && !_isShowingSessionDialog) {
          _handleGlobalSessionExpired(ctx, authProv);
        }
      };

      // Intercepta Error 403 (Permiso Denegado / Descuento no autorizado) y solicita PIN de Administrador
      authProv.apiClient?.onPermissionDenied = (reason) async {
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return null;

        return await showDialog<String>(
          context: ctx,
          barrierDismissible: true,
          builder: (_) => AdminPinDialog(
            actionDescription: reason ?? 'Autorización de Administrador',
          ),
        );
      };
    });
  }

  Future<void> _handleGlobalSessionExpired(
      BuildContext ctx, AuthProvider authProv) async {
    _isShowingSessionDialog = true;

    await showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => PopScope(
        canPop: false,
        child: AppModalShell(
          title: 'Sesión Cerrada',
          subtitle: 'Inicio de sesión detectado en otro dispositivo',
          icon: Icons.phonelink_off_rounded,
          accent: AppModalAccent.orange,
          showCloseButton: false,
          compact: true,
          maxWidth: 440,
          bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          body: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.orange.withValues(alpha: 0.30),
              ),
            ),
            child: const Text(
              'Tu sesión fue cerrada porque otro dispositivo inició sesión con tu usuario.\n\n'
              'Por seguridad, solo se permite una sesión activa por usuario a la vez.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          footerActions: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.orange),
              onPressed: () => Navigator.pop(dCtx),
              icon: const Icon(Icons.login),
              label: const Text('Volver al Login'),
            ),
          ],
        ),
      ),
    );

    // Aniquilar sesión localmente y redirigir
    await authProv.forceLogout();
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (r) => false);
    _isShowingSessionDialog = false;
  }

  Future<bool> _tryLocalhostFallback({
    required SharedPreferences prefs,
    required String previousUrl,
    required SettingsProvider settingsProvider,
    required ApiClient apiClient,
  }) async {
    final candidates = <String>[
      AppConfig.kLocalhostLaragonUrl,
      if (AppConfig.kApiBaseUrl != AppConfig.kLocalhostLaragonUrl)
        AppConfig.kApiBaseUrl,
      AppConfig.kLocalhostDirectUrl,
    ];

    for (final candidateUrl in candidates) {
      try {
        debugPrint(
            '[NetFallback] Probando ping local contra $candidateUrl (timeout 3s)...');
        final pingRes = await http
            .get(
              Uri.parse('$candidateUrl/settings'),
              headers: const {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 3));

        if (pingRes.statusCode == 200) {
          apiClient.setBaseUrlOverride(
            fromBaseUrl: previousUrl,
            toBaseUrl: candidateUrl,
          );
          settingsProvider.updateBaseUrl(candidateUrl);

          try {
            await settingsProvider
                .loadSettings()
                .timeout(const Duration(seconds: 4));
            await prefs.setString('pos_api', candidateUrl);
            await prefs.setString('pos_api_local', candidateUrl);
            debugPrint(
                '[NetFallback] Recuperación exitosa usando servidor local: $candidateUrl');
            return true;
          } catch (loadErr) {
            apiClient.setBaseUrlOverride(
              fromBaseUrl: candidateUrl,
              toBaseUrl: previousUrl,
            );
            settingsProvider.updateBaseUrl(previousUrl);
            rethrow;
          }
        }
      } catch (pingErr) {
        debugPrint('[NetFallback] Sin respuesta en $candidateUrl: $pingErr');
      }
    }
    return false;
  }

  Future<void> _initializeApp() async {
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final apiClient = Provider.of<ApiClient>(context, listen: false);
    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    bool success = false;
    final bool isMobilePlatform = AppConfig.isMobile;
    final prefs = await _getSafeSharedPreferences();
    final currentUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
    final bool isLanIp =
        !isMobilePlatform && AppConfig.isPrivateLanIpUrl(currentUrl);

    final Duration initialTimeout = isMobilePlatform
        ? const Duration(seconds: 15)
        : (isLanIp ? const Duration(seconds: 6) : const Duration(seconds: 8));

    try {
      await settingsProvider.loadSettings().timeout(initialTimeout);
      success = true;
    } catch (e) {
      debugPrint('[Init] Error conectando a $currentUrl: $e');

      if (!isMobilePlatform) {
        // IMPORTANTE: NUNCA sobreescribir la IP de red local configurada por el cliente
        // (ej. 192.168.1.150) con localhost ni con 192.168.1.200 cuando hay un timeout temporal.
        // Solo hacemos fallback automático si la URL era un puerto de desarrollo (:8000).
        if (currentUrl.contains(':8000') && AppConfig.hasLocalLaragonServer()) {
          success = await _tryLocalhostFallback(
            prefs: prefs,
            previousUrl: currentUrl,
            settingsProvider: settingsProvider,
            apiClient: apiClient,
          );
        }

        // Dar un breve margen de 1.5s y reintentar contra la MISMA URL configurada por el cliente
        // por si Apache/MySQL o la red Wi-Fi estaban despertando tras el reinicio OTA.
        if (!success) {
          await Future.delayed(const Duration(milliseconds: 1500));
          try {
            await settingsProvider
                .loadSettings()
                .timeout(const Duration(seconds: 5));
            success = true;
          } catch (_) {}
        }
      }
    }

    if (!success) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _initError =
            'No se pudo conectar al servidor ($currentUrl). Verifique la IP o su conexión de red.';
      });
      _startupReadyNotifier.value = true;

      // Redirigir / abrir inmediatamente el diálogo de configuración de red/servidor
      // para que el usuario pueda ingresar la IP correcta sin congelar la pantalla.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final dialogCtx = _splashNavigatorKey.currentContext;
        if (mounted &&
            dialogCtx != null &&
            dialogCtx.mounted &&
            !_isShowingNetworkDialog) {
          _showNetworkSettingsDialog(dialogCtx);
        }
      });
      return; // Abortar resto de la carga
    }

    // 2. Verificar estado de la Caja de ESTA terminal física asignada
    try {
      final assignedRegisterId = settingsProvider.assignedRegisterId;
      await Provider.of<CashRegisterProvider>(context, listen: false)
          .checkCurrentShift(
              registerId: assignedRegisterId > 0 ? assignedRegisterId : null);
    } catch (_) {
      // Si falla obtener el turno, no bloqueamos la app pero registramos el error
      debugPrint('Error al cargar turno inicial');
    }

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _initError = null;
      });
      _startupReadyNotifier.value = true;
      if (!AppConfig.isMobile) {
        UpdateService().startPeriodicCheck();
      }

      // ── CHECK DE RESULTADO OTA (Smart Chaining) ──
      // Si el updater corrió mientras la app estaba cerrada, mostrar el
      // resultado al usuario. Si fue una actualización exitosa del Frontend,
      // encadenar automáticamente la actualización del Backend (Auto-Resume).
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final ctx = navigatorKey.currentContext;
        if (ctx == null || !ctx.mounted) return;

        final otaResult = OtaStartupChecker.check();
        if (otaResult != null) {
          OtaStartupChecker.clearState();

          // Auto-Resume: si la App se actualizó con éxito, buscar silenciosamente
          // si el Backend sigue pendiente ANTES de mostrar el popup de éxito.
          if (otaResult.success && otaResult.component == 'frontend') {
            try {
              final check = await UpdateService().checkUpdate();
              final backendUpdate = check.backendUpdate;

            // Si llegamos aquí: o solo había update de frontend, o hubo error,
            // o esta PC es una Caja Secundaria conectada al servidor por red LAN
            // (en cuyo caso no debe auto-disparar la actualización del Backend local).
            bool isSecondaryLanTerminal = false;
            if (backendUpdate != null) {
              try {
                final prefs = await _getSafeSharedPreferences();
                final apiUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
                isSecondaryLanTerminal = !(await UpdateDialog.doesApiUrlPointToThisMachine(apiUrl));
              } catch (_) {}
            }

            if (backendUpdate != null && !isSecondaryLanTerminal && ctx.mounted) {
              // Actualización integral en progreso en la PC Servidor: saltamos el cartel de "App actualizada"
              // y pasamos directamente a la Fase 2 (Servidor).
              await showDialog(
                context: ctx,
                barrierDismissible: false,
                builder: (_) => UpdateDialog(
                  updateInfo: backendUpdate,
                  autoStart: true,
                ),
              );
              // Refrescar forzosamente la pantalla de login para borrar el badge obsoleto
              AppConfig.navigatorKey.currentState
                  ?.pushReplacementNamed('/login');
              return; // Salimos para no mostrar el OtaResultDialog
            }
            } catch (e) {
              debugPrint('[OTA Auto-Resume] Error chequeando backend: $e');
            }
          }

          // Si llegamos aquí, o no hubo auto-resume, o fue un error, o solo frontend.
          if (ctx.mounted) {
            await showDialog(
              context: ctx,
              barrierDismissible: otaResult.success,
              builder: (_) => OtaResultDialog(result: otaResult),
            );
            // Refrescar login por si había badges viejos cacheados
            AppConfig.navigatorKey.currentState?.pushReplacementNamed('/login');
          }
        }
      });
    }
  }

  final GlobalKey<NavigatorState> navigatorKey = AppConfig.navigatorKey;
  final ValueNotifier<String?> _currentRoute = ValueNotifier<String?>(null);

  Future<void> _resetConfigurationToDefault() async {
    final prefs = await _getSafeSharedPreferences();
    final oldUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;
    final defaultUrl = AppConfig.hasLocalLaragonServer()
        ? AppConfig.kLocalhostLaragonUrl
        : AppConfig.kApiBaseUrl;

    await prefs.setString('pos_api', defaultUrl);
    await prefs.setString('pos_api_local', defaultUrl);

    if (!mounted) return;
    final apiClient = Provider.of<ApiClient>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    apiClient.setBaseUrlOverride(fromBaseUrl: oldUrl, toBaseUrl: defaultUrl);
    settingsProvider.updateBaseUrl(defaultUrl);

    await _initializeApp();
  }

  Future<void> _showNetworkSettingsDialog(BuildContext dialogContext) async {
    if (_isShowingNetworkDialog) return;
    _isShowingNetworkDialog = true;

    final prefs = await _getSafeSharedPreferences();
    final currentUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;

    if (!dialogContext.mounted) {
      _isShowingNetworkDialog = false;
      return;
    }

    String? newUrl;
    try {
      newUrl = await showDialog<String>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (_) => _NetworkSettingsDialog(initialUrl: currentUrl),
      );
    } finally {
      _isShowingNetworkDialog = false;
    }

    if (newUrl == null || newUrl.isEmpty || !mounted) return;

    await prefs.setString('pos_api', newUrl);
    // IMPORTANTE: También guardamos pos_api_local para que no pise la configuración al reiniciar
    await prefs.setString('pos_api_local', newUrl);

    if (!mounted) return;
    final apiClient = Provider.of<ApiClient>(context, listen: false);
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);

    apiClient.setBaseUrlOverride(
      fromBaseUrl: currentUrl,
      toBaseUrl: newUrl,
    );
    settingsProvider.updateBaseUrl(newUrl);

    // Esperar a que finalice la animación de cierre del diálogo antes de reconstruir el árbol raíz
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;

    await _initializeApp();
  }

  Widget _buildLoadingOrErrorScreen() {
    return MaterialApp(
      navigatorKey: _splashNavigatorKey,
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (innerContext) => Scaffold(
          backgroundColor: Caja4uStartupSplash.backgroundColor,
          body: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 440),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withValues(alpha: 0.18),
                          blurRadius: 36,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset(
                        'assets/caja4u_logo_full.png',
                        width: 200,
                        height: 170,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.point_of_sale_rounded,
                          size: 72,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_initError == null) ...[
                    RepaintBoundary(
                      child: ExcludeSemantics(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: const SizedBox(
                            width: 180,
                            height: 4,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.white12,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    _initError != null
                        ? 'ESTADO: $_initError'
                        : 'Iniciando servicios de Caja4U...',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white60,
                      letterSpacing: 0.4,
                    ),
                  ),
                  if (_initError != null) ...[
                    const SizedBox(height: 28),
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.redAccent, size: 48),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            _initializeApp();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reintentar Conexión'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            _resetConfigurationToDefault();
                          },
                          icon: const Icon(Icons.restore_rounded,
                              color: Colors.amberAccent),
                          label: const Text('Reiniciar Configuración',
                              style: TextStyle(color: Colors.amberAccent)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.amberAccent),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: () async {
                        if (!mounted) return;
                        await _showNetworkSettingsDialog(innerContext);
                      },
                      icon: const Icon(Icons.settings_ethernet,
                          color: Colors.white70),
                      label: const Text('Configurar Servidor Manualmente',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing || _initError != null) {
      return _buildLoadingOrErrorScreen();
    }

    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [
        LicenseRefreshObserver(
            () => navigatorKey.currentContext!, _currentRoute),
      ],
      builder: (context, child) {
        final Widget guardedChild = LicenseGuard(
          routeNotifier: _currentRoute,
          navigatorKey: navigatorKey,
          child: child!,
        );

        // Protección GLOBAL anti-overflow para ventanas estrechas
        return LayoutBuilder(
          builder: (context, constraints) {
            if (AppConfig.isMobile) return guardedChild;
            const double minAppWidth = 1024.0;
            const double minAppHeight = 550.0;

            final bool needsH = constraints.maxWidth < minAppWidth;
            final bool needsV = constraints.maxHeight < minAppHeight;

            if (!needsH && !needsV) return guardedChild;

            Widget content = SizedBox(
              width: needsH ? minAppWidth : constraints.maxWidth,
              height: needsV ? minAppHeight : constraints.maxHeight,
              child: guardedChild,
            );

            if (needsV) {
              content = Scrollbar(
                controller: _vScroll,
                thumbVisibility: true,
                thickness: 8,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  controller: _vScroll,
                  scrollDirection: Axis.vertical,
                  child: content,
                ),
              );
            }

            if (needsH) {
              content = Scrollbar(
                controller: _hScroll,
                thumbVisibility: true,
                thickness: 8,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: content,
                ),
              );
            }

            return content;
          },
        );
      },
      debugShowCheckedModeBanner: false,
      title: 'Caja4U  •  by Dev4U',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'AR'),
        Locale('es', 'ES'),
        Locale('en', 'US'),
      ],
      theme: AppTheme.light(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.windows: FadePageRouteTransitionsBuilder(),
            TargetPlatform.linux: FadePageRouteTransitionsBuilder(),
            TargetPlatform.macOS: FadePageRouteTransitionsBuilder(),
            TargetPlatform.android: FadePageRouteTransitionsBuilder(),
            TargetPlatform.iOS: FadePageRouteTransitionsBuilder(),
          },
        ),
      ),
      initialRoute: '/login',
      onGenerateRoute: (settings) {
        if (settings.name != '/home') return null;
        return PageRouteBuilder<void>(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 460),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, __, ___) => _buildHomeScreen(),
          transitionsBuilder: (_, animation, secondaryAnimation, child) {
            // Deja completar el primer layout pesado del POS mientras la opacidad
            // está en 0 para que el fundido corra fluido sin saltos ni destellos.
            final CurvedAnimation enterFade = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.16, 1.0, curve: Curves.easeOutCubic),
            );
            final CurvedAnimation enterMotion = CurvedAnimation(
              parent: animation,
              curve: const Interval(0.10, 1.0, curve: Curves.easeOutCubic),
            );
            final CurvedAnimation exitCurve = CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeInOutCubic,
            );

            return ScaleTransition(
              scale: exitCurve.drive(Tween<double>(begin: 1.0, end: 0.97)),
              child: FadeTransition(
                opacity: enterFade,
                child: SlideTransition(
                  position: enterMotion.drive(
                    Tween<Offset>(
                      begin: const Offset(0, 0.018),
                      end: Offset.zero,
                    ),
                  ),
                  child: ScaleTransition(
                    scale: enterMotion.drive(Tween<double>(begin: 0.978, end: 1.0)),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
      routes: {
        '/login': (context) => const LoginScreen(),
        '/pos': (context) => const PosScreen(),
        '/close-shift': (context) => const CloseShiftScreen(),
        '/catalog': (context) => const PermissionGuard(
              permissionKey: AppPermissions.manageCatalog,
              child: CatalogScreen(),
            ),
        '/sales-history': (context) => const SalesHistoryScreen(),
        '/general-audit': (context) => const PermissionGuard(
              permissionKey: AppPermissions.manageShifts,
              child: GeneralAuditScreen(),
            ),
        '/users': (context) => const PermissionGuard(
              permissionKey: AppPermissions.manageUsers,
              child: UsersManagerScreen(),
            ),
        '/settings': (context) => const PermissionGuard(
              permissionKey: AppPermissions.manageSettings,
              child: SettingsScreen(),
            ),
        '/settings/registers': (context) => _buildLicensedRoute(
              context: context,
              isEnabled: (f) => f.multiCaja,
              featureName: 'Múltiples Cajas / Terminales',
              description:
                  'La gestión de múltiples cajas registradoras simultáneas está disponible en el Plan Premium o como módulo adicional.',
              permissionKey: AppPermissions.manageSettings,
              child: const CashRegisterManagementScreen(),
            ),
        '/cuentas-corrientes': (context) => _buildLicensedRoute(
              context: context,
              isEnabled: (f) => f.currentAccounts,
              featureName: 'Cuentas Corrientes',
              description:
                  'La gestión de clientes con cuenta corriente (fiado) y saldos deudores está disponible en el Plan Premium o como módulo adicional.',
              permissionKey: AppPermissions.viewCustomersAccount,
              child: const CustomersScreen(),
            ),
        '/checks': (context) => _buildLicensedRoute(
              context: context,
              isEnabled: (f) => f.checks,
              featureName: 'Cartera de Cheques',
              description:
                  'El módulo de Cheques de Terceros es exclusivo del Plan Premium.',
              permissionKey: AppPermissions.viewChecks,
              child: const CheckWalletScreen(),
            ),
        '/trash': (context) => const PermissionGuard(
              permissionKey: AppPermissions.manageTrash,
              child: TrashScreen(),
            ),
        // [hardware_store]
        '/quotes': (context) => _buildLicensedRoute(
              context: context,
              isEnabled: (f) => f.quotes,
              featureName: 'Presupuestos Rápidos',
              description:
                  'La generación y gestión de presupuestos está disponible en el Plan Ferretería/Tecnología, Plan Premium o como módulo adicional.',
              permissionKey: AppPermissions.manageQuotes,
              child: const QuotesListScreen(),
            ),
        '/reports': (context) => const PermissionGuard(
              permissionKey: AppPermissions.viewReports,
              child: ReportsScreen(),
            ),
        // [logistics]
        '/delivery-notes': (context) => _buildLicensedRoute(
              context: context,
              isEnabled: (f) => f.logistics,
              featureName: 'Logística y Remitos',
              description:
                  'El módulo de Remitos y Despacho Logístico es exclusivo del rubro Ferretería/Corralón o como módulo adicional.',
              permissionKey: AppPermissions.manageDeliveryNotes,
              child: const LogisticsDashboardScreen(),
            ),
        // [suppliers]
        '/suppliers': (context) => _buildLicensedRoute(
              context: context,
              isEnabled: (f) => f.suppliers,
              featureName: 'Gestión de Proveedores',
              description:
                  'El control de proveedores, facturas de compra y saldos está disponible en el Plan Premium o como módulo adicional.',
              permissionKey: AppPermissions.viewSuppliers,
              child: const SuppliersScreen(),
            ),
        // [cash movements]
        '/cash-movements': (context) => _buildLicensedRoute(
              context: context,
              isEnabled: (f) => f.expenses,
              featureName: 'Gestión de Gastos y Movimientos',
              description:
                  'El módulo de Gastos Operativos y Movimientos de Caja está disponible en el Plan Premium o como módulo adicional.',
              permissionKey: AppPermissions.viewExpenses,
              child: const CashMovementsScreen(),
            ),
        // [mobile]
        '/mobile-scanner': (context) => const MobileScannerScreen(),
        '/mobile-audit': (context) => const MobileAuditScreen(),
        '/mobile-dashboard': (context) => const PermissionGuard(
              permissionKey: AppPermissions.viewReports,
              child: MobileDashboardScreen(),
            ),
      },
    );
  }

  Widget _buildLicensedRoute({
    required BuildContext context,
    required bool Function(FeatureFlags features) isEnabled,
    required String featureName,
    required String description,
    required String permissionKey,
    required Widget child,
  }) {
    final settings = context.watch<SettingsProvider>().settings;
    if (settings != null && !isEnabled(settings.features)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          Navigator.of(context).pushReplacementNamed('/home');
        }
        PlanUpgradeDialog.show(
          context,
          featureName: featureName,
          description: description,
          onNavigateToSettings: () =>
              Navigator.of(context).pushNamed('/settings'),
        );
      });
      return const Scaffold(
        backgroundColor: Color(0xFF1E2D45),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return PermissionGuard(
      permissionKey: permissionKey,
      child: child,
    );
  }

  Widget _buildHomeScreen() {
    return Consumer<CashRegisterProvider>(
      builder: (ctx, cashProv, _) {
        if (AppConfig.isMobile) {
          return const MobileMenuScreen();
        }
        final shift = cashProv.currentShift;
        final bool open = shift != null && shift.isOpen;
        if (open) {
          return const PosScreen();
        }
        return CashRegisterScreen(
          isLoading: cashProv.isLoading,
          errorMessage: cashProv.errorMessage,
          onOpenShift: (amount, registerId) async {
            final userId = ctx.read<AuthProvider>().currentUser?['id'] ?? 1;

            final success =
                await cashProv.openShift(amount, userId, registerId);
            if (success) {
              navigatorKey.currentState?.pushReplacementNamed('/pos');
            } else {
              final rawError = cashProv.errorMessage ?? '';
              final msg = rawError.replaceAll('Exception: ', '');

              if (rawError.contains('SESSION_EXPIRED') ||
                  rawError.contains('otro dispositivo')) {
                return;
              }

              final isPlanLimitError = rawError.contains('Límite de cajas') ||
                  rawError.contains('plan a PRO') ||
                  rawError.contains('plan a PREMIUM') ||
                  rawError.contains('Actualice su plan');

              if (isPlanLimitError && ctx.mounted) {
                PlanUpgradeDialog.show(
                  ctx,
                  featureName: 'Múltiples Cajas Simultáneas',
                  description:
                      'Su plan actual permite 1 caja activa a la vez. '
                      'Para operar con varias terminales simultáneamente '
                      'es necesario el Plan Premium.\n\n'
                      'Comuníquese con soporte para ampliar su licencia.',
                  onNavigateToSettings: () =>
                      navigatorKey.currentState?.pushNamed('/settings'),
                );
              } else if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(msg), backgroundColor: Colors.red),
                );
              }
            }
          },
          onContinueToPos: () {
            navigatorKey.currentState?.pushReplacementNamed('/pos');
          },
        );
      },
    );
  }
}

class _NetworkSettingsDialog extends StatefulWidget {
  final String initialUrl;

  const _NetworkSettingsDialog({required this.initialUrl});

  @override
  State<_NetworkSettingsDialog> createState() => _NetworkSettingsDialogState();
}

class _NetworkSettingsDialogState extends State<_NetworkSettingsDialog> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit() {
    String newUrl = _urlController.text.trim();
    if (newUrl.isEmpty) return;

    // --- AUTO-FORMATO UX (Igual que en Ajustes) ---
    if (!newUrl.startsWith('http')) {
      if (!newUrl.contains('/')) {
        final isIp =
            RegExp(r'^([0-9]{1,3}\.){3}[0-9]{1,3}$').hasMatch(newUrl) ||
                newUrl == 'localhost';
        if (isIp) {
          newUrl = 'http://$newUrl/Sistema_POS/pos-backend/public/api';
        } else {
          newUrl = 'https://$newUrl/Sistema_POS/pos-backend/public/api';
        }
      } else {
        newUrl = 'http://$newUrl';
      }
    }

    if (newUrl.endsWith('/')) {
      newUrl = newUrl.substring(0, newUrl.length - 1);
    }

    Navigator.of(context).pop(newUrl);
  }

  @override
  Widget build(BuildContext context) {
    return AppModalShell(
      title: 'Configurar Servidor',
      subtitle: 'Conexión a la PC Servidor en la red local',
      icon: Icons.dns_outlined,
      accent: AppModalAccent.blue,
      compact: true,
      maxWidth: 460,
      onClose: () => Navigator.of(context).pop(),
      bodyPadding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No hubo respuesta del servidor configurado tras 3 segundos.\n'
            'Ingrese la IP local de la PC Servidor o use 127.0.0.1 si esta PC es el servidor:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText:
                  'Ej: 192.168.1.50 o http://127.0.0.1/Sistema_POS/pos-backend/public/api',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          if (AppConfig.hasLocalLaragonServer()) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                _urlController.text = AppConfig.kLocalhostLaragonUrl;
              },
              icon: const Icon(Icons.computer, size: 18),
              label: const Text('Usar Servidor Local (127.0.0.1)'),
            ),
          ],
        ],
      ),
      footerActions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save),
          label: const Text('Guardar y Reintentar'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
        ),
      ],
    );
  }
}
