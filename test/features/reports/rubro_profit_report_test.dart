import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/checks/domain/entities/third_party_check.dart';
import 'package:frontend_desktop/features/checks/presentation/providers/check_provider.dart';
import 'package:frontend_desktop/features/reports/data/datasources/reports_remote_datasource.dart';
import 'package:frontend_desktop/features/reports/presentation/pages/reports_screen.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/reports_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/rubro_profit_report_view.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  FakeSettingsProvider({required BusinessSettings settings}) : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;
  @override
  String get currentPlan => _settings.licensePlanType ?? 'basic';
  @override
  FeatureFlags get features => _settings.features;
  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCheckProvider extends ChangeNotifier implements CheckProvider {
  @override
  List<ThirdPartyCheck> get checks => [];
  @override
  Future<void> loadChecks() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalTerminalProvider extends ChangeNotifier implements LocalTerminalProvider {
  @override
  String get printerFormat => 'thermal_80';
  @override
  String get printerConnection => 'none';
  @override
  String get pdfPaperSize => 'a4';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Admin User', 'role': 'admin'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryAlertsProvider extends ChangeNotifier implements InventoryAlertsProvider {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'pos_api': 'http://localhost/api'});
  });

  final sampleRubroData = {
    'start_date': '2026-10-01',
    'end_date': '2026-10-31',
    'previous_period': {
      'start_date': '2026-09-01',
      'end_date': '2026-09-30',
      'revenue': 8000.0,
      'profit': 3000.0,
    },
    'daily_evolution': [],
    'data': [
      {
        'category_name': 'Ferretería',
        'rubro_name': 'Ferretería',
        'rubro_id': 1,
        'items_sold': 50,
        'total_revenue': 10000.0,
        'total_profit': 4000.0,
        'revenue_with_cost': 10000.0,
        'items_with_cost': 50,
        'total_items': 50,
        'products': [
          {
            'product_id': 101,
            'product_name': 'Martillo Pro',
            'items_sold': 20,
            'total_revenue': 4000.0,
            'total_profit': 1600.0,
          },
          {
            'product_id': 102,
            'product_name': 'Taladro Percutor',
            'items_sold': 30,
            'total_revenue': 6000.0,
            'total_profit': 2400.0,
          },
        ],
      },
      {
        'category_name': 'Pinturería',
        'rubro_name': 'Pinturería',
        'rubro_id': 2,
        'items_sold': 30,
        'total_revenue': 6000.0,
        'total_profit': 2500.0,
        'revenue_with_cost': 6000.0,
        'items_with_cost': 30,
        'total_items': 30,
        'products': [
          {
            'product_id': 201,
            'product_name': 'Látex Interior 20L',
            'items_sold': 30,
            'total_revenue': 6000.0,
            'total_profit': 2500.0,
          },
        ],
      },
    ],
  };

  group('ReportsRemoteDataSource & ReportsProvider Unit Tests', () {
    test('getProfitByRubro sends correct query and parses response', () async {
      String? requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final result = await dataSource.getProfitByRubro('2026-10-01', '2026-10-31');

      expect(requestedUrl, contains('/reports/sales-by-rubro'));
      expect(requestedUrl, contains('start_date=2026-10-01'));
      expect(requestedUrl, contains('end_date=2026-10-31'));
      expect(result['data'], isNotEmpty);
      expect(result['data'].length, 2);
    });

    test('getProfitByRubro forwards single and multiple rubro filters', () async {
      String? singleUrl;
      String? multiUrl;

      final mockClient = MockClient((request) async {
        if (request.url.query.contains('rubro_ids=')) {
          multiUrl = request.url.toString();
        } else {
          singleUrl = request.url.toString();
        }
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);

      await dataSource.getProfitByRubro('2026-10-01', '2026-10-31', rubroFilter: 5);
      expect(singleUrl, contains('rubro_id=5'));

      await dataSource.getProfitByRubro('2026-10-01', '2026-10-31', rubroFilter: [1, 2]);
      expect(multiUrl, contains('rubro_ids=1,2'));
    });

    test('downloadRubroExcel and downloadRubroPdf fetch binary bytes', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes([1, 2, 3, 4], 200);
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final excelBytes = await dataSource.downloadRubroExcel('2026-10-01', '2026-10-31');
      expect(excelBytes, [1, 2, 3, 4]);

      final pdfBytes = await dataSource.downloadRubroPdf('2026-10-01', '2026-10-31');
      expect(pdfBytes, [1, 2, 3, 4]);
    });

    test('ReportsProvider calculates rubro metrics correctly', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await provider.fetchProfitByRubro();

      expect(provider.rubroReportData.length, 2);
      expect(provider.rubroTotalRevenue, 16000.0);
      expect(provider.rubroTotalProfit, 6500.0);
      expect(provider.rubroTotalItemsSold, 80);
      expect(provider.rubroMarginPercentage, closeTo(40.625, 0.01));
    });

    test('ReportsProvider clears rubro filter when explicitly passing null', () async {
      String? lastUrl;
      final mockClient = MockClient((request) async {
        lastUrl = request.url.toString();
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      // 1. Filtrar por rubro 1
      await provider.fetchProfitByRubro(rubroFilter: 1);
      expect(provider.rubroFilter, 1);
      expect(lastUrl, contains('rubro_id=1'));

      // 2. Limpiar filtro con null (Todos los Rubros)
      await provider.fetchProfitByRubro(rubroFilter: null);
      expect(provider.rubroFilter, isNull);
      expect(lastUrl, isNot(contains('rubro_id')));
      expect(lastUrl, isNot(contains('rubro_ids')));
    });

    test('ReportsProvider sets rubroError when export fails', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);

      await provider.exportRubroToExcel();
      expect(provider.rubroError, contains('Error al exportar Excel de rubros'));

      await provider.exportRubroToPdf();
      expect(provider.rubroError, contains('Error al exportar PDF de rubros'));
    });

    test('ReportsProvider preserves fractional items sold with rubroTotalQuantitySold', () async {
      final fractionalData = {
        'data': [
          {
            'rubro_name': 'Carnicería',
            'items_sold': 2.75,
            'total_revenue': 1000.0,
            'total_profit': 300.0,
            'revenue_with_cost': 1000.0,
          },
        ],
      };
      final mockClient = MockClient((request) async => http.Response(jsonEncode(fractionalData), 200, headers: {'content-type': 'application/json'}));
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final provider = ReportsProvider(dataSource: dataSource);
      await provider.fetchProfitByRubro();
      expect(provider.rubroTotalQuantitySold, 2.75);
    });
  });

  group('RubroProfitReportView Widget & Plan Gating Tests', () {
    testWidgets('Renders locked state and blocks report when multi_rubro is disabled', (tester) async {
      final settings = const BusinessSettings(
        features: FeatureFlags(multiRubro: false),
      );
      final settingsProv = FakeSettingsProvider(settings: settings);

      final mockClient = MockClient((request) async => http.Response('{}', 200));
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Rentabilidad por Rubro'), findsOneWidget);
      expect(find.text('MÓDULO PREMIUM (MULTI-RUBRO)'), findsOneWidget);
      expect(find.byIcon(Icons.lock_person_rounded), findsOneWidget);
      // No debe renderizar gráficos ni filtros
      expect(find.byType(BarChart), findsNothing);
      expect(find.byType(PieChart), findsNothing);
    });

    testWidgets('Renders BarChart, PieChart, KPI cards and table when multi_rubro is enabled', (tester) async {
      final settings = const BusinessSettings(
        features: FeatureFlags(multiRubro: true),
      );
      final settingsProv = FakeSettingsProvider(settings: settings);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);
      await reportsProv.fetchProfitByRubro();

      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // KPIs
      expect(find.text('Facturación Total'), findsOneWidget);
      expect(find.text('Ganancia Neta'), findsWidgets);
      expect(find.text('Margen Promedio'), findsOneWidget);
      expect(find.text('Ítems Vendidos'), findsOneWidget);

      // Gráficos analíticos con fl_chart
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.byType(PieChart), findsOneWidget);

      // Cabecera de tabla
      expect(find.text('Rubro'), findsOneWidget);
      expect(find.text('Cant.'), findsWidgets);
      expect(find.text('Facturación'), findsWidgets);
      expect(find.text('Margen'), findsWidgets);

      // Tabla y Rubros
      expect(find.text('Ferretería'), findsWidgets);
      expect(find.text('Pinturería'), findsWidgets);

      // Expandir fila de Ferretería para ver desglose de productos
      await tester.tap(find.byKey(const ValueKey('rubro_row_Ferretería')));
      await tester.pumpAndSettle();

      expect(find.text('Producto'), findsOneWidget);
      expect(find.text('• Martillo Pro'), findsOneWidget);
      expect(find.text('• Taladro Percutor'), findsOneWidget);
    });

    testWidgets('Responsiveness: Renders cleanly across screen resolutions with zero overflow', (tester) async {
      final settings = const BusinessSettings(
        features: FeatureFlags(multiRubro: true),
      );
      final settingsProv = FakeSettingsProvider(settings: settings);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);
      await reportsProv.fetchProfitByRubro();

      final resolutions = [
        const Size(320, 480), // Ultra-compact
        const Size(360, 640), // Standard mobile
        const Size(450, 700), // Foldable
        const Size(800, 600), // Compact desktop / Tablet
        const Size(1400, 900), // Large desktop
      ];

      for (final res in resolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
              ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: RubroProfitReportView(),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Failed at resolution: $res');
        expect(find.byType(RubroProfitReportView), findsOneWidget);
      }

      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('RubroProfitReportView auto-refreshes when provider date range is updated externally', (tester) async {
      final settings = const BusinessSettings(
        features: FeatureFlags(multiRubro: true),
      );
      final settingsProv = FakeSettingsProvider(settings: settings);

      int fetchCount = 0;
      final mockClient = MockClient((request) async {
        fetchCount++;
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      final initialFetchCount = fetchCount;
      expect(initialFetchCount, greaterThan(0));

      // Cambiar rango de fechas en el provider externamente (como cuando se hace desde Tab 0)
      reportsProv.setDateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 31));
      await tester.pumpAndSettle();

      expect(fetchCount, greaterThan(initialFetchCount));
    });

    testWidgets('Interactive detail table sorts rows when tapping column headers', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = const BusinessSettings(
        features: FeatureFlags(multiRubro: true),
      );
      final settingsProv = FakeSettingsProvider(settings: settings);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verificar que los botones de ordenamiento están presentes
      final sortMargin = find.byKey(const ValueKey('header_sort_margin'));
      final sortRubro = find.byKey(const ValueKey('header_sort_rubro'));
      expect(sortMargin, findsOneWidget);
      expect(sortRubro, findsOneWidget);

      // Tocar para ordenar por Margen
      await tester.tap(sortMargin);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tocar nuevamente para alternar orden ascendente/descendente
      await tester.tap(sortMargin);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Tocar para ordenar por Rubro
      await tester.tap(sortRubro);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Expanding a rubro displays product sub-rows with product margin column', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = const BusinessSettings(
        features: FeatureFlags(multiRubro: true),
      );
      final settingsProv = FakeSettingsProvider(settings: settings);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tocar la fila de Ferretería para expandir
      final ferreteriaRow = find.byKey(const ValueKey('rubro_row_Ferretería'));
      expect(ferreteriaRow, findsOneWidget);
      await tester.tap(ferreteriaRow);
      await tester.pumpAndSettle();

      // Verificar que aparece el producto y su sub-cabecera con columna Margen
      expect(find.text('• Martillo Pro'), findsOneWidget);
      expect(find.text('Margen'), findsWidgets);
    });

    testWidgets('BarChart displays Pérdida Neta in legend when a rubro has negative profit', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = const BusinessSettings(
        features: FeatureFlags(multiRubro: true),
      );
      final settingsProv = FakeSettingsProvider(settings: settings);

      final dataWithLoss = {
        'data': [
          {
            'rubro_id': 1,
            'rubro_name': 'Ferretería',
            'items_sold': 5,
            'total_revenue': 1000.0,
            'total_profit': -150.0, // Ganancia negativa
            'revenue_with_cost': 1000.0,
            'products': [],
          }
        ],
        'previous_period': {},
        'daily_evolution': [],
      };

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode(dataWithLoss), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Pérdida Neta'), findsOneWidget);
    });

    testWidgets('Negative margin in rubro summary row renders red margin badge', (tester) async {
      final negativeData = {
        'start_date': '2026-10-01',
        'end_date': '2026-10-31',
        'data': [
          {
            'rubro_name': 'Liquidación',
            'rubro_id': 9,
            'items_sold': 10,
            'total_revenue': 1000.0,
            'total_profit': -250.0,
            'revenue_with_cost': 1000.0,
            'products': [],
          },
        ],
      };

      final settingsProv = FakeSettingsProvider(settings: const BusinessSettings(features: FeatureFlags(multiRubro: true)));
      final mockClient = MockClient((request) async => http.Response(jsonEncode(negativeData), 200, headers: {'content-type': 'application/json'}));
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Buscamos el texto del badge dentro de la tabla (size 11)
      final badgeFinder = find.byWidgetPredicate((widget) =>
          widget is Text && widget.data == '-25.0%' && widget.style?.fontSize == 11);
      expect(badgeFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(badgeFinder);
      expect(textWidget.style?.color, Colors.red.shade800);
    });

    testWidgets('Export failure with loaded data displays top error banner while keeping report visible', (tester) async {
      final settingsProv = FakeSettingsProvider(settings: const BusinessSettings(features: FeatureFlags(multiRubro: true)));
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('export')) {
          return http.Response('Disk Error', 500);
        }
        return http.Response(jsonEncode(sampleRubroData), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: RubroProfitReportView(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Report is loaded
      expect(find.text('Facturación Total'), findsOneWidget);
      expect(find.text('Desglose por Rubro y Productos'), findsOneWidget);

      // Trigger export failure
      await reportsProv.exportRubroToExcel();
      await tester.pumpAndSettle();

      // Error banner is visible at the top
      expect(find.textContaining('Error al exportar Excel de rubros'), findsOneWidget);
      // Report content is NOT destroyed
      expect(find.text('Facturación Total'), findsOneWidget);
      expect(find.text('Desglose por Rubro y Productos'), findsOneWidget);
    });
  });

  group('ReportsScreen Tab Integration Tests', () {
    testWidgets('ReportsScreen tab bar omits Por Rubro tab when multi_rubro is disabled', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final basicSettings = const BusinessSettings(
        features: FeatureFlags(multiRubro: false, advancedReports: false),
      );
      final basicSettingsProv = FakeSettingsProvider(settings: basicSettings);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'data': [], 'previous_period': {}, 'daily_evolution': []}), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: basicSettingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
            ChangeNotifierProvider<CheckProvider>.value(value: FakeCheckProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Por Categoría'), findsOneWidget);
      expect(find.text('Marcas'), findsOneWidget);
      expect(find.text('Por Rubro'), findsNothing);
    });

    testWidgets('ReportsScreen tab bar displays Por Rubro tab when multi_rubro is enabled', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final premiumSettings = const BusinessSettings(
        features: FeatureFlags(multiRubro: true, advancedReports: false),
      );
      final premiumSettingsProv = FakeSettingsProvider(settings: premiumSettings);

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'data': [], 'previous_period': {}, 'daily_evolution': []}), 200, headers: {'content-type': 'application/json'});
      });
      final dataSource = ReportsRemoteDataSource(baseUrl: 'http://localhost/api', client: mockClient);
      final reportsProv = ReportsProvider(dataSource: dataSource);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: premiumSettingsProv),
            ChangeNotifierProvider<ReportsProvider>.value(value: reportsProv),
            ChangeNotifierProvider<CheckProvider>.value(value: FakeCheckProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: FakeInventoryAlertsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: FakeAuthProvider()),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Por Categoría'), findsOneWidget);
      expect(find.text('Marcas'), findsOneWidget);
      expect(find.text('Por Rubro'), findsOneWidget);
    });
  });
}
