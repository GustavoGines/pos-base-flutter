import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/data/datasources/settings_remote_datasource.dart';
import 'package:frontend_desktop/features/settings/data/models/ecommerce_integration_model.dart';
import 'package:frontend_desktop/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/domain/entities/ecommerce_integration.dart';
import 'package:frontend_desktop/features/settings/presentation/pages/settings_screen.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// --- TEST FAKES ---
class TestAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  bool get isAdmin => true;
  @override
  bool hasPermission(String permission) => true;
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin Ecom', 'role': 'admin'};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get scaleComPort => '';
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => [];
  @override
  int get totalAlertsCount => 0;
  @override
  List<dynamic> get reactiveAlerts => [];
  @override
  List<dynamic> get predictiveCriticalAlerts => [];

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEcommerceSettingsProvider extends ChangeNotifier implements SettingsProvider {
  @override
  int get assignedRegisterId => 1;
  final List<EcommerceIntegration> _integrations;
  final bool _isLoading = false;
  Map<String, dynamic>? _generalIntegrations;

  bool loadCalled = false;
  bool saveCalled = false;
  Map<String, dynamic>? lastSavedPayload;
  int? lastSavedId;
  bool testConnectionCalled = false;
  int? lastTestedId;
  bool toggleActiveCalled = false;
  int? lastToggledId;

  FakeEcommerceSettingsProvider({
    List<EcommerceIntegration>? integrations,
    Map<String, dynamic>? generalIntegrations,
  })  : _integrations = integrations ?? [
          EcommerceIntegration(
            id: 101,
            platform: 'mercadolibre',
            name: 'Mercado Libre',
            clientId: 'MELI_APP_123',
            clientSecret: '****secret_meli',
            isActive: true,
            syncStockEnabled: true,
            autoPauseOnZeroStock: true,
            lastHealthStatus: 'healthy',
          ),
          EcommerceIntegration(
            id: 102,
            platform: 'woocommerce',
            name: 'WooCommerce Store',
            baseUrl: 'https://mi-tienda-woo.com',
            clientId: 'ck_****woo_key',
            clientSecret: '****woo_secret',
            isActive: true,
            syncStockEnabled: true,
            autoPauseOnZeroStock: false,
            lastHealthStatus: 'healthy',
          ),
          EcommerceIntegration(
            id: 103,
            platform: 'tiendanube',
            name: 'Tienda Nube Principal',
            storeId: '987654',
            accessToken: '****tn_token',
            isActive: false,
            syncStockEnabled: true,
            autoPauseOnZeroStock: true,
            lastHealthStatus: 'warning',
          ),
          EcommerceIntegration(
            id: 104,
            platform: 'ecommerce_platform',
            name: 'Plataforma Web Propia',
            baseUrl: 'http://g3.localhost',
            storeId: 'g3',
            accessToken: '****internal_token',
            webhookSecret: '****internal_secret',
            isActive: true,
            syncStockEnabled: true,
            autoPauseOnZeroStock: true,
            lastHealthStatus: 'healthy',
          ),
        ],
        _generalIntegrations = generalIntegrations ?? {
          'ecommerce_enabled': true,
          'mp_qr_enabled': true,
          'afip_enabled': false,
        };

  @override
  List<EcommerceIntegration> get ecommerceIntegrations => _integrations;
  @override
  bool get isLoadingEcommerce => _isLoading;
  @override
  bool get isLoading => false;
  @override
  BusinessSettings? get settings => const BusinessSettings(companyName: 'POS Ecom Testing');
  @override
  String get currentPlan => 'premium';
  @override
  bool get isLicenseActive => true;
  @override
  String get currentApiUrl => 'http://pos-backend.test/api';
  @override
  Map<String, dynamic>? get integrations => _generalIntegrations;
  @override
  bool get isLoadingIntegrations => false;
  @override
  String? get errorMessage => null;
  @override
  List<String> get allowedAddons => [];
  @override
  FeatureFlags get features => const FeatureFlags(fastPos: true, ecommerceSync: true);
  @override
  bool hasFeature(String featureName) => true;

  @override
  EcommerceIntegration? getIntegrationByPlatform(String platform) {
    try {
      return _integrations.firstWhere((e) => e.platform == platform);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<EcommerceIntegration>> loadEcommerceIntegrations({bool isSilent = false}) async {
    loadCalled = true;
    return _integrations;
  }

  @override
  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async {
    return _generalIntegrations;
  }

  @override
  Future<bool> saveIntegrations(Map<String, dynamic> data) async {
    _generalIntegrations = {...?_generalIntegrations, ...data};
    return true;
  }

  @override
  Future<EcommerceIntegration?> saveEcommerceIntegration(Map<String, dynamic> data, {int? id}) async {
    saveCalled = true;
    lastSavedPayload = data;
    lastSavedId = id;
    final platform = data['platform']?.toString() ?? 'mercadolibre';
    final saved = EcommerceIntegration(
      id: id ?? 999,
      platform: platform,
      name: data['name']?.toString() ?? platform,
      baseUrl: data['base_url']?.toString(),
      storeId: data['store_id']?.toString(),
      clientId: data['client_id']?.toString(),
      clientSecret: data['client_secret']?.toString(),
      accessToken: data['access_token']?.toString(),
      isActive: data['is_active'] == true,
      syncStockEnabled: data['sync_stock_enabled'] == true,
      autoPauseOnZeroStock: data['auto_pause_on_zero_stock'] == true,
      lastHealthStatus: 'healthy',
    );
    final idx = _integrations.indexWhere((e) => e.platform == platform);
    if (idx >= 0) {
      _integrations[idx] = saved;
    } else {
      _integrations.add(saved);
    }
    notifyListeners();
    return saved;
  }

  @override
  Future<Map<String, dynamic>> testEcommerceConnection(int id) async {
    testConnectionCalled = true;
    lastTestedId = id;
    return {
      'success': true,
      'message': 'Diagnóstico exitoso: Conexión establecida con la tienda virtual.',
    };
  }

  @override
  Future<EcommerceIntegration?> toggleEcommerceActive(int id) async {
    toggleActiveCalled = true;
    lastToggledId = id;
    final idx = _integrations.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      final current = _integrations[idx];
      final updated = current.copyWith(isActive: !current.isActive);
      _integrations[idx] = updated;
      notifyListeners();
      return updated;
    }
    return null;
  }

  bool importCatalogCalled = false;
  bool exportCatalogCalled = false;

  @override
  Future<Map<String, dynamic>> importEcommerceCatalog(int id) async {
    importCatalogCalled = true;
    return {
      'success': true,
      'total_remote': 5,
      'imported': 4,
      'updated': 1,
      'mapped': 5,
    };
  }

  @override
  Future<Map<String, dynamic>> exportEcommerceCatalog(int id) async {
    exportCatalogCalled = true;
    return {
      'success': true,
      'exported_count': 10,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-ecom',
      'pos_api': 'http://pos-backend.test/api',
      'backend_install_path': r'C:\laragon\www\Sistema_POS\pos-backend',
      'update_channel': 'stable',
    });
    PackageInfo.setMockInitialValues(
      appName: 'POS Ecom Test',
      packageName: 'com.example.pos',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 1. ENTITY & MODEL TESTS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  group('E-Commerce Entity & Model Unit Tests', () {
    test('EcommerceIntegration entity properties and copyWith', () {
      final entity = EcommerceIntegration(
        id: 1,
        platform: 'mercadolibre',
        name: 'Meli Oficial',
        clientId: 'APP_123',
        clientSecret: 'SEC_456',
        isActive: true,
        syncStockEnabled: true,
        autoPauseOnZeroStock: false,
        lastHealthStatus: 'healthy',
        hasClientSecret: true,
      );

      expect(entity.id, equals(1));
      expect(entity.platform, equals('mercadolibre'));
      expect(entity.isHealthy, isTrue);
      expect(entity.hasClientSecret, isTrue);
      expect(entity.hasAccessToken, isFalse);

      final updated = entity.copyWith(
        isActive: false,
        lastHealthStatus: 'error',
      );
      expect(updated.isActive, isFalse);
      expect(updated.lastHealthStatus, equals('error'));
      expect(updated.isHealthy, isFalse);
      expect(updated.clientId, equals('APP_123'));
    });

    test('EcommerceIntegrationModel.fromJson parses varied JSON schemas correctly', () {
      final json = {
        'id': 42,
        'platform': 'woocommerce',
        'name': 'Mi Tienda Woo',
        'store_id': null,
        'base_url': 'https://example.com',
        'client_id': 'ck_test',
        'client_secret': '****secret',
        'access_token': null,
        'is_active': 1,
        'sync_stock_enabled': '1',
        'sync_price_enabled': true,
        'auto_pause_on_zero_stock': 0,
        'rate_limit_per_minute': '60',
        'batch_size': 50,
        'timeout_seconds': 30,
        'settings': {'custom_meta': 'value'},
        'last_health_status': 'healthy',
        'consecutive_failures': 0,
        'has_client_secret': true,
        'has_access_token': false,
      };

      final model = EcommerceIntegrationModel.fromJson(json);

      expect(model.id, equals(42));
      expect(model.platform, equals('woocommerce'));
      expect(model.baseUrl, equals('https://example.com'));
      expect(model.isActive, isTrue);
      expect(model.syncStockEnabled, isTrue);
      expect(model.syncPriceEnabled, isTrue);
      expect(model.autoPauseOnZeroStock, isFalse);
      expect(model.rateLimitPerMinute, equals(60));
      expect(model.batchSize, equals(50));
      expect(model.timeoutSeconds, equals(30));
      expect(model.settings?['custom_meta'], equals('value'));
      expect(model.lastHealthStatus, equals('healthy'));
    });

    test('EcommerceIntegrationModel.toJson produces standard backend payload', () {
      final model = EcommerceIntegrationModel(
        id: 10,
        platform: 'tiendanube',
        name: 'Tienda Nube Tienda',
        storeId: '54321',
        accessToken: 'token_secret_123',
        isActive: true,
        syncStockEnabled: true,
        autoPauseOnZeroStock: true,
      );

      final json = model.toJson();

      expect(json['platform'], equals('tiendanube'));
      expect(json['name'], equals('Tienda Nube Tienda'));
      expect(json['store_id'], equals('54321'));
      expect(json['access_token'], equals('token_secret_123'));
      expect(json['is_active'], isTrue);
      expect(json['sync_stock_enabled'], isTrue);
      expect(json['auto_pause_on_zero_stock'], isTrue);
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 2. REMOTE DATASOURCE & REPOSITORY TESTS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  group('E-Commerce Remote DataSource & Repository Unit Tests', () {
    test('fetchEcommerceIntegrations sends GET /ecommerce/integrations and parses list', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('GET'));
        expect(request.url.path, endsWith('/ecommerce/integrations'));
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'platform': 'mercadolibre',
              'name': 'Mercado Libre',
              'is_active': true,
              'sync_stock_enabled': true,
              'auto_pause_on_zero_stock': true,
            },
            {
              'id': 2,
              'platform': 'woocommerce',
              'name': 'WooCommerce',
              'is_active': false,
              'sync_stock_enabled': false,
              'auto_pause_on_zero_stock': false,
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: ds);

      final results = await repo.getEcommerceIntegrations();
      expect(results.length, equals(2));
      expect(results[0].platform, equals('mercadolibre'));
      expect(results[0].isActive, isTrue);
      expect(results[1].platform, equals('woocommerce'));
      expect(results[1].isActive, isFalse);
    });

    test('createEcommerceIntegration sends POST /ecommerce/integrations', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, endsWith('/ecommerce/integrations'));
        final body = jsonDecode(request.body);
        expect(body['platform'], equals('mercadolibre'));
        expect(body['client_id'], equals('APP_TEST'));
        return http.Response(
          jsonEncode({
            'id': 5,
            'platform': 'mercadolibre',
            'name': 'Mercado Libre',
            'client_id': 'APP_TEST',
            'is_active': true,
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: ds);

      final result = await repo.createEcommerceIntegration({
        'platform': 'mercadolibre',
        'name': 'Mercado Libre',
        'client_id': 'APP_TEST',
        'is_active': true,
      });

      expect(result.id, equals(5));
      expect(result.clientId, equals('APP_TEST'));
    });

    test('testEcommerceConnection sends POST /ecommerce/integrations/{id}/test-connection', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, endsWith('/ecommerce/integrations/7/test-connection'));
        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'Autenticación con WooCommerce exitosa (v3 API)',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: ds);

      final result = await repo.testEcommerceConnection(7);
      expect(result['success'], isTrue);
      expect(result['message'], contains('WooCommerce'));
    });

    test('toggleEcommerceActive sends POST /ecommerce/integrations/{id}/toggle-active', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, endsWith('/ecommerce/integrations/9/toggle-active'));
        return http.Response(
          jsonEncode({
            'id': 9,
            'platform': 'tiendanube',
            'name': 'Tienda Nube',
            'is_active': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: ds);

      final result = await repo.toggleEcommerceActive(9);
      expect(result.id, equals(9));
      expect(result.isActive, isTrue);
    });

    test('importEcommerceCatalog sends POST /ecommerce/integrations/{id}/import-catalog', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, endsWith('/ecommerce/integrations/7/import-catalog'));
        return http.Response(
          jsonEncode({
            'success': true,
            'total_remote': 5,
            'imported': 3,
            'updated': 2,
            'mapped': 5,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: ds);

      final result = await repo.importEcommerceCatalog(7);
      expect(result['success'], isTrue);
      expect(result['imported'], equals(3));
      expect(result['mapped'], equals(5));
    });

    test('exportEcommerceCatalog sends POST /ecommerce/integrations/{id}/export-catalog', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, endsWith('/ecommerce/integrations/7/export-catalog'));
        return http.Response(
          jsonEncode({
            'success': true,
            'exported_count': 12,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final ds = SettingsRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: ds);

      final result = await repo.exportEcommerceCatalog(7);
      expect(result['success'], isTrue);
      expect(result['exported_count'], equals(12));
    });
  });

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // 3. SETTINGS SCREEN WIDGET TESTS (E-COMMERCE UI)
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  group('SettingsScreen E-Commerce Widget UI Tests', () {
    Widget buildApp({required FakeEcommerceSettingsProvider provider}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: provider),
          ChangeNotifierProvider<AuthProvider>.value(value: TestAuthProvider()),
          ChangeNotifierProvider<LocalTerminalProvider>.value(value: TestTerminalProvider()),
          ChangeNotifierProvider<InventoryAlertsProvider>.value(value: TestAlertsProvider()),
        ],
        child: const MaterialApp(
          home: SettingsScreen(),
        ),
      );
    }

    testWidgets('Integraciones tab renders Mercado Libre, WooCommerce, and Tienda Nube sections', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = FakeEcommerceSettingsProvider();

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Integraciones
      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // E-commerce card title
      final ecomHeader = find.text('E-Commerce y Omnicanalidad');
      expect(ecomHeader, findsOneWidget);

      // Expand E-Commerce card
      await tester.ensureVisible(ecomHeader);
      await tester.tap(ecomHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Verify sections are present
      expect(find.text('Mercado Libre'), findsWidgets);
      expect(find.text('WooCommerce'), findsWidgets);
      expect(find.text('Tienda Nube'), findsWidgets);

      // Expand sub-accordions to reveal fields
      final meliHeader = find.text('Mercado Libre').first;
      await tester.ensureVisible(meliHeader);
      await tester.tap(meliHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final wooHeader = find.text('WooCommerce').first;
      await tester.ensureVisible(wooHeader);
      await tester.tap(wooHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final tnHeader = find.text('Tienda Nube').first;
      await tester.ensureVisible(tnHeader);
      await tester.tap(tnHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final internalHeader = find.text('Plataforma Web Propia (Ecommerce-Platform)').first;
      await tester.ensureVisible(internalHeader);
      await tester.tap(internalHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Verify fields
      expect(find.byKey(const ValueKey('field_meli_id')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_meli_secret')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_woo_url')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_woo_key')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_woo_secret')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_tiendanube_store_id')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_tiendanube_token')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_internal_url')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_internal_store_id')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_internal_token')), findsOneWidget);
      expect(find.byKey(const ValueKey('field_internal_secret')), findsOneWidget);
    });

    testWidgets('Connection testing button triggers testEcommerceConnection and displays SnackBar feedback', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = FakeEcommerceSettingsProvider();

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand E-Commerce card
      final ecomHeader = find.text('E-Commerce y Omnicanalidad');
      await tester.ensureVisible(ecomHeader);
      await tester.tap(ecomHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand Mercado Libre sub-accordion
      await tester.tap(find.text('Mercado Libre').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Find "Probar Conexión" for Mercado Libre
      final testMeliBtn = find.byKey(const ValueKey('btn_test_meli_connection'));
      await tester.ensureVisible(testMeliBtn);
      await tester.tap(testMeliBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(provider.testConnectionCalled, isTrue);
      expect(provider.lastTestedId, equals(101));
      expect(find.textContaining('Diagnóstico exitoso'), findsOneWidget);
    });

    testWidgets('Active switch invokes toggleEcommerceActive', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = FakeEcommerceSettingsProvider();

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand E-Commerce card
      final ecomHeader = find.text('E-Commerce y Omnicanalidad');
      await tester.ensureVisible(ecomHeader);
      await tester.tap(ecomHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Find switch for Mercado Libre
      final meliSwitch = find.byKey(const ValueKey('switch_meli_active'));
      await tester.ensureVisible(meliSwitch);
      await tester.tap(meliSwitch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(provider.toggleActiveCalled, isTrue);
      expect(provider.lastToggledId, equals(101));
    });

    testWidgets('Preserves masked **** secrets when saving integration without changes', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = FakeEcommerceSettingsProvider();

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand E-Commerce card
      final ecomHeader = find.text('E-Commerce y Omnicanalidad');
      await tester.ensureVisible(ecomHeader);
      await tester.tap(ecomHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand Mercado Libre sub-accordion
      await tester.tap(find.text('Mercado Libre').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Click "Guardar Mercado Libre" without modifying the masked secret
      final saveMeliBtn = find.byKey(const ValueKey('btn_save_meli'));
      await tester.ensureVisible(saveMeliBtn);
      await tester.tap(saveMeliBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(provider.saveCalled, isTrue);
      expect(provider.lastSavedPayload?['platform'], equals('mercadolibre'));
      // Masked secret was preserved
      expect(provider.lastSavedPayload?['client_secret'], equals('****secret_meli'));
    });

    testWidgets('Plataforma Web Propia testing button triggers testEcommerceConnection', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = FakeEcommerceSettingsProvider();

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand E-Commerce card
      final ecomHeader = find.text('E-Commerce y Omnicanalidad');
      await tester.ensureVisible(ecomHeader);
      await tester.tap(ecomHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand Plataforma Web Propia sub-accordion
      final webHeader = find.text('Plataforma Web Propia (Ecommerce-Platform)').first;
      await tester.ensureVisible(webHeader);
      await tester.tap(webHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Tap "Probar Conexión"
      final testWebBtn = find.byKey(const ValueKey('btn_test_internal_connection'));
      await tester.ensureVisible(testWebBtn);
      await tester.tap(testWebBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(provider.testConnectionCalled, isTrue);
      expect(provider.lastTestedId, equals(104));
    });

    testWidgets('Zero RenderFlex overflow on narrow mobile screen (320x480)', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final provider = FakeEcommerceSettingsProvider();

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Select Integraciones compact chip
      final chip = find.widgetWithText(ChoiceChip, 'Integraciones');
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Assert zero exceptions / overflows
      expect(tester.takeException(), isNull);
      expect(find.text('E-Commerce y Omnicanalidad'), findsOneWidget);
    });

    testWidgets('Plataforma Web Propia renders catalog import and export buttons', (tester) async {
      final provider = FakeEcommerceSettingsProvider();

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand E-Commerce card
      final ecomHeader = find.text('E-Commerce y Omnicanalidad');
      await tester.ensureVisible(ecomHeader);
      await tester.tap(ecomHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand Plataforma Web Propia sub-accordion
      final webHeader = find.text('Plataforma Web Propia (Ecommerce-Platform)').first;
      await tester.ensureVisible(webHeader);
      await tester.tap(webHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const ValueKey('btn_import_internal_catalog')), findsOneWidget);
      expect(find.byKey(const ValueKey('btn_export_internal_catalog')), findsOneWidget);
    });

    testWidgets('Unconfigured ecommerce channels are displayed as Inactive by default', (tester) async {
      final provider = FakeEcommerceSettingsProvider(integrations: []);

      await tester.pumpWidget(buildApp(provider: provider));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Integraciones'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Expand E-Commerce card
      final ecomHeader = find.text('E-Commerce y Omnicanalidad');
      await tester.ensureVisible(ecomHeader);
      await tester.tap(ecomHeader);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Mercado Libre switch must be false
      final meliSwitch = tester.widget<Switch>(find.byKey(const ValueKey('switch_meli_active')));
      expect(meliSwitch.value, isFalse);

      // WooCommerce switch must be false
      final wooSwitch = tester.widget<Switch>(find.byKey(const ValueKey('switch_woo_active')));
      expect(wooSwitch.value, isFalse);

      // Tienda Nube switch must be false
      final tnSwitch = tester.widget<Switch>(find.byKey(const ValueKey('switch_tiendanube_active')));
      expect(tnSwitch.value, isFalse);

      // Tapping unconfigured switch keeps it false
      await tester.tap(find.byKey(const ValueKey('switch_meli_active')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final meliSwitchAfter = tester.widget<Switch>(find.byKey(const ValueKey('switch_meli_active')));
      expect(meliSwitchAfter.value, isFalse);
    });
  });
}
