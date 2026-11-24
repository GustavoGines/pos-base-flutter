import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/presentation/widgets/app_modal_shell.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/theme/app_theme.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/brand.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/category.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/offers/data/models/offer_model.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_hardware_calculator_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_price_lookup_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_customer_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_quick_quotes_dialog.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/pos_rename_cart_item_dialog.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/presentation/providers/quote_provider.dart';
import 'package:frontend_desktop/features/quotes/presentation/widgets/quote_success_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _PhaseBFakePosProvider extends ChangeNotifier implements PosProvider {
  final List<CartItem> _cart;
  Customer? _selectedCustomer;

  _PhaseBFakePosProvider({List<CartItem>? initialCart})
      : _cart = initialCart ?? [];

  @override
  List<CartItem> get cart => _cart;

  @override
  Customer? get selectedCustomer => _selectedCustomer;

  @override
  double get cartSubtotal =>
      _cart.fold(0.0, (sum, item) => sum + item.subtotal);

  @override
  void selectCustomer(Customer? customer, {bool? isPerceptionAgent}) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  @override
  PriceTier get activeTier => PriceTier.base;

  @override
  double get wholesaleFactor => 0.9;

  @override
  double get cardFactor => 1.1;

  @override
  double get currentCustomFactor => 1.0;

  @override
  String? get customTierLabel => null;

  @override
  CardSurchargeOnOffersMode get cardSurchargeOnOffersMode =>
      CardSurchargeOnOffersMode.surchargeOnOffer;

  @override
  DiscountTierOnOffersMode get discountTierOnOffersMode =>
      DiscountTierOnOffersMode.bestPriceWins;

  @override
  bool get ignoreProductFixedPrices => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhaseBFakeQuoteProvider extends ChangeNotifier implements QuoteProvider {
  @override
  bool get isLoading => false;

  @override
  List<Quote> get quotes => const [];

  @override
  Future<void> loadQuotes({String? search, String? status}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhaseBFakeCustomerProvider extends ChangeNotifier
    implements CustomerProvider {
  final List<Customer> _customers;

  _PhaseBFakeCustomerProvider(this._customers);

  @override
  bool get isLoading => false;

  @override
  List<Customer> get customers => _customers;

  @override
  Future<void> fetchCustomers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhaseBFakeCatalogProvider extends ChangeNotifier
    implements CatalogProvider {
  @override
  List<Product> get products => const [];

  @override
  List<Category> get categories => const [];

  @override
  List<Brand> get brands => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhaseBFakeOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  List<OfferModel> get activeOffers => const [];

  @override
  List<OfferModel> get allOffers => const [];

  @override
  bool get isLoadingActive => false;

  @override
  OfferModel? getActiveOfferForProduct(int productId, {double? basePrice}) =>
      null;

  @override
  double? getDiscountedPrice(Product product) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PhaseBFakeSettingsProvider extends ChangeNotifier
    implements SettingsProvider {
  final BusinessSettings _settings;

  _PhaseBFakeSettingsProvider({bool hardwareMode = true})
      : _settings = BusinessSettings(
          businessType: hardwareMode ? 'hardware_store' : 'retail',
          licenseStatus: 'active',
          licensePlanType: 'premium',
          features: const FeatureFlags(suppliers: false),
        );

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isHardwareStore => _settings.isHardwareStore;

  @override
  FeatureFlags get features => _settings.features;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Product _sampleWoodProduct() => Product(
      id: 101,
      name: 'Machimbre Eucalipto 3/4" x 6" x 4.00m',
      internalCode: 'HW101',
      costPrice: 1450,
      sellingPrice: 2350,
      stock: 40,
      active: true,
      isSoldByWeight: false,
    );

Widget _wrapModal({
  required Widget child,
  _PhaseBFakePosProvider? posProvider,
  _PhaseBFakeQuoteProvider? quoteProvider,
  _PhaseBFakeCustomerProvider? customerProvider,
  _PhaseBFakeSettingsProvider? settingsProvider,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PosProvider>.value(
        value: posProvider ?? _PhaseBFakePosProvider(),
      ),
      ChangeNotifierProvider<QuoteProvider>.value(
        value: quoteProvider ?? _PhaseBFakeQuoteProvider(),
      ),
      ChangeNotifierProvider<CustomerProvider>.value(
        value: customerProvider ??
            _PhaseBFakeCustomerProvider([
              Customer(
                id: 1,
                name: 'Gustavo Gines',
                documentNumber: '39606329',
                documentType: 96,
                creditLimit: 50000,
                balance: 0,
                isActive: true,
              ),
            ]),
      ),
      ChangeNotifierProvider<CatalogProvider>.value(
        value: _PhaseBFakeCatalogProvider(),
      ),
      ChangeNotifierProvider<OfferProvider>.value(
        value: _PhaseBFakeOfferProvider(),
      ),
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settingsProvider ?? _PhaseBFakeSettingsProvider(),
      ),
      ChangeNotifierProvider<LocalTerminalProvider>(
        create: (_) => LocalTerminalProvider(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'disable_pusher': true});
  });

  group('Fase B - Unificación Dark Navy y Anti-Overflow en Modales POS', () {
    const viewports = [Size(1366, 768), Size(800, 600)];

    testWidgets(
      'PosQuickQuotesDialog usa AppModalHeader/Footer, corrige singular y alterna footer por pestaña sin overflow',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final viewport in viewports) {
          await tester.binding.setSurfaceSize(viewport);
          final pos = _PhaseBFakePosProvider(
            initialCart: [CartItem(product: _sampleWoodProduct(), quantity: 1)],
          );

          await tester.pumpWidget(
            _wrapModal(
              posProvider: pos,
              child: const PosQuickQuotesDialog(),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppModalHeader), findsOneWidget);
          expect(find.byType(AppModalFooter), findsOneWidget);
          expect(find.text('1 producto en el ticket'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AppModalFooter),
              matching: find.text('Generar y Guardar Presupuesto'),
            ),
            findsOneWidget,
          );

          await tester.tap(find.text('Recuperar Presupuesto'));
          await tester.pumpAndSettle();

          expect(
            find.descendant(
              of: find.byType(AppModalFooter),
              matching: find.text('Cerrar (Esc)'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      'PosQuickCustomerDialog y PosPriceLookupDialog renderizan AppModalHeader y AppModalFooter sin overflow en 1366x768 y 800x600',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final viewport in viewports) {
          await tester.binding.setSurfaceSize(viewport);

          await tester.pumpWidget(
            _wrapModal(child: const PosQuickCustomerDialog()),
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppModalHeader), findsOneWidget);
          expect(find.byType(AppModalFooter), findsOneWidget);
          expect(find.text('Gestión Rápida de Cliente'), findsOneWidget);
          expect(find.text('Gustavo Gines'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          await tester.pumpWidget(
            _wrapModal(child: const PosPriceLookupDialog()),
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppModalHeader), findsOneWidget);
          expect(find.byType(AppModalFooter), findsOneWidget);
          expect(
            find.text('Consultar Precio sin Agregar (F5)'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      'PosRenameCartItemDialog y QuoteSuccessDialog usan AppModalShell/Footer sin overflow en 1366x768 y 800x600',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final viewport in viewports) {
          await tester.binding.setSurfaceSize(viewport);

          final item = CartItem(product: _sampleWoodProduct(), quantity: 1);
          await tester.pumpWidget(
            _wrapModal(
              child: PosRenameCartItemDialog(
                item: item,
                onOpenHardwareCalculator: () {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppModalHeader), findsOneWidget);
          expect(find.byType(AppModalFooter), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AppModalFooter),
              matching: find.text('Recalcular por m² / Medidas'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(AppModalFooter),
              matching: find.text('Aplicar en Comprobante (Enter)'),
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();

          final quote = Quote(
            id: 99,
            quoteNumber: 'PRES-0099',
            status: 'pending',
            subtotal: 2350,
            total: 2350,
            items: [
              QuoteItem(
                productId: 101,
                productName: _sampleWoodProduct().name,
                unitPrice: 2350,
                quantity: 1,
                subtotal: 2350,
              ),
            ],
          );
          await tester.pumpWidget(
            _wrapModal(
              child: QuoteSuccessDialog(
                quote: quote,
                businessName: 'Ferretería Test',
                vendorName: 'Vendedor',
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(AppModalHeader), findsOneWidget);
          expect(find.byType(AppModalFooter), findsOneWidget);
          expect(find.text('¡Presupuesto Generado!'), findsOneWidget);
          expect(find.text('Imprimir Ticket (Térmica)'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );

    testWidgets(
      'PosHardwareCalculatorDialog muestra Complementos sugeridos sin scrollear y aclara cobertura/unitario singular en Techos',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final roofProduct = Product(
          id: 202,
          name: 'Chapa Trapezoidal C25 Prepintada Negra 1.10 x 6.00m',
          internalCode: 'HW202',
          costPrice: 45000,
          sellingPrice: 68500,
          stock: 40,
          active: true,
          isSoldByWeight: false,
          calcConfig: const {
            'type': 'roof',
            'nominal_width_m': 1.10,
            'useful_width_m': 1.00,
            'length_m': 6.00,
            'longitudinal_overlap_m': 0.20,
            'pricing_mode': 'per_sheet',
          },
        );

        for (final viewport in const [Size(1440, 900), Size(1280, 800)]) {
          tester.view.physicalSize = viewport;
          await tester.pumpWidget(
            _wrapModal(
              child: PosHardwareCalculatorDialog(
                initialProduct: roofProduct,
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Ingresar techo 10 x 10.5m
          await tester.enterText(
            find.widgetWithText(
                TextField, 'Ancho del Techo (perpendicular a la caída)'),
            '10',
          );
          await tester.enterText(
            find.widgetWithText(
                TextField, 'Largo de la Caída / Agua (pendiente)'),
            '10.5',
          );
          await tester.pumpAndSettle();

          expect(find.text('20 Chapas de 6m'), findsOneWidget);
          expect(find.textContaining('cubre 11.8m p/ 10.5m'), findsWidgets);
          expect(find.textContaining('sobra 1.3m/hilada'), findsOneWidget);
          expect(find.text('Unitario: \$68.500 / chapa'), findsOneWidget);

          // Verificar que "Complementos sugeridos" entra completo sin scrollear dentro del TabBarView
          final tabViewRect = tester.getRect(find.byType(TabBarView));
          final complementsFinder = find.text('Complementos sugeridos:');
          expect(complementsFinder, findsOneWidget);
          final complementsRect = tester.getRect(complementsFinder);
          expect(
            complementsRect.bottom,
            lessThanOrEqualTo(tabViewRect.bottom),
            reason:
                'Complementos sugeridos quedó cortado en viewport ${viewport.width}x${viewport.height} (tabView=$tabViewRect, complements=$complementsRect)',
          );

          // Probar modo m² Directos (Estimado) en Chapas: sincroniza m², calcula con margen y mantiene Complementos visibles sin scroll
          await tester.tap(find.text('m² Directos'));
          await tester.pumpAndSettle();

          expect(find.byKey(const ValueKey('roof_direct_m2_field')), findsOneWidget);
          expect(
            find.textContaining('Cálculo orientativo por superficie'),
            findsOneWidget,
          );

          await tester.enterText(
            find.byKey(const ValueKey('roof_direct_m2_field')),
            '40',
          );
          await tester.pumpAndSettle();

          // 40 m² + 10% = 44 m² / (1.0m x 6.0m) => 8 chapas
          expect(find.text('8 Chapas de 6m'), findsOneWidget);
          expect(find.textContaining('Estimado p/ 40 m² (+10%)'), findsOneWidget);

          // Verificar que con 0% Exacto recalcula a 7 chapas (ceil(40/6) = 7)
          await tester.tap(find.text('0% (Exacto)'));
          await tester.pumpAndSettle();
          expect(find.text('7 Chapas de 6m'), findsOneWidget);

          // Complementos sugeridos siguen visibles sin scrollear también en modo m² Directos
          final directComplementsRect =
              tester.getRect(find.text('Complementos sugeridos:'));
          expect(
            directComplementsRect.bottom,
            lessThanOrEqualTo(tabViewRect.bottom),
            reason:
                'Complementos sugeridos en m² Directos quedó cortado en ${viewport.width}x${viewport.height}',
          );

          // Verificar también Machimbre / Maderas y Pintura / Membrana sin banner de cambio de tab en 1280x800, y aún con banner en 1440x900
          if (viewport.width >= 1400) {
            await tester.tap(find.text('🪵 Machimbre / Maderas'));
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.text('Complementos sugeridos:')).bottom,
              lessThanOrEqualTo(
                  tester.getRect(find.byType(TabBarView)).bottom),
            );

            await tester.tap(find.text('🎨 Pintura / Membrana'));
            await tester.pumpAndSettle();
            expect(
              tester.getRect(find.text('Complementos sugeridos:')).bottom,
              lessThanOrEqualTo(
                  tester.getRect(find.byType(TabBarView)).bottom),
            );
          }

          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      },
    );
  });
}
