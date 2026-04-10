import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Providers
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/catalog/presentation/providers/catalog_provider.dart';
import 'features/cash_register/presentation/providers/cash_register_provider.dart';
import 'features/pos/presentation/providers/pos_provider.dart';
import 'features/sales_history/presentation/providers/sales_history_provider.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/customers/providers/customer_provider.dart';
import 'features/trash/providers/trash_provider.dart';
import 'core/config/app_config.dart';

import 'core/presentation/widgets/license_guard.dart';
import 'core/presentation/widgets/plan_upgrade_dialog.dart';
import 'core/network/api_client.dart';
import 'core/utils/receipt_printer_service.dart';

// Screens
import 'features/settings/presentation/pages/settings_screen.dart';
import 'features/cash_register/presentation/pages/cash_register_management_screen.dart';
import 'features/pos/presentation/pages/pos_screen.dart';
import 'features/catalog/presentation/pages/catalog_screen.dart';
import 'features/cash_register/presentation/pages/cash_register_screen.dart';
import 'features/cash_register/presentation/pages/close_shift_screen.dart';
import 'features/sales_history/presentation/pages/sales_history_screen.dart';
import 'features/auth/presentation/pages/login_screen.dart';
import 'features/cash_register/presentation/pages/shift_audit_screen.dart';
import 'features/customers/presentation/screens/customers_screen.dart';
import 'features/trash/presentation/screens/trash_screen.dart';
// [hardware_store] Módulo Presupuestos
import 'features/quotes/presentation/pages/quote_screen.dart';
import 'features/quotes/presentation/providers/quote_provider.dart';
import 'features/quotes/data/quote_repository.dart';

// Repositories & DataSources
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
    return FadeTransition(opacity: animation, child: child);
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
      // Context might be unmounted during startup — silently ignore.
    }
  }

  @override
  void didPush(Route route, Route? previousRoute) => _refresh(route);

  @override
  void didPop(Route route, Route? previousRoute) => _refresh(previousRoute);

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _refresh(newRoute);
}

void main() async {
  // CRÍTICO: Inicialización obligatoria para assets y plugins en desktop
  WidgetsFlutterBinding.ensureInitialized();
  
  // Pre-cargar perfil de impresora para evitar crashes de AssetManifest en Windows
  await ReceiptPrinterService.instance.initialize();
  
  // Obtener URL de la API del almacenamiento local
  final prefs = await SharedPreferences.getInstance();
  final savedApiUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;

  // Inicialización de Dependencias Base (DI)
  final String apiUrl = savedApiUrl;
  final httpClient = ApiClient(http.Client());

  // Auth — creado ANTES de runApp para poder restaurar el token de sesión
  // antes del primer request HTTP (Crash Recovery de la Vulnerabilidad #3)
  final authRepo = AuthRepository(
      remoteDataSource: AuthRemoteDataSource(baseUrl: apiUrl, client: httpClient));
  final authProvider = AuthProvider(repository: authRepo)
    ..apiClient = httpClient; // Inyección sin dependencia circular
  await authProvider.restoreSessionFromPrefs();

   // Settings
  final settingsRepo = SettingsRepositoryImpl(
      remoteDataSource: SettingsRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));
  final getSettingsUseCase = GetSettingsUseCase(settingsRepo);
  final updateSettingsUseCase = UpdateSettingsUseCase(settingsRepo);

  // Catalog
  final catalogRepo = CatalogRepositoryImpl(
      remoteDataSource: CatalogRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));
  final getProductsUseCase = GetProductsUseCase(catalogRepo);

  // Cash Register
  final cashRegisterRepo = CashRegisterRepositoryImpl(
      remoteDataSource: CashRegisterRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));
  
  // Pos
  final posRepo = PosRepositoryImpl(
      remoteDataSource: PosRemoteDataSourceImpl(baseUrl: apiUrl, client: httpClient));

  // Sales History
  final salesHistoryDataSource = SalesHistoryRemoteDataSource(
      baseUrl: apiUrl, client: httpClient);

  // Auth — ya instanciado antes de runApp (ver arriba con restoreSessionFromPrefs)

  // Users
  final usersRepo = UsersRepository(
      dataSource: UsersRemoteDataSource(baseUrl: apiUrl, client: httpClient));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: authProvider, // Reusar la instancia creada antes de runApp
        ),
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(
            getSettingsUseCase: getSettingsUseCase,
            updateSettingsUseCase: updateSettingsUseCase,
          ), 
          lazy: false
        ),
        ChangeNotifierProvider(create: (_) => SalesHistoryProvider(dataSource: salesHistoryDataSource), lazy: false),
        ChangeNotifierProvider(create: (_) => CatalogProvider(
          getProductsUseCase: getProductsUseCase,
          repository: catalogRepo,
        ), lazy: false),
        ChangeNotifierProvider(
          create: (_) => CashRegisterProvider(
            getCurrentShiftUseCase: GetCurrentShiftUseCase(cashRegisterRepo),
            getAllShiftsUseCase: GetAllShiftsUseCase(cashRegisterRepo),
            openShiftUseCase: OpenShiftUseCase(cashRegisterRepo),
            closeShiftUseCase: CloseShiftUseCase(cashRegisterRepo),
            getRegistersUseCase: GetRegistersUseCase(cashRegisterRepo),
          ),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => PosProvider(
            processSaleUseCase: ProcessSaleUseCase(posRepo),
            searchProductsUseCase: SearchProductsUseCase(posRepo),
            repository: posRepo,
          ),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => UsersProvider(repository: usersRepo),
          lazy: true,  // Solo carga cuando se navega a Personal y Accesos
        ),
        ChangeNotifierProxyProvider<SettingsProvider, CustomerProvider>(
          create: (_) => CustomerProvider(baseUrl: apiUrl),
          update: (_, settingsProvider, customerProvider) {
            customerProvider!.setAccess(settingsProvider.hasFeature('cuentas_corrientes'));
            return customerProvider;
          },
          lazy: false,
        ),
        ChangeNotifierProvider(create: (_) => TrashProvider(baseUrl: apiUrl), lazy: false),
        // [hardware_store] Presupuestos
        ChangeNotifierProvider(
          create: (_) => QuoteProvider(
            repository: QuoteRepository(baseUrl: apiUrl, client: httpClient),
          ),
          lazy: true,
        ),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool _isInitializing = true;
  String? _initError;
  int _retryCount = 0;
  static const int _maxRetries = 5;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    // 1. Cargar Settings del negocio con lógica de reintento para Render Cold Start
    bool success = false;
    while (!success && _retryCount <= _maxRetries) {
      try {
        await settingsProvider.loadSettings();
        success = true;
      } catch (e) {
        final prefs = await SharedPreferences.getInstance();
        final currentUrl = prefs.getString('pos_api') ?? AppConfig.kApiBaseUrl;

        // Auto-fix: Si estamos en localhost 8000 y falla, probar con Laragon (puerto 80) una vez
        if (_retryCount == 0 && currentUrl.contains(':8000')) {
          await prefs.setString('pos_api', AppConfig.kApiBaseUrl);
          settingsProvider.updateBaseUrl(AppConfig.kApiBaseUrl);
          continue; // Intento inmediato con la nueva URL
        }

        if (_retryCount < _maxRetries) {
          _retryCount++;
          setState(() {
            _initError = 'El servidor está despertando. Reintento $_retryCount de $_maxRetries...';
          });
          await Future.delayed(const Duration(seconds: 30));
        } else {
          setState(() {
            _isInitializing = false;
            _initError = 'No se pudo conectar tras varios intentos. Verifique si Laragon está iniciado o si el servidor de licencias en Render está activo.';
          });
          return; // Abortar resto de la carga
        }
      }
    }

    if (!success) return;

    // 2. Verificar estado de la Caja de ESTA terminal física asignada
    try {
      final assignedRegisterId = settingsProvider.assignedRegisterId;
      await Provider.of<CashRegisterProvider>(context, listen: false)
          .checkCurrentShift(registerId: assignedRegisterId > 0 ? assignedRegisterId : null);
    } catch (_) {
      // Si falla obtener el turno, no bloqueamos la app pero registramos el error
      debugPrint('Error al cargar turno inicial');
    }
    
    if (mounted) {
      setState(() {
        _isInitializing = false;
        _initError = null;
      });
    }
  }

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final ValueNotifier<String?> _currentRoute = ValueNotifier<String?>(null);

  Widget _buildLoadingOrErrorScreen() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1E2D45),
        body: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.point_of_sale_rounded, size: 72, color: Color(0xFF3B82F6)),
                const SizedBox(height: 24),
                const Text('Sistema POS', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                Text(_initError != null ? 'ESTADO: $_initError' : 'Iniciando sistema...', 
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.white54)),
                const SizedBox(height: 32),
                if (_initError != null && _retryCount >= _maxRetries) ...[
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      _retryCount = 0;
                      _initializeApp();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar Conexión'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () async {
                      // Abrir mini-dialog manual para corregir URL (si falla Laragon)
                      if (!mounted) return;
                      // Aquí podrías implementar un modal simple si fuera necesario corregir la URL a mano
                    },
                    icon: const Icon(Icons.settings_ethernet, color: Colors.white70),
                    label: const Text('Ajustes de Red', style: TextStyle(color: Colors.white70)),
                  ),
                ] else
                  const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(color: Color(0xFF3B82F6), strokeWidth: 3),
                  ),
              ],
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
        LicenseRefreshObserver(() => navigatorKey.currentContext!, _currentRoute),
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
            const double minAppWidth = 1024.0;
            const double minAppHeight = 550.0;

            final bool needsHorizontalScroll = constraints.maxWidth < minAppWidth;
            final bool needsVerticalScroll = constraints.maxHeight < minAppHeight;

            if (!needsHorizontalScroll && !needsVerticalScroll) {
              return guardedChild;
            }

            Widget content = SizedBox(
              width: needsHorizontalScroll ? minAppWidth : constraints.maxWidth,
              height: needsVerticalScroll ? minAppHeight : constraints.maxHeight,
              child: guardedChild,
            );

            if (needsVerticalScroll) {
              content = SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: content,
              );
            }

            if (needsHorizontalScroll) {
              content = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: content,
              );
            }

            return content;
          },
        );
      },
      debugShowCheckedModeBanner: false,
      title: 'Sistema POS',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.windows: FadePageRouteTransitionsBuilder(),
            TargetPlatform.linux: FadePageRouteTransitionsBuilder(),
            TargetPlatform.macOS: FadePageRouteTransitionsBuilder(),
          },
        ),
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => Consumer<CashRegisterProvider>(
          builder: (ctx, cashProv, _) {
            final shift = cashProv.currentShift;
            final bool open = shift != null && shift.isOpen;
            if (open) {
              return const PosScreen();
            } else {
              return CashRegisterScreen(
                isLoading: cashProv.isLoading,
                errorMessage: cashProv.errorMessage,
                onOpenShift: (amount, registerId) async {
                  final userId = ctx.read<AuthProvider>().currentUser?['id'] ?? 1;
                  final success = await cashProv.openShift(amount, userId, registerId);
                  if (success) {
                    // Usamos navigatorKey para evitar contexto desactivado en callback async
                    navigatorKey.currentState?.pushReplacementNamed('/pos');
                  } else {
                    final rawError = cashProv.errorMessage ?? '';
                    final msg = rawError.replaceAll('Exception: ', '');

                    // Detectar error de límite de plan → mostrar modal de upselling
                    final isPlanLimitError = rawError.contains('Límite de cajas') ||
                        rawError.contains('plan a PRO') ||
                        rawError.contains('Actualice su plan');

                    if (isPlanLimitError && ctx.mounted) {
                      PlanUpgradeDialog.show(
                        ctx,
                        featureName: 'Múltiples Cajas Simultáneas',
                        description:
                            'Su plan actual permite 1 caja activa a la vez. '
                            'Para operar con varias terminales simultáneamente '
                            'es necesario el Plan PRO o Enterprise.\n\n'
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
            }
          },
        ),
        '/pos': (context) => const PosScreen(),
        '/close-shift': (context) => const CloseShiftScreen(),
        '/catalog': (context) => const CatalogScreen(),
        '/sales-history': (context) => const SalesHistoryScreen(),
        '/shift-audit': (context) => const ShiftAuditScreen(),
        '/users': (context) => const UsersManagerScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/settings/registers': (context) => const CashRegisterManagementScreen(),
        '/cuentas-corrientes': (context) => const CustomersScreen(),
        '/trash': (context) => const TrashScreen(),
        // [hardware_store]
        '/quotes': (context) => const QuoteScreen(),
      },
    );
  }
}
