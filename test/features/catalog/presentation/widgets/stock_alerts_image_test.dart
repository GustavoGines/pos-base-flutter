import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/widgets/stock_alert_bell.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';

class FakeCatalogAlertsProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> _criticalAlerts;

  FakeCatalogAlertsProvider({List<Product>? criticalAlerts})
      : _criticalAlerts = criticalAlerts ?? [];

  @override
  List<Product> get criticalAlerts => _criticalAlerts;

  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Widget buildTestAlertBell({required List<Product> alerts}) {
    final catalogProv = FakeCatalogAlertsProvider(criticalAlerts: alerts);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catalogProv),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StockAlertBell(),
          ),
        ),
      ),
    );
  }

  group('Milestone 2: StockAlertBell Product Thumbnail Tests', () {
    testWidgets('Stock alert item with valid imageUrl renders 40x40 thumbnail with CachedNetworkImage', (tester) async {
      final alertProductWithImage = Product(
        id: 501,
        name: 'Aceite de Girasol 1.5L',
        internalCode: 'ACE-501',
        costPrice: 800,
        sellingPrice: 1200,
        stock: 0,
        active: true,
        isSoldByWeight: false,
        imageUrl: 'http://pos-backend.test/storage/products/501.jpg',
      );

      await tester.pumpWidget(buildTestAlertBell(alerts: [alertProductWithImage]));
      await tester.pump();

      // Tap bell icon to open overlay portal
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify product name and internal code are displayed
      expect(find.text('Aceite de Girasol 1.5L'), findsOneWidget);
      expect(find.text('ACE-501'), findsOneWidget);

      // Verify CachedNetworkImage is displayed in the alert item
      final imageFinder = find.byType(CachedNetworkImage);
      expect(imageFinder, findsOneWidget);

      final cachedImage = tester.widget<CachedNetworkImage>(imageFinder);
      expect(cachedImage.imageUrl, 'http://pos-backend.test/storage/products/501.jpg');
      expect(cachedImage.width, 40.0);
      expect(cachedImage.height, 40.0);
    });

    testWidgets('Stock alert item without image renders fallback Icon(Icons.inventory_2_outlined)', (tester) async {
      final alertProductNoImage = Product(
        id: 502,
        name: 'Arroz Integral 1kg',
        internalCode: 'ARR-502',
        costPrice: 400,
        sellingPrice: 650,
        stock: 2,
        active: true,
        isSoldByWeight: false,
        imageUrl: null,
      );

      await tester.pumpWidget(buildTestAlertBell(alerts: [alertProductNoImage]));
      await tester.pumpAndSettle();

      // Tap bell icon to open overlay portal
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      // No CachedNetworkImage widget rendered
      expect(find.byType(CachedNetworkImage), findsNothing);

      // Fallback icon inventory_2_outlined rendered
      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('Empty stock alert state displays "¡Todo en orden!" message', (tester) async {
      await tester.pumpWidget(buildTestAlertBell(alerts: []));
      await tester.pumpAndSettle();

      // Tap bell icon to open overlay portal
      await tester.tap(find.byType(IconButton));
      await tester.pumpAndSettle();

      expect(find.text('¡Todo en orden!'), findsOneWidget);
    });
  });
}
