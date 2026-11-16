import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/rubro.dart';
import 'package:frontend_desktop/features/catalog/presentation/pages/catalog_screen.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/models/supplier_model.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _ComboFakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> _catalog;

  _ComboFakeCatalogProvider(this._catalog);

  @override
  List<Product> get products => _catalog;
  @override
  List<Category> get categories => [Category(id: 1, name: 'Pastelería')];
  @override
  List<Brand> get brands => [Brand(id: 1, name: 'Artesanal')];
  @override
  List<Rubro> get rubros => const [];
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;

  @override
  Future<void> loadMetadata({bool force = false}) async {}

  @override
  Future<List<Product>> searchProductsForCombo(String query) async {
    final q = query.trim().toLowerCase();
    return _catalog
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.barcode?.toLowerCase().contains(q) ?? false) ||
            p.internalCode.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Product>> searchProductsRemote(String query, {int perPage = 30}) =>
      searchProductsForCombo(query);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ComboFakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    licensePlanType: 'basic',
    features: FeatureFlags(suppliers: true),
  );

  @override
  BusinessSettings? get settings => _settings;
  @override
  FeatureFlags get features => _settings.features;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ComboFakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  List<Supplier> get suppliers => const [];
  @override
  bool get isLoading => false;
  @override
  Future<void> fetchSuppliers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-test',
      'pos_api': 'http://localhost/api',
    });
  });

  final tortaMatilda = Product(
    id: 50,
    name: 'TORTA MATILDA',
    internalCode: '00050',
    barcode: '7790005000501',
    costPrice: 1200.0,
    sellingPrice: 2000.0,
    stock: 1.0,
    minStock: 0.0,
    active: true,
    isSoldByWeight: false,
  );

  Widget buildDialogApp(CatalogProvider catProv) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CatalogProvider>.value(value: catProv),
        ChangeNotifierProvider<SettingsProvider>(create: (_) => _ComboFakeSettingsProvider()),
        ChangeNotifierProvider<SupplierProvider>(create: (_) => _ComboFakeSupplierProvider()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => ProductFormDialog(provider: catProv),
                );
              },
              child: const Text('Abrir Producto'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'Combo / Receta UX: oculta campos inaplicables, permite búsqueda inline + ÷ 16 y botón Aplicar al precio',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final catProv = _ComboFakeCatalogProvider([tortaMatilda]);
      await tester.pumpWidget(buildDialogApp(catProv));
      await tester.tap(find.text('Abrir Producto'));
      await tester.pumpAndSettle();

      // Cambiar a modo Combo / Fracción
      await tester.tap(find.text('Combo / Fracción'));
      await tester.pumpAndSettle();

      // Campos fantasma e inaplicables ocultos; métricas de receta visibles; Precios Mayoristas colapsado
      expect(find.text('Precio Costo (Opc.)'), findsNothing);
      expect(find.text('Unidad de Medida'), findsNothing);
      expect(find.text('Venta p/peso'), findsNothing);
      expect(find.text('Costo Receta (Calc.)'), findsOneWidget);
      expect(find.text('% Margen Receta'), findsOneWidget);
      expect(find.text('Precios Mayoristas · Sin escalas', findRichText: true), findsOneWidget);

      // Búsqueda inline de ingrediente y agregado al combo
      final inlineSearch = find.byKey(const Key('catalog_combo_inline_search'));
      expect(inlineSearch, findsOneWidget);
      await tester.enterText(inlineSearch, 'Matilda');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TORTA MATILDA').last);
      await tester.pumpAndSettle();

      expect(find.text('Productos incluidos en el Combo (1)'), findsOneWidget);

      // Abrir calculadora de fracciones 1/x y dividir en 16 partes
      final fracToggle = find.byKey(const Key('catalog_combo_fraction_toggle_50'));
      await tester.ensureVisible(fracToggle);
      await tester.tap(fracToggle);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('catalog_combo_parts_50')), '16');
      await tester.tap(find.byKey(const Key('catalog_combo_apply_parts_50')));
      await tester.pumpAndSettle();

      // Stock 1 / (1/16) = 16 porciones/fracciones armables hoy
      expect(find.text('Cálculo de Porción / Fracción'), findsOneWidget);
      expect(find.text('Porciones/Fracciones armables hoy: 16'), findsOneWidget);
      expect(find.text('Valor proporcional: \$125'), findsOneWidget);

      // Botón accionable "Base ($125)" + sugerencias de Fracción (+%) al dividir en 16 partes
      final applyBtn = find.byKey(const Key('catalog_apply_base_price_btn'));
      await tester.ensureVisible(applyBtn);
      expect(find.text('Base (\$125)'), findsOneWidget);
      expect(find.text('+30% (\$162,50)'), findsOneWidget);
      expect(find.text('+50% (\$187,50)'), findsOneWidget);
      expect(find.text('+100% (x2) (\$250)'), findsOneWidget);

      await tester.tap(applyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Base \$125 aplicada'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '125'), findsOneWidget);

      // Aplicar sugerencia de fracción +50% ($187,50) y verificar rendimiento por unidad entera
      final plus50Btn = find.byKey(const Key('catalog_apply_plus50_btn'));
      await tester.ensureVisible(plus50Btn);
      await tester.tap(plus50Btn);
      await tester.pumpAndSettle();

      expect(find.text('+50% (\$187,50) aplicado'), findsOneWidget);
      expect(
        find.textContaining('Rendimiento por unidad entera (16 porc.): \$3.000 (+50% vs \$2.000 entera)'),
        findsOneWidget,
      );

      // Toggle manual a Combo (-%) -> sugiere -10% ($112,50) y -15% ($106,25)
      await tester.ensureVisible(find.text('Combo (-%)'));
      await tester.tap(find.text('Combo (-%)'));
      await tester.pumpAndSettle();
      expect(find.text('-10% (\$112,50)'), findsOneWidget);
      expect(find.text('-15% (\$106,25)'), findsOneWidget);

      // Aplicar sugerencia -10% ($112,50) en 1 clic -> actualiza Precio Venta y ahorro exacto
      final promo10Btn = find.byKey(const Key('catalog_apply_promo10_btn'));
      await tester.ensureVisible(promo10Btn);
      await tester.tap(promo10Btn);
      await tester.pumpAndSettle();

      expect(find.text('-10% (\$112,50) aplicado'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '112,50'), findsOneWidget);
      expect(
        find.text('Ahorro p/ el cliente: -\$12,50 (-10.0%)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Responsive stress: Combo / Receta renderiza sin overflow en viewport 320x480',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catProv = _ComboFakeCatalogProvider([tortaMatilda]);
      await tester.pumpWidget(buildDialogApp(catProv));
      await tester.tap(find.text('Abrir Producto'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Combo / Fracción'));
      await tester.pumpAndSettle();

      final inlineSearch = find.byKey(const Key('catalog_combo_inline_search'));
      await tester.ensureVisible(inlineSearch);
      await tester.enterText(inlineSearch, 'Matilda');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TORTA MATILDA').last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Fase 0 UX: Control de Vencimiento inicia plegado para producto nuevo y expande fila única compacta sin overflow',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catProv = _ComboFakeCatalogProvider([tortaMatilda]);
      await tester.pumpWidget(buildDialogApp(catProv));
      await tester.tap(find.text('Abrir Producto'));
      await tester.pumpAndSettle();

      // Producto nuevo sin datos de vencimiento: sección inicia plegada
      expect(find.text('Control de Vencimiento y Alertas (Opcional)'), findsOneWidget);
      expect(find.text('Configurar vencimiento'), findsOneWidget);
      expect(find.text('Fecha de Vencimiento (Lote)'), findsNothing);
      expect(find.byType(Tooltip), findsWidgets);

      await tester.ensureVisible(find.text('Configurar vencimiento'));
      await tester.tap(find.text('Configurar vencimiento'));
      await tester.pumpAndSettle();

      expect(find.text('Ocultar'), findsOneWidget);
      expect(find.text('Fecha de Vencimiento (Lote)'), findsOneWidget);
      expect(find.text('Pre-Alerta'), findsOneWidget);
      expect(find.text('Vida útil / envasado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Fase 0 UX: Control de Vencimiento inicia expandido al editar producto que ya tiene fecha de vencimiento',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final catProv = _ComboFakeCatalogProvider([tortaMatilda]);
      final productoConVto = Product(
        id: 88,
        name: 'YOGUR ENTERO',
        internalCode: '00088',
        costPrice: 800,
        sellingPrice: 1500,
        stock: 10,
        active: true,
        isSoldByWeight: false,
        expirationDate: '2026-12-31',
        expiryAlertDays: 10,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CatalogProvider>.value(value: catProv),
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _ComboFakeSettingsProvider()),
            ChangeNotifierProvider<SupplierProvider>(
                create: (_) => _ComboFakeSupplierProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => ProductFormDialog(
                        provider: catProv,
                        product: productoConVto,
                      ),
                    );
                  },
                  child: const Text('Editar Producto'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Editar Producto'));
      await tester.pumpAndSettle();

      expect(find.text('Ocultar'), findsOneWidget);
      expect(find.text('Fecha de Vencimiento (Lote)'), findsOneWidget);
      expect(find.text('31/12/2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
