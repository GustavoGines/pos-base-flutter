import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

// Providers
import 'features/settings/presentation/providers/settings_provider.dart';
import 'features/catalog/presentation/providers/catalog_provider.dart';
import 'features/cash_register/presentation/providers/cash_register_provider.dart';
import 'features/pos/presentation/providers/pos_provider.dart';

// Screens
import 'features/cash_register/presentation/pages/cash_register_screen.dart';
import 'features/cash_register/presentation/pages/close_shift_screen.dart';
import 'features/pos/presentation/pages/pos_screen.dart';
import 'features/catalog/presentation/pages/catalog_screen.dart';

// Repositories & DataSources
import 'features/settings/data/datasources/settings_remote_datasource.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/usecases/get_settings_usecase.dart';

import 'features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'features/catalog/data/repositories/catalog_repository_impl.dart';
import 'features/catalog/domain/usecases/get_products_usecase.dart';

import 'features/cash_register/data/datasources/cash_register_remote_datasource.dart';
import 'features/cash_register/data/repositories/cash_register_repository_impl.dart';
import 'features/cash_register/domain/usecases/get_current_shift_usecase.dart';
import 'features/cash_register/domain/usecases/open_shift_usecase.dart';
import 'features/cash_register/domain/usecases/close_shift_usecase.dart';

import 'features/pos/data/datasources/pos_remote_datasource.dart';
import 'features/pos/data/repositories/pos_repository_impl.dart';
import 'features/pos/domain/usecases/process_sale_usecase.dart';
import 'features/pos/domain/usecases/search_products_usecase.dart';

void main() {
  // Inicialización de Dependencias Base (DI)
  const String apiBaseUrl = 'http://127.0.0.1:8000/api';
  final httpClient = http.Client();

  // Settings
  final settingsRepo = SettingsRepositoryImpl(
      remoteDataSource: SettingsRemoteDataSourceImpl(baseUrl: apiBaseUrl, client: httpClient));
  final getSettingsUseCase = GetSettingsUseCase(settingsRepo);

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider(getSettingsUseCase: getSettingsUseCase), lazy: false),
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
        )
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
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final cashRegisterProvider = context.watch<CashRegisterProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    
    if (cashRegisterProvider.isLoading || settingsProvider.isLoading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final shift = cashRegisterProvider.currentShift;
    final bool isShiftOpen = shift != null && shift.isOpen;

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'POS Base - Marca Blanca',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Builder(
        builder: (ctx) {
          if (isShiftOpen) {
            return const PosScreen();
          } else {
            return CashRegisterScreen(
              isLoading: cashRegisterProvider.isLoading,
              errorMessage: cashRegisterProvider.errorMessage,
              onOpenShift: (amount) async {
                final success = await cashRegisterProvider.openShift(amount);
                if (success) {
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
      routes: {
        '/pos': (context) => const PosScreen(),
        '/close-shift': (context) => const CloseShiftScreen(),
        '/catalog': (context) => const CatalogScreen(),
      },
    );
  }
}
