import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

// Providers
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/catalog/presentation/providers/catalog_provider.dart';
import 'features/cash_register/presentation/providers/cash_register_provider.dart';
import 'features/pos/presentation/providers/pos_provider.dart';
import 'features/sales_history/presentation/providers/sales_history_provider.dart';
import 'features/auth/presentation/providers/auth_provider.dart';

// Screens
import 'features/settings/presentation/pages/settings_screen.dart';
import 'features/pos/presentation/pages/pos_screen.dart';
import 'features/catalog/presentation/pages/catalog_screen.dart';
import 'features/cash_register/presentation/pages/cash_register_screen.dart';
import 'features/cash_register/presentation/pages/close_shift_screen.dart';
import 'features/sales_history/presentation/pages/sales_history_screen.dart';
import 'features/auth/presentation/pages/login_screen.dart';

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
import 'features/cash_register/domain/usecases/open_shift_usecase.dart';
import 'features/cash_register/domain/usecases/get_current_shift_usecase.dart';
import 'features/cash_register/domain/usecases/close_shift_usecase.dart';

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

void main() {
  // Inicialización de Dependencias Base (DI)
  const String apiBaseUrl = 'http://127.0.0.1:8000/api';
  final httpClient = http.Client();

  // Settings
  final settingsRepo = SettingsRepositoryImpl(
      remoteDataSource: SettingsRemoteDataSourceImpl(baseUrl: apiBaseUrl, client: httpClient));
  final getSettingsUseCase = GetSettingsUseCase(settingsRepo);
  final updateSettingsUseCase = UpdateSettingsUseCase(settingsRepo);

  // Catalog
  final catalogRepo = CatalogRepositoryImpl(
      remoteDataSource: CatalogRemoteDataSourceImpl(baseUrl: apiBaseUrl, client: httpClient));
  final getProductsUseCase = GetProductsUseCase(catalogRepo);

  // Cash Register
  final cashRegisterRepo = CashRegisterRepositoryImpl(
      remoteDataSource: CashRegisterRemoteDataSourceImpl(baseUrl: apiBaseUrl, client: httpClient));
  
  // Pos
  final posRepo = PosRepositoryImpl(
      remoteDataSource: PosRemoteDataSourceImpl(baseUrl: apiBaseUrl, client: httpClient));

  // Sales History
  final salesHistoryDataSource = SalesHistoryRemoteDataSource(
      baseUrl: apiBaseUrl, client: httpClient);

  // Auth
  final authRepo = AuthRepository(
      remoteDataSource: AuthRemoteDataSource(baseUrl: apiBaseUrl, client: httpClient));

  // Users
  final usersRepo = UsersRepository(
      dataSource: UsersRemoteDataSource(baseUrl: apiBaseUrl, client: httpClient));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(repository: authRepo),
          lazy: false,
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
            openShiftUseCase: OpenShiftUseCase(cashRegisterRepo),
            closeShiftUseCase: CloseShiftUseCase(cashRegisterRepo)
          ),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => PosProvider(
            processSaleUseCase: ProcessSaleUseCase(posRepo),
            searchProductsUseCase: SearchProductsUseCase(posRepo)
          ),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) => UsersProvider(repository: usersRepo),
          lazy: true,  // Solo carga cuando se navega a Personal y Accesos
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
  // Estado de carga inicial
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _initializeApp();
    });
  }

  Future<void> _initializeApp() async {
    // 1. Cargar Settings del negocio
    await Provider.of<SettingsProvider>(context, listen: false).loadSettings();
    // 2. Verificar estado de la Caja
    await Provider.of<CashRegisterProvider>(context, listen: false).checkCurrentShift();
    
    if (mounted) {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFF1E2D45),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.point_of_sale_rounded, size: 72, color: Color(0xFF3B82F6)),
                const SizedBox(height: 24),
                const Text('POS Base', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 8),
                const Text('Iniciando sistema...', style: TextStyle(fontSize: 14, color: Colors.white54)),
                const SizedBox(height: 32),
                const SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(color: Color(0xFF3B82F6), strokeWidth: 3),
                ),
              ],
            ),
          ),
        ),
      );
    }


    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'POS Base - Marca Blanca',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
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
                onOpenShift: (amount) async {
                  final success = await cashProv.openShift(amount);
                  if (success) {
                    // Usamos navigatorKey para evitar contexto desactivado en callback async
                    navigatorKey.currentState?.pushReplacementNamed('/pos');
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
        '/users': (context) => const UsersManagerScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
