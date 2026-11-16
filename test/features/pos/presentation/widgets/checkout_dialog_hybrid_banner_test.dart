import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/entities/cart_item.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/checkout_dialog.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _HybridFakeSettingsProvider extends ChangeNotifier
    implements SettingsProvider {
  final BusinessSettings _settings = const BusinessSettings(
    companyName: 'Test POS',
    enableAdvancedPriceTiers: true,
    globalCardPercentage: 15.0,
    globalWholesalePercentage: -15.0,
    cardSurchargeOnOffersMode: 'surcharge_on_offer',
    discountTierOnOffersMode: 'best_price_wins',
    features: FeatureFlags(
      multiplePrices: true,
      currentAccounts: false,
      checks: false,
      logistics: false,
    ),
  );

  @override
  BusinessSettings? get settings => _settings;
  @override
  FeatureFlags get features => _settings.features;
  @override
  bool get isIibbPerceptionAgent => false;
  @override
  bool get isHardwareStore => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HybridFakeLocalTerminal extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  bool get autoOpenCashDrawer => false;
  @override
  String get terminalId => 'caja-1';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HybridFakeAuth extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser => {'id': 1, 'name': 'Cajero Hybrid'};
  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HybridFakeCustomer extends ChangeNotifier implements CustomerProvider {
  @override
  List<Customer> get customers => const [];
  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HybridFakeCashRegister extends ChangeNotifier
    implements CashRegisterProvider {
  @override
  CashRegisterShift? get currentShift => CashRegisterShift(
        id: 1,
        cashRegisterId: 1,
        userId: 1,
        openedAt: DateTime.now(),
        openingBalance: 10000.0,
        status: 'open',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _HybridFakeCatalog extends ChangeNotifier implements CatalogProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Fase 3 CheckoutDialog: muestra banner híbrido cuando el carrito tiene Lista Tarjeta y se selecciona Efectivo, y permite pasar todo a Minorista en 1 clic',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final paymentMethodsPayload = [
        {
          'id': 1,
          'name': 'Efectivo',
          'code': 'cash',
          'surcharge_type': 'none',
          'surcharge_value': 0.0,
          'is_cash': true,
          'is_active': true,
          'sort_order': 1,
        },
        {
          'id': 2,
          'name': 'Tarjeta Crédito',
          'code': 'credit_card',
          'surcharge_type': 'percent',
          'surcharge_value': 15.0,
          'is_cash': false,
          'is_active': true,
          'sort_order': 2,
        },
      ];

      final mockHttp = MockClient((request) async {
        if (request.url.path.endsWith('/payment-methods')) {
          return http.Response(jsonEncode(paymentMethodsPayload), 200);
        }
        return http.Response('{}', 200);
      });

      final apiClient = ApiClient(mockHttp);
      final ds = PosRemoteDataSourceImpl(
          baseUrl: 'http://localhost/api', client: mockHttp);
      final repo = PosRepositoryImpl(remoteDataSource: ds);
      final posProv = PosProvider(
        processSaleUseCase: ProcessSaleUseCase(repo),
        searchProductsUseCase: SearchProductsUseCase(repo),
        repository: repo,
        remoteDataSource: ds,
      );
      await posProv.loadPaymentMethods();

      final ps5 = Product(
        id: 1,
        name: 'CONSOLA PLAY STATION 5 PRO DIGITAL 2TB',
        internalCode: '00001',
        costPrice: 2500000.0,
        sellingPrice: 3250000.0,
        stock: 8.0,
        active: true,
        isSoldByWeight: false,
      );
      posProv.requestAddToCartWithPromo(
        ps5,
        promotionalPrice: 2600000.0,
        promotionalLabel: 'Oferta Semanal',
        promotionalPeriodType: 'weekly',
      );
      posProv.setPriceTier(
        PriceTier.card,
        wholesaleFactor: 0.85,
        cardFactor: 1.15,
      );
      expect(posProv.activeTier, PriceTier.card);
      expect(posProv.cartTotal, 2990000.0);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProv),
            ChangeNotifierProvider<SettingsProvider>(
                create: (_) => _HybridFakeSettingsProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>(
                create: (_) => _HybridFakeLocalTerminal()),
            ChangeNotifierProvider<AuthProvider>(
                create: (_) => _HybridFakeAuth()),
            ChangeNotifierProvider<CustomerProvider>(
                create: (_) => _HybridFakeCustomer()),
            ChangeNotifierProvider<CashRegisterProvider>(
                create: (_) => _HybridFakeCashRegister()),
            ChangeNotifierProvider<CatalogProvider>(
                create: (_) => _HybridFakeCatalog()),
            Provider<ApiClient>.value(value: apiClient),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: CheckoutDialog(total: posProv.cartTotal),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Por defecto selecciona Efectivo con Lista Tarjeta activa -> aparece banner híbrido
      expect(find.byKey(const ValueKey('hybrid_card_tier_banner')), findsOneWidget);
      expect(
        find.textContaining('Atención: Todo el carrito tiene recargo de Lista Tarjeta.'),
        findsOneWidget,
      );
      final convertBtn = find.byKey(const ValueKey('convert_cart_to_retail_btn'));
      expect(convertBtn, findsOneWidget);

      await tester.ensureVisible(convertBtn);
      await tester.tap(convertBtn);
      await tester.pumpAndSettle();

      // Carrito pasa a Minorista (Base), recargo global eliminado y banner desaparece
      expect(posProv.activeTier, PriceTier.base);
      expect(posProv.cart.first.activeTier, PriceTier.base);
      expect(posProv.cartTotal, 2600000.0);
      expect(find.byKey(const ValueKey('hybrid_card_tier_banner')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
