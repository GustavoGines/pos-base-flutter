import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_price_lookup_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_item_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_offers_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/suppliers/providers/supplier_provider.dart';

class _FakePosProvider extends ChangeNotifier implements PosProvider {
  final List<Product> remotePosProducts;
  final List<CartItem> _cart = [];

  _FakePosProvider({this.remotePosProducts = const []});

  @override
  List<CartItem> get cart => _cart;

  @override
  double get wholesaleFactor => 0.9;

  @override
  double get cardFactor => 1.1;

  @override
  double get currentCustomFactor => 1.0;

  @override
  String? get customTierLabel => null;

  @override
  void syncActiveOffers(List<dynamic> activeOffers) {}

  @override
  Future<List<Product>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return remotePosProducts.where((p) {
      return p.active &&
          (p.name.toLowerCase().contains(q) ||
              (p.barcode?.toLowerCase().contains(q) ?? false) ||
              p.internalCode.toLowerCase().contains(q));
    }).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  final List<Product> localProducts;
  final List<Product> remoteProducts;

  _FakeCatalogProvider({
    this.localProducts = const [],
    this.remoteProducts = const [],
  });

  @override
  List<Product> get products => localProducts;

  @override
  List<Product> get pinnedExtraProducts => const [];

  @override
  List<Product> get weightOnlyProducts => const [];

  @override
  List<Category> get categories => const [];

  @override
  List<Brand> get brands => const [];

  @override
  Future<void> loadMetadata({bool force = false}) async {}

  @override
  Future<List<Product>> searchProductsRemote(String query,
      {int perPage = 30}) async {
    final q = query.trim().toLowerCase();
    return remoteProducts
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            (p.barcode?.toLowerCase().contains(q) ?? false) ||
            p.internalCode.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<Product>> searchProductsForCombo(String query) =>
      searchProductsRemote(query, perPage: 20);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  List<OfferModel> get activeOffers => const [];

  @override
  List<OfferModel> get allOffers => const [];

  @override
  bool get isLoadingActive => false;

  @override
  Future<void> loadActiveOffers() async {}

  @override
  Future<void> loadAllOffers({String? status, String? search}) async {}

  @override
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) =>
      null;

  @override
  double? getDiscountedPrice(Product product) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    features: FeatureFlags(suppliers: false),
  );

  @override
  BusinessSettings? get settings => _settings;

  @override
  FeatureFlags get features => _settings.features;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSupplierProvider extends ChangeNotifier implements SupplierProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Product _buildProduct({
  required int id,
  required String name,
  required String internalCode,
  String? barcode,
  double price = 1500.0,
}) {
  return Product(
    id: id,
    name: name,
    internalCode: internalCode,
    barcode: barcode,
    costPrice: price * 0.6,
    sellingPrice: price,
    stock: 15,
    active: true,
    isSoldByWeight: false,
  );
}

Widget _wrapWithProviders({
  required Widget child,
  required PosProvider posProvider,
  required CatalogProvider catalogProvider,
  OfferProvider? offerProvider,
  SettingsProvider? settingsProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PosProvider>.value(value: posProvider),
      ChangeNotifierProvider<CatalogProvider>.value(value: catalogProvider),
      ChangeNotifierProvider<OfferProvider>.value(
        value: offerProvider ?? _FakeOfferProvider(),
      ),
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider ?? _FakeSettingsProvider(),
      ),
      ChangeNotifierProvider<SupplierProvider>.value(
        value: _FakeSupplierProvider(),
      ),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('UX y Escáner en Modales POS', () {
    testWidgets(
      'PosQuickOffersDialog: escaneo USB continuo con Enter agrega productos y mantiene el foco sin perderlo ni recortar pestañas',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final coca = _buildProduct(
          id: 1,
          name: 'Coca Cola 2.25L',
          internalCode: '00014',
          barcode: '7790895000997',
          price: 2500,
        );
        final agua = _buildProduct(
          id: 2,
          name: 'Agua Villavicencio 2L',
          internalCode: '00015',
          barcode: '7791234567890',
          price: 1200,
        );

        final posProv = _FakePosProvider(remotePosProducts: [coca, agua]);
        final catProv = _FakeCatalogProvider(localProducts: [coca]);

        await tester.pumpWidget(
          _wrapWithProviders(
            posProvider: posProv,
            catalogProvider: catProv,
            child: const PosQuickOffersDialog(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Armar Nueva Oferta'), findsOneWidget);
        await tester.tap(find.text('Armar Nueva Oferta'));
        await tester.pumpAndSettle();

        final searchField = find.widgetWithText(
          TextField,
          'Buscar por nombre o pistolear código (USB / Celular)...',
        );
        expect(searchField, findsOneWidget);

        // 1er escaneo USB: Enter sobre código local
        await tester.tap(searchField);
        await tester.pump();
        await tester.enterText(searchField, '7790895000997');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Productos en la Oferta (1):'), findsOneWidget);

        // El campo se limpió y conserva foco listo para la siguiente pistola USB
        final tfAfterFirst = tester.widget<TextField>(searchField);
        expect(tfAfterFirst.controller?.text, isEmpty);
        expect(tfAfterFirst.focusNode?.hasFocus, isTrue);

        // 2do escaneo USB (producto encontrado en /pos/products/search por PLU/EAN) sin volver a tocar el campo
        await tester.enterText(searchField, '15');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Productos en la Oferta (2):'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog: prefill inteligente de initialQuery (código vs nombre), sin doble signo \$ y fracciones 1/x compactas',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final cable = _buildProduct(
          id: 50,
          name: 'Cable HDMI 2m',
          internalCode: '00050',
          barcode: '7790005000500',
          price: 4000,
        );
        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider(
          localProducts: [cable],
          remoteProducts: [cable],
        );

        // Caso A: initialQuery tipo código de barras -> banner referencia, nombre vacío y sin doble icono $
        await tester.pumpWidget(
          _wrapWithProviders(
            posProvider: posProv,
            catalogProvider: catProv,
            child: const PosQuickItemDialog(initialQuery: '7791112223334'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Código escaneado: "7791112223334"'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(
                  TextFormField,
                  'Notas adicionales para Factura / Ticket (Opcional)',
                ),
              )
              .controller
              ?.text,
          isEmpty,
        );
        expect(find.byIcon(Icons.attach_money_rounded), findsNothing);
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(TextFormField, 'Descripción del Producto *'),
              )
              .controller
              ?.text,
          isEmpty,
        );

        // Cambiar a Combo / Fracción y agregar ingrediente -> chips 1/x colapsados por defecto
        await tester.tap(find.text('Combo / Fracción'));
        await tester.pumpAndSettle();

        final comboSearch = find.widgetWithText(
          TextField,
          'Buscar o pistolear producto para incluir en el combo...',
        );
        await tester.enterText(comboSearch, 'Cable HDMI');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cable HDMI 2m'));
        await tester.pumpAndSettle();

        expect(find.text('1/6'), findsNothing);
        await tester.tap(find.text('1/x'));
        await tester.pumpAndSettle();
        expect(find.text('1/6'), findsOneWidget);

        // Caso B: initialQuery de texto -> prellena el nombre del producto sin banner EAN
        await tester.pumpWidget(
          _wrapWithProviders(
            posProvider: posProv,
            catalogProvider: catProv,
            child: const PosQuickItemDialog(
              key: ValueKey('text-prefill'),
              initialQuery: 'Tornillo drywall',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Cód. consultado:'), findsNothing);
        expect(find.textContaining('Código escaneado:'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'Tornillo drywall'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosPriceLookupDialog (F5): no muestra Producto Rápido en reposo; al no encontrar código ofrece F3 y Asociar, y texto solo F3',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider();
        String? requestedQuickQuery;
        String? requestedAssociateCode;

        await tester.pumpWidget(
          _wrapWithProviders(
            posProvider: posProv,
            catalogProvider: catProv,
            child: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  PosPriceLookupDialog.show(
                    ctx,
                    onQuickCreateRequested: (q) => requestedQuickQuery = q,
                    onAssociateBarcodeRequested: (c) =>
                        requestedAssociateCode = c,
                  );
                },
                child: const Text('Abrir F5'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir F5'));
        await tester.pumpAndSettle();

        // Estado inicial limpio: sin botón de creación rápida
        expect(find.text('Producto Rápido (F3)'), findsNothing);
        expect(find.text('Asociar código a existente'), findsNothing);

        // Buscar código inexistente -> muestra ambos botones contextuales
        final lookupInput = find.byType(TextField);
        await tester.enterText(lookupInput, '7799998887776');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(
          find.text('No se encontró ningún producto activo para "7799998887776".'),
          findsOneWidget,
        );
        expect(find.text('Producto Rápido (F3)'), findsOneWidget);
        expect(find.text('Asociar código a existente'), findsOneWidget);

        await tester.tap(find.text('Producto Rápido (F3)'));
        await tester.pumpAndSettle();
        expect(requestedQuickQuery, '7799998887776');
        expect(requestedAssociateCode, isNull);

        // Reabrir F5 con consulta textual (no barcode) -> no ofrece Asociar código, y atajo F3 funciona
        requestedQuickQuery = null;
        await tester.tap(find.text('Abrir F5'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'Repuesto Especial');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(find.text('Producto Rápido (F3)'), findsOneWidget);
        expect(find.text('Asociar código a existente'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.f3);
        await tester.pumpAndSettle();
        expect(requestedQuickQuery, 'Repuesto Especial');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog Combo: soporta divisor universal ÷ 16 (0.0625) y escritura directa 1/16',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final torta = _buildProduct(
          id: 90,
          name: 'Torta Chocolina',
          internalCode: '00090',
          barcode: '7790009000900',
          price: 2000,
        );
        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider(
          localProducts: [torta],
          remoteProducts: [torta],
        );

        await tester.pumpWidget(
          _wrapWithProviders(
            posProvider: posProv,
            catalogProvider: catProv,
            child: const PosQuickItemDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Combo / Fracción'));
        await tester.pumpAndSettle();

        final comboSearch = find.widgetWithText(
          TextField,
          'Buscar o pistolear producto para incluir en el combo...',
        );
        await tester.enterText(comboSearch, 'Torta');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Torta Chocolina'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('1/x'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('quick_combo_parts_90')), '16');
        await tester.tap(find.byKey(const Key('quick_combo_apply_parts_90')));
        await tester.pumpAndSettle();

        // 1/16 -> 0.0625, y 0.0625 * $2.000 = $125 en "Valor proporcional: $125 · Fracción: $0"
        expect(find.widgetWithText(TextField, '0.0625'), findsOneWidget);
        expect(find.textContaining('Valor proporcional: \$125'), findsOneWidget);

        // Escritura directa de fracción 1/8 -> Valor proporcional: $250
        await tester.enterText(find.widgetWithText(TextField, '0.0625'), '1/8');
        await tester.pumpAndSettle();
        expect(find.textContaining('Valor proporcional: \$250'), findsOneWidget);

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog Combo: no autorrellena campos y recomienda precios dinámicos según porciones',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 960));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final torta = _buildProduct(
          id: 91,
          name: 'Torta Matilda',
          internalCode: '00091',
          barcode: '7790009100917',
          price: 2000, // costPrice = 1200
        );
        final cafe = _buildProduct(
          id: 92,
          name: 'Café Doble',
          internalCode: '00092',
          barcode: '7790009200924',
          price: 1000, // costPrice = 600
        );
        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider(
          localProducts: [torta, cafe],
          remoteProducts: [torta, cafe],
        );

        await tester.pumpWidget(
          _wrapWithProviders(
            posProvider: posProv,
            catalogProvider: catProv,
            child: const PosQuickItemDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Combo / Fracción'));
        await tester.pumpAndSettle();

        // 1. Agregar primer ingrediente -> NO autorrellena precio, detalle ni costo editable
        final comboSearch = find.widgetWithText(
          TextField,
          'Buscar o pistolear producto para incluir en el combo...',
        );
        await tester.enterText(comboSearch, 'Matilda');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Torta Matilda'));
        await tester.pumpAndSettle();

        expect(find.text('1x Torta Matilda'), findsNothing);
        expect(find.widgetWithText(TextFormField, '2.000'), findsNothing);
        expect(find.text('Precio de Costo (Opcional)'), findsNothing);
        expect(find.text('% Ganancia s/Costo'), findsNothing);
        expect(find.text('Costo Receta (Calc.)'), findsOneWidget);
        expect(find.text('\$1.200'), findsOneWidget);
        expect(find.text('% Margen Combo'), findsOneWidget);
        expect(find.text('Ingresá precio'), findsOneWidget);

        // 2. Fraccionar a 1/8 ($250 valor proporcional, $150 costo) -> detecta modo Fracción (+%)
        await tester.tap(find.text('1/x'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('1/8'));
        await tester.pumpAndSettle();
        expect(find.text('\$150'), findsOneWidget);
        expect(find.text('Usar \$250'), findsOneWidget);
        expect(find.text('+30% (\$325)'), findsOneWidget);
        expect(find.text('+50% (\$375)'), findsOneWidget);
        expect(find.text('+100% (x2) (\$500)'), findsOneWidget);

        final plus50QuickBtn =
            find.byKey(const Key('quick_combo_apply_plus50_btn'));
        await tester.ensureVisible(plus50QuickBtn);
        await tester.tap(plus50QuickBtn);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
              'Rendimiento por unidad entera (8 porc.): \$3.000 (+50% vs \$2.000 entera)'),
          findsOneWidget,
        );

        // 3. Agregar 2º ingrediente (Café Doble $1.000 lista, $600 costo) -> suma $1.250, costo $750
        await tester.enterText(comboSearch, 'Café');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Café Doble'));
        await tester.pumpAndSettle();

        expect(find.text('\$750'), findsOneWidget);
        expect(find.text('Usar \$1.250'), findsOneWidget);
        expect(find.text('+30% (\$1.625)'), findsOneWidget);

        // Cambiar con toggle manual a Combo (-%) -> sugiere -10% ($1.125) y -15% ($1.062,50)
        await tester.ensureVisible(find.text('Combo (-%)'));
        await tester.tap(find.text('Combo (-%)'));
        await tester.pumpAndSettle();
        expect(find.text('-10% (\$1.125)'), findsOneWidget);
        expect(find.text('-15% (\$1.062,50)'), findsOneWidget);

        // 4. Tocar -10% ($1.125) -> llena Precio Venta Unit., muestra ahorro -10.0% y margen 50%
        final promo10Btn = find.byKey(const Key('quick_combo_apply_promo10_btn'));
        await tester.ensureVisible(promo10Btn);
        await tester.tap(promo10Btn);
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextFormField, '1.125'), findsOneWidget);
        expect(find.text('Ahorro \$125 (-10.0%)'), findsOneWidget);
        expect(find.text('50%'), findsOneWidget);

        // 5. Copiar ingredientes al detalle solo bajo demanda con el botón
        final copyBtn = find.byKey(const Key('quick_combo_copy_details_btn'));
        await tester.ensureVisible(copyBtn);
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(
            TextFormField,
            '0.125x Torta Matilda + 1x Café Doble',
          ),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog Combo: renderiza sin overflow en viewport 320x480 con ingredientes y sugerencias',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final torta = _buildProduct(
          id: 93,
          name: 'Torta Matilda',
          internalCode: '00093',
          price: 2000,
        );
        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider(
          localProducts: [torta],
          remoteProducts: [torta],
        );

        await tester.pumpWidget(
          _wrapWithProviders(
            posProvider: posProv,
            catalogProvider: catProv,
            child: const PosQuickItemDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Combo / Fracción'));
        await tester.pumpAndSettle();

        final comboSearch = find.widgetWithText(
          TextField,
          'Buscar o pistolear producto para incluir en el combo...',
        );
        await tester.ensureVisible(comboSearch);
        await tester.enterText(comboSearch, 'Matilda');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Torta Matilda'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog: switch fijo Guardar en el Catálogo con default inteligente por pestaña, hint N y cantidades persistibles',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 960));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final torta = _buildProduct(
          id: 95,
          name: 'Torta Balcarce',
          internalCode: '00095',
          barcode: '7790009500955',
          price: 4000,
        );
        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider(
          localProducts: [torta],
          remoteProducts: [torta],
        );

        PosQuickItemResult? capturedResult;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<CatalogProvider>.value(value: catProv),
              ChangeNotifierProvider<OfferProvider>.value(
                  value: _FakeOfferProvider()),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: _FakeSettingsProvider()),
              ChangeNotifierProvider<SupplierProvider>.value(
                  value: _FakeSupplierProvider()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () async {
                      capturedResult = await showDialog<PosQuickItemResult>(
                        context: ctx,
                        builder: (_) => const PosQuickItemDialog(),
                      );
                    },
                    child: const Text('Abrir Rápido'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Abrir Rápido'));
        await tester.pumpAndSettle();

        // 1. Default en Producto Rápido: Switch fijo "Guardar en el Catálogo" en ON
        expect(find.text('Guardar en el Catálogo'), findsOneWidget);
        SwitchListTile readSwitch() =>
            tester.widget<SwitchListTile>(find.byType(SwitchListTile));
        expect(readSwitch().value, isTrue);

        // 2. Servicio / Honorario mantiene ON por defecto
        await tester.tap(find.text('Servicio / Honorario'));
        await tester.pumpAndSettle();
        expect(find.text('Guardar en el Catálogo'), findsOneWidget);
        expect(readSwitch().value, isTrue);

        // 3. Combo / Promoción pasa automáticamente a OFF (solo venta)
        await tester.tap(find.text('Combo / Fracción'));
        await tester.pumpAndSettle();
        expect(find.text('Guardar en el Catálogo'), findsOneWidget);
        expect(readSwitch().value, isFalse);

        // Agregar ingrediente Torta Balcarce -> hint 'N' y subtítulo aclara que SÍ descuenta stock
        final comboSearch = find.widgetWithText(
          TextField,
          'Buscar o pistolear producto para incluir en el combo...',
        );
        await tester.enterText(comboSearch, 'Balcarce');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Torta Balcarce'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('SÍ descuenta el stock de sus 1 ingredientes al cobrar'),
          findsOneWidget,
        );

        await tester.tap(find.text('1/x'));
        await tester.pumpAndSettle();
        final customPartsField = tester.widget<TextField>(
          find.byKey(const Key('quick_combo_parts_95')),
        );
        expect(customPartsField.decoration?.hintText, 'N');

        // Dividir en 1/16 -> activar manual switch para guardar en catálogo (redondea a 0.063)
        await tester.enterText(find.byKey(const Key('quick_combo_parts_95')), '16');
        await tester.tap(find.byKey(const Key('quick_combo_apply_parts_95')));
        await tester.pumpAndSettle();

        // Activar manualmente "Guardar en el Catálogo" y verificar que persiste al cambiar pestañas
        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(readSwitch().value, isTrue);

        await tester.tap(find.text('Producto Rápido'));
        await tester.pumpAndSettle();
        expect(readSwitch().value, isTrue);
        await tester.tap(find.text('Combo / Fracción'));
        await tester.pumpAndSettle();
        expect(readSwitch().value, isTrue);

        // Llenar nombre + precio y confirmar -> persiste 0.063 compatible con decimal(10,3)
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nombre del Combo / Fracción *'),
          '1 Porción Balcarce',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Precio Venta Unit. *'),
          '500',
        );
        await tester.tap(find.text('Agregar al Carrito (Enter)'));
        await tester.pumpAndSettle();

        expect(capturedResult, isNotNull);
        expect(capturedResult!.item.saveToCatalog, isTrue);
        expect(capturedResult!.item.isTemporary, isFalse);
        expect(capturedResult!.item.product.comboIngredients?.first['quantity'], 0.063);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog Combo temporal: conserva fraccion exacta 1/16 (0.0625) para descuento de stock en esta venta',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 960));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final torta = _buildProduct(
          id: 96,
          name: 'Torta Selva Negra',
          internalCode: '00096',
          barcode: '7790009600962',
          price: 4000,
        );
        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider(
          localProducts: [torta],
          remoteProducts: [torta],
        );

        PosQuickItemResult? capturedResult;
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<CatalogProvider>.value(value: catProv),
              ChangeNotifierProvider<OfferProvider>.value(
                  value: _FakeOfferProvider()),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: _FakeSettingsProvider()),
              ChangeNotifierProvider<SupplierProvider>.value(
                  value: _FakeSupplierProvider()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () async {
                      capturedResult = await showDialog<PosQuickItemResult>(
                        context: ctx,
                        builder: (_) => const PosQuickItemDialog(),
                      );
                    },
                    child: const Text('Abrir Temporal'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Abrir Temporal'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Combo / Fracción'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Buscar o pistolear producto para incluir en el combo...',
          ),
          'Selva',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Torta Selva Negra'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('1/x'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('quick_combo_parts_96')), '16');
        await tester.tap(find.byKey(const Key('quick_combo_apply_parts_96')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Nombre del Combo / Fracción *'),
          'Porción Selva Temporal',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Precio Venta Unit. *'),
          '350',
        );
        await tester.tap(find.text('Agregar al Carrito (Enter)'));
        await tester.pumpAndSettle();

        expect(capturedResult, isNotNull);
        expect(capturedResult!.item.saveToCatalog, isFalse);
        expect(capturedResult!.item.isTemporary, isTrue);
        expect(capturedResult!.item.product.comboIngredients?.first['quantity'], 0.0625);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PosQuickItemDialog: conserva código de barras escaneado (initialQuery) en Product y toSalePayload()',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1280, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final posProv = _FakePosProvider();
        final catProv = _FakeCatalogProvider();
        PosQuickItemResult? capturedResult;

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<CatalogProvider>.value(value: catProv),
              ChangeNotifierProvider<OfferProvider>.value(
                  value: _FakeOfferProvider()),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: _FakeSettingsProvider()),
              ChangeNotifierProvider<SupplierProvider>.value(
                  value: _FakeSupplierProvider()),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () async {
                      capturedResult = await PosQuickItemDialog.show(
                        ctx,
                        initialQuery: '7798765432109',
                      );
                    },
                    child: const Text('Crear Desde Escaneo'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Crear Desde Escaneo'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Descripción del Producto *'),
          'Galletitas Escaneadas',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Precio Venta Unit. *'),
          '1800',
        );
        await tester.tap(find.text('Agregar al Carrito (Enter)'));
        await tester.pumpAndSettle();

        expect(capturedResult, isNotNull);
        expect(capturedResult!.item.saveToCatalog, isTrue);
        expect(capturedResult!.item.product.barcode, '7798765432109');
        expect(capturedResult!.item.customDetails, isNull);
        final payload = capturedResult!.item.toSalePayload();
        expect(payload['save_to_catalog'], isTrue);
        expect(payload['barcode'], '7798765432109');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
