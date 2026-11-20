import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/widgets/inventory_alerts_widget.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _FakeInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  final List<Map<String, dynamic>> _reactive;
  final List<Map<String, dynamic>> _expiration;

  _FakeInventoryAlertsProvider({
    required List<Map<String, dynamic>> reactive,
    required List<Map<String, dynamic>> expiration,
  })  : _reactive = reactive,
        _expiration = expiration;

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  @override
  List<dynamic> get reactiveAlerts => _reactive;

  @override
  List<dynamic> get expirationAlerts => _expiration;

  @override
  List<dynamic> get deficitAlerts => const [];

  @override
  List<dynamic> get predictiveCriticalAlerts => const [];

  @override
  List<dynamic> get alerts => [..._reactive, ..._expiration];

  @override
  int get totalAlertsCount => alerts.length;

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _FakeSettingsProvider(this._settings);

  @override
  BusinessSettings? get settings => _settings;

  @override
  FeatureFlags get features => _settings.features;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  List<Product> get products => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'InventoryAlertsWidget overlay soporta hover/tooltip en Limpiar búsqueda y PopupMenuButton sin crash de RenderFollowerLayer',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final alertsProv = _FakeInventoryAlertsProvider(
        reactive: [
          {
            'product_id': 2,
            'product_name': 'Café Molido 500g',
            'internal_code': 'CAF-002',
            'alert_type': 'out_of_stock',
            'current_stock': 0,
            'is_sold_by_weight': false,
          },
        ],
        expiration: [
          {
            'product_id': 1,
            'batch_id': 10,
            'batch_code': 'L-010',
            'product_name': 'Medialunas',
            'alert_type': 'expiration',
            'alert_level': 'critical',
            'days_until_expiry': 1,
            'expiry_stage_label': 'Por vencer',
            'current_stock': 12,
            'expiration_date': '2026-11-20',
          },
        ],
      );

      final settingsProv = _FakeSettingsProvider(
        const BusinessSettings(
          features: FeatureFlags(
            predictiveAlerts: true,
            batchExpiration: true,
          ),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryAlertsProvider>.value(
              value: alertsProv,
            ),
            ChangeNotifierProvider<SettingsProvider>.value(
              value: settingsProv,
            ),
            ChangeNotifierProvider<CatalogProvider>.value(
              value: _FakeCatalogProvider(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                title: const Text('Dashboard'),
                actions: const [
                  InventoryAlertsWidget(),
                ],
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir el overlay pulsando el botón de la campana
      final bellButton = find.descendant(
        of: find.byType(Badge),
        matching: find.byType(IconButton),
      );
      expect(bellButton, findsOneWidget);
      await tester.tap(bellButton);
      await tester.pumpAndSettle();

      expect(find.text('Alertas de Reposición'), findsOneWidget);
      expect(find.text('Medialunas'), findsOneWidget);
      expect(find.text('Café Molido 500g'), findsOneWidget);

      // Escribir en el buscador para mostrar el IconButton(tooltip: 'Limpiar búsqueda')
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Medi');
      await tester.pumpAndSettle();

      expect(find.text('Medialunas'), findsOneWidget);
      expect(find.text('Café Molido 500g'), findsNothing);

      final clearBtn = find.byTooltip('Limpiar búsqueda');
      expect(clearBtn, findsOneWidget);

      // Simular hover con mouse para activar el Tooltip del botón 'Limpiar búsqueda'
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(clearBtn));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);

      // Simular hover con mouse sobre PopupMenuButton<String> para disparar su Tooltip
      final popupBtn = find.byType(PopupMenuButton<String>);
      expect(popupBtn, findsOneWidget);
      await mouse.moveTo(tester.getCenter(popupBtn));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);

      // Mantener presionado / tap para abrir el menú de opciones del PopupMenuButton
      await tester.tap(popupBtn);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Posponer por 1 día'), findsOneWidget);
      expect(find.text('Crear Oferta de Liquidación (%)'), findsOneWidget);
    },
  );
}
