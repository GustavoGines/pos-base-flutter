import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/network/api_client.dart';
import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/services/license_heartbeat_service.dart';
import 'package:frontend_desktop/core/utils/iibb_fiscal_calculator.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/domain/entities/product.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:frontend_desktop/features/pos/data/repositories/pos_repository_impl.dart';
import 'package:frontend_desktop/features/pos/domain/entities/payment_method.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/process_sale_usecase.dart';
import 'package:frontend_desktop/features/pos/domain/usecases/search_products_usecase.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/widgets/checkout_dialog.dart';
import 'package:frontend_desktop/features/quotes/data/quote_repository.dart';
import 'package:frontend_desktop/features/quotes/services/quote_pdf_service.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/settings/data/models/business_settings_model.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/pages/settings_screen.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

class _TestPosProviderWithPreviewGate extends PosProvider {
  Completer<bool>? pendingResultCompleter;
  bool clearCartBeforePreview = true;
  int checkoutCalls = 0;

  _TestPosProviderWithPreviewGate({
    required super.processSaleUseCase,
    required super.searchProductsUseCase,
    required super.repository,
    required super.remoteDataSource,
  });

  final List<PaymentMethod> _stubMethods = [
    PaymentMethod(
      id: 1,
      name: 'Efectivo',
      code: 'efectivo',
      surchargeType: 'none',
      surchargeValue: 0.0,
      isCash: true,
      isActive: true,
      sortOrder: 1,
    ),
  ];

  @override
  List<PaymentMethod> get paymentMethods => _stubMethods;

  @override
  Future<bool> processCheckout({
    required int shiftId,
    required double totalSurcharge,
    required List<Map<String, dynamic>> payments,
    required double tenderedAmount,
    required double changeAmount,
    required String printerFormat,
    required LocalTerminalProvider localTerminal,
    int? userId,
    int? customerId,
    String? userName,
    BusinessSettings? settings,
    bool showPreview = true,
    bool requiresDispatch = false,
    String fulfillmentStatus = 'pending',
    dynamic checkDetails,
    double? iibbPerceptionAmount,
    double? iibbPerceptionRate,
    String? deliveryAddress,
    String? clientTransactionId,
  }) async {
    checkoutCalls++;
    if (clearCartBeforePreview) {
      // Simula exactamente PosProvider.processCheckout: clearCart() corre ANTES de cerrar AppPdfPreviewModal
      clearCart();
    }
    final completer = pendingResultCompleter;
    if (completer != null) {
      return await completer.future;
    }
    return true;
  }
}

class _FakeIibbSettingsProvider extends ChangeNotifier
    implements SettingsProvider {
  BusinessSettings _settings;
  Map<String, dynamic>? savedPayload;

  _FakeIibbSettingsProvider(this._settings);

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isIibbPerceptionAgent => _settings.isIibbPerceptionAgent;

  @override
  double get defaultIibbPerceptionRate => _settings.defaultIibbPerceptionRate;

  @override
  String get iibbCalculationBase => _settings.iibbCalculationBase;

  @override
  List<String> get iibbSubjectTaxConditions =>
      _settings.iibbSubjectTaxConditions;

  @override
  bool get isResponsableInscripto => _settings.isResponsableInscripto;

  @override
  int get assignedRegisterId => 1;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  String get currentPlan => _settings.licensePlanType ?? 'premium';

  @override
  FeatureFlags get features => _settings.features;

  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  bool get isLicenseActive => true;

  @override
  List<String> get allowedAddons => _settings.licenseFeatures;

  @override
  LicenseSecurityStatus get securityStatus => LicenseSecurityStatus.ok;

  @override
  String get currentApiUrl => 'https://pos-backend.test/api';

  @override
  void updateBaseUrl(String newUrl) {}

  @override
  Map<String, dynamic>? get integrations => const {
        'mp_qr_enabled': false,
        'afip_enabled': true,
        'afip_cuit': '30500010912',
        'afip_pto_vta': 1,
        'afip_environment': 'testing',
        'afip_has_cert': true,
        'afip_has_key': true,
      };

  @override
  bool get isLoadingIntegrations => false;

  @override
  Future<Map<String, dynamic>?> loadIntegrations({bool isSilent = false}) async =>
      integrations;

  @override
  Future<bool> saveSettings(Map<String, dynamic> data) async {
    savedPayload = Map<String, dynamic>.from(data);
    _settings = _settings.copyWith(
      isIibbPerceptionAgent: data['is_iibb_perception_agent'] == '1',
      defaultIibbPerceptionRate:
          (data['default_iibb_perception_rate'] as num?)?.toDouble() ??
              _settings.defaultIibbPerceptionRate,
      iibbCalculationBase:
          data['iibb_calculation_base']?.toString() ??
              _settings.iibbCalculationBase,
      iibbSubjectTaxConditions: IibbFiscalCalculator.normalizeSubjectConditions(
        data['iibb_subject_tax_conditions'],
      ),
    );
    notifyListeners();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser =>
      {'id': 1, 'name': 'Admin IIBB', 'role': 'admin'};

  @override
  bool get isAdmin => true;

  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerProvider extends ChangeNotifier
    implements CustomerProvider {
  @override
  List<Customer> get customers => const [];

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchCustomers({String? search}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  @override
  List<CashRegister>? get availableRegisters => const [];

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
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
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
  String get terminalId => 'caja-1';

  @override
  String get lockedPriceTier => 'none';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  List<dynamic> get alerts => const [];

  @override
  List<dynamic> get reactiveAlerts => const [];

  @override
  List<dynamic> get predictiveCriticalAlerts => const [];

  @override
  int get totalAlertsCount => 0;

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PosProvider _createRealPosProvider() {
  final client = MockClient((_) async => http.Response('[]', 200));
  final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: client);
  final repo = PosRepositoryImpl(remoteDataSource: ds);
  return PosProvider(
    processSaleUseCase: ProcessSaleUseCase(repo),
    searchProductsUseCase: SearchProductsUseCase(repo),
    repository: repo,
    remoteDataSource: ds,
  );
}

_TestPosProviderWithPreviewGate _createPreviewGatePosProvider() {
  final client = MockClient((_) async => http.Response('[]', 200));
  final ds = PosRemoteDataSourceImpl(baseUrl: 'http://localhost/api', client: client);
  final repo = PosRepositoryImpl(remoteDataSource: ds);
  return _TestPosProviderWithPreviewGate(
    processSaleUseCase: ProcessSaleUseCase(repo),
    searchProductsUseCase: SearchProductsUseCase(repo),
    repository: repo,
    remoteDataSource: ds,
  );
}

String _extractPdfText(List<int> pdfBytes) {
  final rawLatin = latin1.decode(pdfBytes, allowInvalid: true);
  final buffer = StringBuffer(rawLatin);
  final streamRegex = RegExp(r'/Length\s+(\d+)>>stream\r?\n');
  for (final match in streamRegex.allMatches(rawLatin)) {
    final len = int.tryParse(match.group(1) ?? '');
    if (len == null || len <= 0) continue;
    final dataStart = match.end;
    final dataEnd = dataStart + len;
    if (dataEnd <= pdfBytes.length) {
      try {
        final decoded = ZLibDecoder().convert(pdfBytes.sublist(dataStart, dataEnd));
        final text = latin1.decode(decoded, allowInvalid: true);
        buffer.write('\n');
        buffer.write(text);
        buffer.write('\n');
        // Unir literales de cadena PDF separados por palabra/kerning en BT ... [(word)]TJ ET
        final words = RegExp(r'\[\(((?:\\.|[^()])*)\)\]TJ')
            .allMatches(text)
            .map((m) => (m.group(1) ?? '')
                .replaceAll(r'\(', '(')
                .replaceAll(r'\)', ')'))
            .join(' ');
        buffer.write('\n');
        buffer.write(words);
      } catch (_) {}
    }
  }
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'pos_terminal_id': 'caja-1',
      'pos_api': 'https://pos-backend.test/api',
    });
    PackageInfo.setMockInitialValues(
      appName: 'Caja4U',
      packageName: 'com.dev4u.pos',
      version: '2.1.2',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('IibbFiscalCalculator & BusinessSettingsModel', () {
    test('parsea y serializa iibb_calculation_base y iibb_subject_tax_conditions excluyendo Consumidor Final', () {
      final model = BusinessSettingsModel.fromJson({
        'is_iibb_perception_agent': '1',
        'default_iibb_perception_rate': '3.00',
        'iibb_calculation_base': 'gross_with_vat',
        'iibb_subject_tax_conditions':
            '["responsable_inscripto","monotributo","consumidor_final"]',
      });

      expect(model.iibbCalculationBase, IibbFiscalCalculator.baseGrossWithVat);
      expect(model.isIibbGrossBase, isTrue);
      expect(
        model.iibbSubjectTaxConditions,
        equals(['responsable_inscripto', 'monotributo']),
      );
      expect(model.isTaxConditionSubjectToIibb('responsable_inscripto'), isTrue);
      expect(model.isTaxConditionSubjectToIibb('monotributo'), isTrue);
      expect(model.isTaxConditionSubjectToIibb('exento'), isFalse);
      expect(model.isTaxConditionSubjectToIibb('consumidor_final'), isFalse);
    });

    test('calculateBreakdown respeta net_without_vat y gross_with_vat con alícuotas 21%, 10.5% y 0%', () {
      const lines = [
        IibbTaxableLine(subtotal: 12100.00, ivaRate: 21.0), // Neto 10000, IVA 2100
        IibbTaxableLine(subtotal: 11050.00, ivaRate: 10.5), // Neto 10000, IVA 1050
        IibbTaxableLine(subtotal: 1000.00, ivaRate: 0.0), // Neto 1000, IVA 0
      ];

      final netMode = IibbFiscalCalculator.calculateBreakdown(
        lines: lines,
        iibbRate: 3.0,
        calculationBase: IibbFiscalCalculator.baseNetWithoutVat,
      );
      expect(netMode.netAmount, 21000.00);
      expect(netMode.ivaAmount, 3150.00);
      expect(netMode.tributeBaseImp, 21000.00);
      expect(netMode.iibbAmount, 630.00);
      expect(
        IibbFiscalCalculator.round2(
            netMode.netAmount + netMode.ivaAmount + netMode.iibbAmount),
        netMode.grandTotal,
      );

      final grossMode = IibbFiscalCalculator.calculateBreakdown(
        lines: lines,
        iibbRate: 3.0,
        calculationBase: IibbFiscalCalculator.baseGrossWithVat,
      );
      expect(grossMode.tributeBaseImp, 24150.00);
      expect(grossMode.iibbAmount, 724.50);
      expect(grossMode.grandTotal, 24874.50);
      expect(
        IibbFiscalCalculator.round2(
            grossMode.netAmount + grossMode.ivaAmount + grossMode.iibbAmount),
        grossMode.grandTotal,
      );
    });

    test('Despeje inverso + applyAgreedTotalRounding cierra al centavo exacto en 21%, 10.5%, 0% y carritos mixtos en ambas bases', () {
      final prod21 = Product(
        id: 1,
        name: 'Pintura 20L',
        internalCode: 'P21',
        costPrice: 10000,
        sellingPrice: 22900.0,
        ivaRate: 21.0,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );
      final prod105 = Product(
        id: 2,
        name: 'Compresor 10.5%',
        internalCode: 'P105',
        costPrice: 5000,
        sellingPrice: 11050.0,
        ivaRate: 10.5,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );
      final prod0 = Product(
        id: 3,
        name: 'Folleto Exento',
        internalCode: 'P0',
        costPrice: 500,
        sellingPrice: 1000.0,
        ivaRate: 0.0,
        stock: 50,
        active: true,
        isSoldByWeight: false,
      );

      final riCustomer = Customer(
        id: 10,
        name: 'Cliente RI SA',
        documentNumber: '30500010912',
        documentType: 80,
        taxCondition: 'responsable_inscripto',
        creditLimit: 0.0,
        balance: 0.0,
        isActive: true,
        appliesIibbPerception: true,
        iibbPerceptionRate: 3.0,
      );

      final scenarios = <({String name, List<Product> products, double target, String base})>[
        (name: '21% neto absorber 22900', products: [prod21], target: 22900.00, base: IibbFiscalCalculator.baseNetWithoutVat),
        (name: '21% bruto absorber 22900', products: [prod21], target: 22900.00, base: IibbFiscalCalculator.baseGrossWithVat),
        (name: '10.5% neto pactar 10500', products: [prod105], target: 10500.00, base: IibbFiscalCalculator.baseNetWithoutVat),
        (name: '10.5% bruto pactar 10500', products: [prod105], target: 10500.00, base: IibbFiscalCalculator.baseGrossWithVat),
        (name: '0% neto pactar 1000', products: [prod0], target: 1000.00, base: IibbFiscalCalculator.baseNetWithoutVat),
        (name: 'Mixto 21+10.5+0 neto pactar 23000', products: [prod21, prod105, prod0], target: 23000.00, base: IibbFiscalCalculator.baseNetWithoutVat),
        (name: 'Mixto 21+10.5+0 bruto pactar 23000', products: [prod21, prod105, prod0], target: 23000.00, base: IibbFiscalCalculator.baseGrossWithVat),
      ];

      for (final sc in scenarios) {
        final pos = _createRealPosProvider();
        for (final p in sc.products) {
          pos.requestAddToCartWithPromo(p);
        }
        pos.selectCustomer(riCustomer, isPerceptionAgent: true);
        pos.setDefaultIibbPerceptionRate(3.0);
        pos.setIibbCalculationBase(sc.base);

        final lines = pos.cart
            .map((c) => IibbTaxableLine(
                  subtotal: c.subtotal,
                  ivaRate: c.product.ivaRate,
                ))
            .toList();

        final sol = IibbFiscalCalculator.solveAgreedGrandTotal(
          lines: lines,
          targetGrandTotal: sc.target,
          iibbRate: 3.0,
          calculationBase: sc.base,
        );

        pos.applyAgreedTotalRounding(sol.merchandiseTotal);

        final recomputedIibb = pos.calculateIibbPerceptionAmount();
        final recomputedBreakdown = IibbFiscalCalculator.calculateBreakdown(
          lines: pos.cart
              .map((c) => IibbTaxableLine(
                    subtotal: c.subtotal,
                    ivaRate: c.product.ivaRate,
                  ))
              .toList(),
          iibbRate: 3.0,
          calculationBase: sc.base,
        );

        // 1. PosProvider coincide exacto al centavo con IibbFiscalCalculator / AfipWsfeService
        expect(recomputedIibb, equals(recomputedBreakdown.iibbAmount),
            reason: '${sc.name}: PosProvider vs AFIP IIBB mismatch');
        // 2. Ecuación ARCA ImpTotal == ImpNeto + ImpIVA + ImpTrib cierra con 0.00 de desvío
        expect(
          IibbFiscalCalculator.round2(recomputedBreakdown.netAmount +
              recomputedBreakdown.ivaAmount +
              recomputedBreakdown.iibbAmount),
          equals(recomputedBreakdown.grandTotal),
          reason: '${sc.name}: ImpTotal != ImpNeto + ImpIVA + ImpTrib',
        );
        // 3. El total alcanzado iguala el pactado (o -0.01 si salto discreto de 2c)
        final deltaFromTarget =
            IibbFiscalCalculator.round2(sc.target - recomputedBreakdown.grandTotal);
        expect(deltaFromTarget == 0.0 || deltaFromTarget == 0.01, isTrue,
            reason: '${sc.name}: delta inesperado $deltaFromTarget');
      }
    });
  });

  group('CheckoutDialog Snapshot Vista Previa', () {
    testWidgets('No parpadea Saldo Pendiente negativo (-\$567,77) tras clearCart durante Vista Previa', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 860));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final posProvider = _createPreviewGatePosProvider();
      final pintProduct = Product(
        id: 50,
        name: 'Látex Interior 4L',
        internalCode: 'PIN-04',
        costPrice: 12000.0,
        sellingPrice: 22900.0,
        ivaRate: 21.0,
        stock: 20,
        active: true,
        isSoldByWeight: false,
      );
      final riCustomer = Customer(
        id: 77,
        name: 'Pinturería Norte SRL',
        documentNumber: '30500010912',
        documentType: 80,
        taxCondition: 'responsable_inscripto',
        creditLimit: 0.0,
        balance: 0.0,
        isActive: true,
        appliesIibbPerception: true,
        iibbPerceptionRate: 3.0,
      );

      posProvider.requestAddToCartWithPromo(pintProduct);
      posProvider.selectCustomer(riCustomer, isPerceptionAgent: true);
      posProvider.setDefaultIibbPerceptionRate(3.0);

      final completer = Completer<bool>();
      posProvider.pendingResultCompleter = completer;

      final settingsProvider = _FakeIibbSettingsProvider(
        const BusinessSettings(
          companyName: 'Corralón Test',
          taxId: '30-50001091-2',
          taxCondition: 'IVA Responsable Inscripto',
          afipEnabled: true,
          isIibbPerceptionAgent: true,
          defaultIibbPerceptionRate: 3.0,
          licenseStatus: 'LIC-TEST',
          licensePlanType: 'premium',
          features: FeatureFlags(fastPos: true, arcaAfip: true),
        ),
      );

      bool popped = false;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: _FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<CustomerProvider>.value(value: _FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: _FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: _FakeCatalogProvider()),
            Provider<ApiClient>.value(
              value: ApiClient(MockClient((_) async => http.Response('{}', 200))),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await showDialog<bool>(
                        context: ctx,
                        builder: (_) => const CheckoutDialog(total: 22900.0),
                      );
                      popped = true;
                    },
                    child: const Text('ABRIR'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ABRIR'));
      await tester.pumpAndSettle();

      // Verifica el Gran Total inicial con Percepción IIBB ($22.900 + $567,77 = $23.467,77)
      // y el saldo cubierto en verde ($0, sin "Monto Excedido:").
      expect(find.textContaining('23.467,77'), findsWidgets);
      expect(find.text('Saldo Pendiente a Cubrir:'), findsOneWidget);
      expect(find.text('Monto Excedido:'), findsNothing);
      expect(find.text('\$0'), findsWidgets);

      // Dispara el cobro; dentro de processCheckout se limpia el carrito ANTES de cerrar la Vista Previa
      await tester.tap(find.widgetWithText(ElevatedButton, 'CONFIRMAR PAGO'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(posProvider.checkoutCalls, 1);
      expect(posProvider.cart, isEmpty);
      expect(popped, isFalse);

      // BUG FIX VERIFICADO: mientras el carrito está vacío esperando el cierre de Vista Previa,
      // _frozenIibbAmount mantiene $567,77 y NO cambia a "Monto Excedido: $567,77" ni aparece en rojo.
      expect(find.text('Monto Excedido:'), findsNothing);
      expect(find.text('Saldo Pendiente a Cubrir:'), findsOneWidget);
      final zeroTexts = tester.widgetList<Text>(find.text('\$0')).toList();
      expect(zeroTexts, isNotEmpty);
      expect(
        zeroTexts.every((t) => t.style?.color == Colors.green.shade700),
        isTrue,
      );

      // Si el checkout falla/se cancela, libera el snapshot al fallar
      completer.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('Monto Excedido:'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cambiar comprobante fiscal a Factura B (Consumidor Final) fuerza percepción IIBB a \$0 incluso con cliente marcado', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final posProvider = _createPreviewGatePosProvider();
      final pintProduct = Product(
        id: 11,
        name: 'Pintura Test FB',
        internalCode: 'P-FB',
        costPrice: 12000,
        sellingPrice: 22900,
        ivaRate: 21.0,
        stock: 20,
        active: true,
        isSoldByWeight: false,
      );
      final riCustomer = Customer(
        id: 78,
        name: 'Cliente RI Switch B',
        documentNumber: '30500010912',
        documentType: 80,
        taxCondition: 'responsable_inscripto',
        creditLimit: 0.0,
        balance: 0.0,
        isActive: true,
        appliesIibbPerception: true,
        iibbPerceptionRate: 3.0,
      );

      posProvider.requestAddToCartWithPromo(pintProduct);
      posProvider.selectCustomer(riCustomer, isPerceptionAgent: true);
      posProvider.setDefaultIibbPerceptionRate(3.0);

      final settingsProvider = _FakeIibbSettingsProvider(
        const BusinessSettings(
          companyName: 'Corralón Test',
          taxId: '30-50001091-2',
          taxCondition: 'IVA Responsable Inscripto',
          afipEnabled: true,
          isIibbPerceptionAgent: true,
          defaultIibbPerceptionRate: 3.0,
          licenseStatus: 'LIC-TEST',
          licensePlanType: 'premium',
          features: FeatureFlags(fastPos: true, arcaAfip: true),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<PosProvider>.value(value: posProvider),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: _FakeLocalTerminalProvider()),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<CustomerProvider>.value(value: _FakeCustomerProvider()),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: _FakeCashRegisterProvider()),
            ChangeNotifierProvider<CatalogProvider>.value(value: _FakeCatalogProvider()),
            Provider<ApiClient>.value(
              value: ApiClient(MockClient((_) async => http.Response('{}', 200))),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<bool>(
                        context: ctx,
                        builder: (_) => const CheckoutDialog(total: 22900.0),
                      );
                    },
                    child: const Text('ABRIR'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ABRIR'));
      await tester.pumpAndSettle();

      // En modo Ticket Común con cliente RI marcado -> $23.467,77
      expect(find.textContaining('23.467,77'), findsWidgets);

      // Activar modo Factura Fiscal ARCA (inicia en Factura B -> Consumidor Final -> IIBB $0)
      final fiscalArcaFinder = find.text('Factura Fiscal ARCA').first;
      await tester.ensureVisible(fiscalArcaFinder);
      await tester.tap(fiscalArcaFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('23.467,77'), findsNothing);
      expect(find.textContaining('22.900'), findsWidgets);

      // Cambiar a Factura A -> restaura percepción IIBB $567,77 ($23.467,77)
      final factAFinder = find.text('Factura A').first;
      await tester.ensureVisible(factAFinder);
      await tester.tap(factAFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('23.467,77'), findsWidgets);

      // Verificar alto contraste en los SegmentedButton fiscales (seleccionado oscuro + texto blanco, no seleccionado blanco)
      final fiscalModeSeg = tester.widget<SegmentedButton<bool>>(
        find.byKey(const Key('fiscal_mode_segmented_button')),
      );
      final voucherTypeSeg = tester.widget<SegmentedButton<int>>(
        find.byKey(const Key('voucher_type_segmented_button')),
      );
      expect(
        fiscalModeSeg.style?.backgroundColor?.resolve({WidgetState.selected}),
        Colors.indigo.shade800,
      );
      expect(
        fiscalModeSeg.style?.foregroundColor?.resolve({WidgetState.selected}),
        Colors.white,
      );
      expect(
        fiscalModeSeg.style?.backgroundColor?.resolve(<WidgetState>{}),
        Colors.white,
      );
      expect(
        voucherTypeSeg.style?.backgroundColor?.resolve({WidgetState.selected}),
        Colors.indigo.shade800,
      );
      expect(
        voucherTypeSeg.style?.foregroundColor?.resolve({WidgetState.selected}),
        Colors.white,
      );
      expect(
        voucherTypeSeg.style?.backgroundColor?.resolve(<WidgetState>{}),
        Colors.white,
      );

      // Volver a Factura B -> _fiscalTaxCondition pasa a consumidor_final -> IIBB cae a $0
      final factBFinder = find.text('Factura B').first;
      await tester.ensureVisible(factBFinder);
      await tester.tap(factBFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('23.467,77'), findsNothing);
      expect(find.textContaining('22.900'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('QuotePdfService Leyenda Condicional IIBB', () {
    final quote = Quote(
      id: 1,
      quoteNumber: 'PRES-0001',
      status: 'pending',
      subtotal: 22900.0,
      total: 22900.0,
      items: [
        QuoteItem(
          productId: 10,
          productName: 'Pintura Látex 4L',
          unitPrice: 22900.0,
          quantity: 1,
          subtotal: 22900.0,
        ),
      ],
    );

    test('Incluye leyenda discreta al pie solo cuando isIibbPerceptionAgent == true sin alterar montos', () async {
      final agentPdf = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Agente IIBB',
        businessSettings: const BusinessSettings(
          isIibbPerceptionAgent: true,
          defaultIibbPerceptionRate: 3.0,
        ),
      );
      final agentText = _extractPdfText(agentPdf);
      expect(agentText, contains('percepciones de IIBB (DGR)'));
      expect(quote.total, 22900.0);

      final nonAgentPdf = await QuotePdfService.generateQuotePdf(
        quote: quote,
        businessName: 'Ferretería Común',
        businessSettings: const BusinessSettings(
          isIibbPerceptionAgent: false,
          defaultIibbPerceptionRate: 0.0,
        ),
      );
      final nonAgentText = _extractPdfText(nonAgentPdf);
      expect(nonAgentText.contains('percepciones de IIBB (DGR)'), isFalse);
    });
  });

  group('SettingsScreen Selectores IIBB', () {
    testWidgets('Muestra base de cálculo y condiciones IVA alcanzadas al activar Agente IIBB sin overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProvider = _FakeIibbSettingsProvider(
        const BusinessSettings(
          companyName: 'Corralón Formosa',
          taxId: '30-50001091-2',
          taxCondition: 'IVA Responsable Inscripto',
          afipEnabled: true,
          isIibbPerceptionAgent: false,
          defaultIibbPerceptionRate: 3.0,
          licenseStatus: 'LIC-PREM',
          licensePlanType: 'premium',
          features: FeatureFlags(fastPos: true, arcaAfip: true),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: _FakeLocalTerminalProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeAlertsProvider()),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: _FakeCashRegisterProvider()),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Navegar a la pestaña Datos del Negocio / Integraciones según orden del menú
      await tester.tap(find.text('General').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final switchFinder = find.byKey(const ValueKey('switch_iibb_perception_agent'));
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('iibb_base_net_option')), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_base_gross_option')), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_subject_ri')), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_subject_mono')), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_subject_exento')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('iibb_base_gross_option')));
      await tester.tap(find.byKey(const ValueKey('iibb_base_gross_option')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('iibb_subject_mono')));
      await tester.tap(find.byKey(const ValueKey('iibb_subject_mono')));
      await tester.pump();

      final saveBtn = find.text('GUARDAR').first;
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(settingsProvider.savedPayload?['iibb_calculation_base'],
          IibbFiscalCalculator.baseGrossWithVat);
      expect(settingsProvider.savedPayload?['iibb_subject_tax_conditions'],
          containsAll(['responsable_inscripto', 'monotributo']));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Cambiar Condición frente al IVA sincroniza en vivo subtítulo, base automática Factura C y etiquetas de chips IIBB', (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final settingsProvider = _FakeIibbSettingsProvider(
        const BusinessSettings(
          companyName: 'Comercio Dual IVA',
          taxId: '20-30405060-7',
          taxCondition: 'IVA Responsable Inscripto',
          afipEnabled: true,
          isIibbPerceptionAgent: true,
          defaultIibbPerceptionRate: 3.0,
          licenseStatus: 'LIC-PREM',
          licensePlanType: 'premium',
          features: FeatureFlags(fastPos: true, arcaAfip: true),
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
            ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuthProvider()),
            ChangeNotifierProvider<LocalTerminalProvider>.value(value: _FakeLocalTerminalProvider()),
            ChangeNotifierProvider<InventoryAlertsProvider>.value(value: _FakeAlertsProvider()),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: _FakeCashRegisterProvider()),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      await tester.tap(find.text('General').first);
      await tester.pumpAndSettle();

      // Estado inicial: IVA Responsable Inscripto
      expect(find.textContaining('en Facturas A y B.'), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_base_net_option')), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_base_gross_option')), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_base_factura_c_auto_note')), findsNothing);
      expect(find.text('Responsable Inscripto (Fact. A)'), findsOneWidget);
      expect(find.text('Monotributista (Fact. B)'), findsOneWidget);
      expect(find.text('IVA Exento (Fact. B)'), findsOneWidget);

      // Cambiar dropdown a Responsable Monotributo
      final dropdown = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Responsable Monotributo').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('en Factura C.'), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_base_net_option')), findsNothing);
      expect(find.byKey(const ValueKey('iibb_base_gross_option')), findsNothing);
      expect(find.byKey(const ValueKey('iibb_base_factura_c_auto_note')), findsOneWidget);
      expect(find.text('Responsable Inscripto (Fact. C)'), findsOneWidget);
      expect(find.text('Monotributista (Fact. C)'), findsOneWidget);
      expect(find.text('IVA Exento (Fact. C)'), findsOneWidget);

      // Cambiar dropdown a IVA Exento mantiene modo Factura C
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('IVA Exento').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('en Factura C.'), findsOneWidget);
      expect(find.byKey(const ValueKey('iibb_base_factura_c_auto_note')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
