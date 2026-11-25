import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/core/providers/local_terminal_provider.dart';
import 'package:frontend_desktop/core/utils/afip_fiscal_pdf_service.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/catalog/presentation/providers/catalog_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/offers/presentation/providers/offer_provider.dart';
import 'package:frontend_desktop/features/pos/presentation/providers/pos_provider.dart';
import 'package:frontend_desktop/features/reports/presentation/providers/inventory_alerts_provider.dart';
import 'package:frontend_desktop/features/sales_history/domain/entities/sale_record.dart';
import 'package:frontend_desktop/features/sales_history/presentation/pages/sales_history_screen.dart';
import 'package:frontend_desktop/features/sales_history/presentation/providers/sales_history_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/users/presentation/providers/users_provider.dart';

class _FakePosProvider extends ChangeNotifier implements PosProvider {
  int? lastIssuedSaleId;
  Map<String, dynamic>? lastIssuedPayload;
  Map<String, dynamic> Function(int saleId, Map<String, dynamic> payload)?
      onIssue;

  @override
  bool get isLoading => false;

  @override
  Future<Map<String, dynamic>?> issueFiscalInvoice(
    int saleId,
    Map<String, dynamic> invoiceData,
  ) async {
    lastIssuedSaleId = saleId;
    lastIssuedPayload = Map<String, dynamic>.from(invoiceData);
    if (onIssue != null) {
      return onIssue!(saleId, invoiceData);
    }
    return {
      'success': true,
      'invoice': {
        'id': 48,
        'sale_id': saleId,
        'voucher_type': invoiceData['voucher_type'] ?? 1,
        'voucher_letter': (invoiceData['voucher_type'] == 1)
            ? 'A'
            : (invoiceData['voucher_type'] == 11 ? 'C' : 'B'),
        'point_of_sale': 1,
        'voucher_number': 45,
        'formatted_number': '00001-00000045',
        'cae': '86461089624789',
        'cae_expiration': '2026-11-28',
        'doc_type': invoiceData['doc_type'] ?? 80,
        'doc_number': invoiceData['doc_number'] ?? '27388231497',
        'receiver_name':
            invoiceData['receiver_name'] ?? 'Supermercado Los Primos SRL',
        'receiver_address':
            invoiceData['receiver_address'] ?? 'Av. 25 de Mayo 1420, Formosa',
        'receiver_tax_condition':
            invoiceData['receiver_tax_condition'] ?? 'responsable_inscripto',
        'net_amount': '8264.46',
        'iva_amount': '1735.54',
        'tribute_amount':
            ((invoiceData['iibb_perception_amount'] as num?)?.toDouble() ?? 0.0)
                .toStringAsFixed(2),
        'tributes_breakdown': ((invoiceData['iibb_perception_amount'] as num?)
                        ?.toDouble() ??
                    0.0) >
                0
            ? [
                {
                  'Id': 2,
                  'Desc': 'Percepcion de Ingresos Brutos',
                  'BaseImp': 8264.46,
                  'Alic': (invoiceData['iibb_perception_rate'] as num?)
                          ?.toDouble() ??
                      0.0,
                  'Importe': (invoiceData['iibb_perception_amount'] as num?)
                          ?.toDouble() ??
                      0.0,
                }
              ]
            : null,
        'total_amount': (10000.0 +
                ((invoiceData['iibb_perception_amount'] as num?)?.toDouble() ??
                    0.0))
            .toStringAsFixed(2),
        'issued_at': '2026-11-18T19:41:00Z',
        'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=test',
      },
    };
  }

  @override
  Future<Map<String, dynamic>?> fetchElectronicInvoice(int saleId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings _settings;

  _FakeSettingsProvider(this._settings);

  @override
  BusinessSettings? get settings => _settings;

  @override
  int get assignedRegisterId => 1;

  @override
  bool get isIibbPerceptionAgent => _settings.isIibbPerceptionAgent;

  @override
  double get defaultIibbPerceptionRate => _settings.defaultIibbPerceptionRate;

  @override
  bool get isResponsableInscripto => _settings.isResponsableInscripto;

  @override
  bool get isLicenseActive => true;

  @override
  String get currentPlan => 'premium';

  @override
  FeatureFlags get features => _settings.features;

  @override
  bool hasFeature(String featureName) => _settings.hasFeature(featureName);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCustomerProvider extends ChangeNotifier implements CustomerProvider {
  final List<Customer> _customers;

  _FakeCustomerProvider(this._customers);

  @override
  List<Customer> get customers => _customers;

  @override
  bool get isLoading => false;

  @override
  Future<void> fetchCustomers({String? search}) async {}

  @override
  Future<Map<String, dynamic>?> lookupFiscalRecipient(
      String rawDocNumber) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSalesHistoryProvider extends ChangeNotifier
    implements SalesHistoryProvider {
  final List<SaleRecord> _sales;
  int loadSalesCallCount = 0;

  _FakeSalesHistoryProvider(this._sales);

  @override
  List<SaleRecord> get sales => _sales;

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  String get currentPeriod => 'shift';

  @override
  int? get selectedUserId => null;

  @override
  int? get selectedRegisterId => null;

  @override
  int? get currentShiftId => 1;

  @override
  String? get methodFilter => null;

  @override
  void setMethodFilter(String? code) {}

  @override
  String get fiscalFilter => 'all';

  @override
  void setFiscalFilter(String filter) {}

  @override
  DateTimeRange? get customDateRange => null;

  @override
  Future<void> setCustomDateRange(DateTimeRange? range) async {}

  @override
  bool matchesCustomDateRange(SaleRecord sale) => true;

  @override
  Future<void> loadSales({String? period, int? shiftId}) async {
    loadSalesCallCount++;
    notifyListeners();
  }

  @override
  Map<String, double> get totalByMethod => {'efectivo': 10000.0};

  @override
  Map<String, double> get totalByMethodBase => {'efectivo': 10000.0};

  @override
  Map<String, double> get totalByMethodSurcharge => {};

  @override
  Map<String, String> get methodNames => {'efectivo': 'Efectivo'};

  @override
  double get totalVentas => 10000.0;

  @override
  double get totalNetVentas => 10000.0;

  @override
  double get totalSurcharges => 0.0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  Map<String, dynamic>? get currentUser =>
      {'id': 1, 'name': 'Administrador', 'role': 'admin'};

  @override
  bool get isAdmin => true;

  @override
  bool get isAuthenticated => true;

  @override
  bool hasPermission(String key) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUsersProvider extends ChangeNotifier implements UsersProvider {
  @override
  List<Map<String, dynamic>> get users => [
        {'id': 1, 'name': 'Administrador'}
      ];

  @override
  bool get isLoading => false;

  @override
  Future<void> loadUsers() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCashRegisterProvider extends ChangeNotifier
    implements CashRegisterProvider {
  final _shift = CashRegisterShift(
    id: 1,
    cashRegisterId: 1,
    userId: 1,
    openedAt: DateTime(2026, 11, 18, 8, 0),
    openingBalance: 0.0,
    status: 'open',
    cashRegisterName: 'Caja Principal',
  );

  @override
  CashRegisterShift? get currentShift => _shift;

  @override
  List<CashRegister>? get availableRegisters => [
        CashRegister(id: 1, name: 'Caja Principal', isActive: true),
      ];

  @override
  int? get activeRegisterId => 1;

  @override
  Future<void> loadRegisters() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalTerminalProvider extends ChangeNotifier
    implements LocalTerminalProvider {
  @override
  double get salesHistorySplitRatio => 0.28;

  @override
  String get printerFormat => 'thermal_80';

  @override
  String get pdfPaperSize => 'a4';

  @override
  bool get autoOpenCashDrawer => false;

  @override
  String get scaleComPort => '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInventoryAlertsProvider extends ChangeNotifier
    implements InventoryAlertsProvider {
  @override
  int get totalAlertsCount => 0;

  @override
  bool get isLoading => false;

  @override
  List<Map<String, dynamic>> get reactiveAlerts => const [];

  @override
  List<Map<String, dynamic>> get predictiveCriticalAlerts => const [];

  @override
  List<Map<String, dynamic>> get expirationAlerts => const [];

  @override
  List<Map<String, dynamic>> get deficitAlerts => const [];

  @override
  Future<void> fetchAlerts({int threshold = 3}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCatalogProvider extends ChangeNotifier implements CatalogProvider {
  @override
  Future<void> fetchCriticalAlerts() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOfferProvider extends ChangeNotifier implements OfferProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SaleRecord _buildTicket156({double total = 10000.0}) {
  return SaleRecord(
    id: 156,
    total: total,
    status: 'completed',
    paymentStatus: 'paid',
    invoiceStatus: 'none',
    createdAt: DateTime(2026, 11, 16, 23, 4, 24),
    userId: 1,
    userName: 'Administrador',
    cashierId: 1,
    cashierName: 'Administrador',
    cashShiftId: 1,
    cashRegisterId: 1,
    cashRegisterName: 'Caja Principal',
    customerId: 2,
    customerName: 'Supermercado Los Primos SRL',
    customerDocumentType: 80,
    customerDocumentNumber: '27388231497',
    customerTaxCondition: 'consumidor_final',
    customerAddress: 'Av. 25 de Mayo 1420, Formosa',
    customerAppliesIibbPerception: false,
    customerIibbPerceptionRate: null,
    items: [
      SaleItemRecord(
        id: 1,
        productId: 10,
        productName: 'Refrescante Bucal',
        quantity: 1,
        unitPrice: total,
        subtotal: total,
        ivaRate: 21.0,
      ),
    ],
    payments: [
      SalePayment(
        id: 1,
        paymentMethodId: 1,
        methodName: 'Efectivo',
        methodCode: 'efectivo',
        isCash: true,
        baseAmount: total,
        surchargeAmount: 0.0,
        totalAmount: total,
      ),
    ],
  );
}

SaleRecord _buildAnonymousSale({int id = 151, double total = 300.0}) {
  return SaleRecord(
    id: id,
    total: total,
    status: 'completed',
    paymentStatus: 'paid',
    invoiceStatus: 'none',
    createdAt: DateTime(2026, 11, 18, 12, 0),
    userId: 1,
    userName: 'Administrador',
    cashierId: 1,
    cashierName: 'Administrador',
    cashShiftId: 1,
    cashRegisterId: 1,
    cashRegisterName: 'Caja Principal',
    customerId: null,
    customerName: null,
    customerDocumentType: null,
    customerDocumentNumber: null,
    customerTaxCondition: 'consumidor_final',
    items: [
      SaleItemRecord(
        id: 1,
        productId: 10,
        productName: 'Producto Test',
        quantity: 1,
        unitPrice: total,
        subtotal: total,
        ivaRate: 21.0,
      ),
    ],
    payments: [
      SalePayment(
        id: 1,
        paymentMethodId: 1,
        methodName: 'Efectivo',
        methodCode: 'efectivo',
        isCash: true,
        baseAmount: total,
        surchargeAmount: 0.0,
        totalAmount: total,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const agentSettings = BusinessSettings(
    companyName: 'Dev4U',
    taxId: '20-39606329-9',
    address: 'Jujuy 152',
    phone: '3704787285',
    taxCondition: 'IVA Responsable Inscripto',
    iibb: '20-39606329-9',
    afipEnabled: true,
    isIibbPerceptionAgent: true,
    defaultIibbPerceptionRate: 3.0,
    features: FeatureFlags(arcaAfip: true, currentAccounts: true),
  );

  final losPrimos = Customer(
    id: 2,
    name: 'Supermercado Los Primos SRL',
    documentNumber: '27388231497',
    documentType: 80,
    taxCondition: 'consumidor_final',
    fiscalAddress: 'Av. 25 de Mayo 1420, Formosa',
    creditLimit: 0.0,
    balance: 0.0,
    isActive: true,
    appliesIibbPerception: false,
    iibbPerceptionRate: null,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Registro de Ventas - Emisión ARCA + IIBB + Selector Impresión', () {
    testWidgets(
      '1. Factura A calcula automáticamente 3.0% IIBB (\$247,93 -> \$10.247,93) aunque el cliente no tenga flag aplica_iibb',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerProv = _FakeCustomerProvider([losPrimos]);
        final ticket156 = _buildTicket156();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(
                  value: customerProv),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EmitArcaInvoiceDialog(sale: ticket156),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Seleccionar Factura A
        await tester.tap(find.text('Factura A'));
        await tester.pumpAndSettle();

        expect(find.text('Percepción IIBB (Rentas):'), findsOneWidget);
        expect(find.text('Total a facturar: \$10.247,93'), findsOneWidget);
        expect(find.text('+\$247,93'), findsOneWidget);

        // Enviar autorización ARCA
        final authBtn = find.text('Autorizar Factura en ARCA');
        await tester.ensureVisible(authBtn);
        await tester.tap(authBtn);
        await tester.pumpAndSettle();

        expect(posProv.lastIssuedSaleId, equals(156));
        expect(posProv.lastIssuedPayload, isNotNull);
        expect(posProv.lastIssuedPayload!['voucher_type'], equals(1));
        expect(
            posProv.lastIssuedPayload!['iibb_perception_amount'], equals(247.93));
        expect(posProv.lastIssuedPayload!['iibb_perception_rate'], equals(3.0));
      },
    );

    testWidgets(
      '2. Override manual "Sin perc. (0%)" vuelve a \$10.000,00 y envía iibb_perception_amount=0, rate=0',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerProv = _FakeCustomerProvider([losPrimos]);
        final ticket156 = _buildTicket156();

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(
                  value: customerProv),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EmitArcaInvoiceDialog(sale: ticket156),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Factura A'));
        await tester.pumpAndSettle();
        expect(find.text('Total a facturar: \$10.247,93'), findsOneWidget);

        // Tocar chip "Sin perc. (0%)"
        final zeroChip = find.text('Sin perc. (0%)');
        await tester.ensureVisible(zeroChip);
        await tester.tap(zeroChip);
        await tester.pumpAndSettle();

        expect(find.text('Total a facturar: \$10.000'), findsOneWidget);

        final authBtn = find.text('Autorizar Factura en ARCA');
        await tester.ensureVisible(authBtn);
        await tester.tap(authBtn);
        await tester.pumpAndSettle();

        expect(posProv.lastIssuedPayload!['iibb_perception_amount'], equals(0.0));
        expect(posProv.lastIssuedPayload!['iibb_perception_rate'], equals(0.0));
      },
    );

    testWidgets(
      '3. Ticket > \$340.000 + cliente con documentType=99 no crashea DropdownButtonFormField y normaliza a DNI (96)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerSinDoc = Customer(
          id: 99,
          name: 'Cliente Ocasional',
          documentNumber: '',
          documentType: 99,
          taxCondition: 'consumidor_final',
          creditLimit: 0.0,
          balance: 0.0,
          isActive: true,
        );
        final customerProv = _FakeCustomerProvider([customerSinDoc]);
        final highSale = SaleRecord(
          id: 200,
          total: 400000.0,
          status: 'completed',
          createdAt: DateTime(2026, 11, 18, 12, 0),
          items: [
            SaleItemRecord(
              id: 1,
              productName: 'Heladera Industrial',
              quantity: 1,
              unitPrice: 400000.0,
              subtotal: 400000.0,
            ),
          ],
          payments: const [],
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(
                  value: customerProv),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EmitArcaInvoiceDialog(sale: highSale),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Buscar y seleccionar cliente con documentType = 99
        final searchBtn = find.text('Buscar Cliente');
        await tester.ensureVisible(searchBtn);
        await tester.tap(searchBtn);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cliente Ocasional'));
        await tester.pumpAndSettle();

        // Debe renderizar sin AssertionError y normalizar Tipo Doc. a DNI (96)
        expect(tester.takeException(), isNull);
        expect(find.text('DNI (96)'), findsOneWidget);
      },
    );

    testWidgets(
      '4. Flujo completo en SalesHistoryScreen: tras Autorizar Factura en ARCA abre automáticamente PrintFormatSelector (Térmico / PDF)',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerProv = _FakeCustomerProvider([losPrimos]);
        final ticket156 = _buildTicket156();
        final historyProv = _FakeSalesHistoryProvider([ticket156]);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(
                  value: customerProv),
              ChangeNotifierProvider<SalesHistoryProvider>.value(
                  value: historyProv),
              ChangeNotifierProvider<AuthProvider>.value(
                  value: _FakeAuthProvider()),
              ChangeNotifierProvider<UsersProvider>.value(
                  value: _FakeUsersProvider()),
              ChangeNotifierProvider<CashRegisterProvider>.value(
                  value: _FakeCashRegisterProvider()),
              ChangeNotifierProvider<LocalTerminalProvider>.value(
                  value: _FakeLocalTerminalProvider()),
              ChangeNotifierProvider<InventoryAlertsProvider>.value(
                  value: _FakeInventoryAlertsProvider()),
              ChangeNotifierProvider<CatalogProvider>.value(
                  value: _FakeCatalogProvider()),
              ChangeNotifierProvider<OfferProvider>.value(
                  value: _FakeOfferProvider()),
            ],
            child: const MaterialApp(
              home: SalesHistoryScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Seleccionar el Ticket #156 de la lista izquierda
        await tester.tap(find.text('#156'));
        await tester.pumpAndSettle();

        // Pulsar "Emitir a ARCA"
        expect(find.text('Emitir a ARCA'), findsOneWidget);
        await tester.tap(find.text('Emitir a ARCA'));
        await tester.pumpAndSettle();

        // Elegir Factura A y autorizar
        await tester.tap(find.text('Factura A'));
        await tester.pumpAndSettle();
        final authBtn = find.text('Autorizar Factura en ARCA');
        await tester.ensureVisible(authBtn);
        await tester.tap(authBtn);
        await tester.pumpAndSettle();

        // Verificar que se recargó el historial y apareció automáticamente PrintFormatSelector
        expect(historyProv.loadSalesCallCount, greaterThanOrEqualTo(2));
        expect(find.text('Formato de Impresión'), findsOneWidget);
        expect(find.text('Ticket\nTérmico'), findsOneWidget);
        expect(find.text('Hoja A4\n(PDF)'), findsOneWidget);

        // Cerrar PrintFormatSelector
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      },
    );

    test(
      '5. AfipFiscalPdfService usa Alic de tributes_breakdown cuando sale["iibb_perception_rate"] viene en 0.0',
      () async {
        final sale = {
          'id': 156,
          'created_at': '2026-11-18T19:41:00Z',
          'items': [
            {
              'product_name': 'Refrescante Bucal',
              'quantity': 1,
              'unit_price': 10000.0,
              'subtotal': 10000.0,
              'iva_rate': 21.0,
            },
          ],
          'total': 10247.93,
          'iibb_perception_amount': 247.93,
          'iibb_perception_rate': 0.0,
        };

        final electronicInvoice = {
          'voucher_type': 1,
          'voucher_letter': 'A',
          'point_of_sale': 1,
          'voucher_number': 45,
          'formatted_number': '00001-00000045',
          'cae': '86461089624789',
          'cae_expiration': '2026-11-28',
          'doc_type': 80,
          'doc_number': '27388231497',
          'receiver_name': 'Supermercado Los Primos SRL',
          'receiver_tax_condition': 'responsable_inscripto',
          'net_amount': 8264.46,
          'iva_amount': 1735.54,
          'tribute_amount': 247.93,
          'tributes_breakdown': [
            {
              'Id': 2,
              'Desc': 'Percepcion de Ingresos Brutos',
              'BaseImp': 8264.46,
              'Alic': 3.0,
              'Importe': 247.93,
            }
          ],
          'total_amount': 10247.93,
          'qr_data': 'https://www.afip.gob.ar/fe/qr/?p=test',
        };

        final doc = AfipFiscalPdfService.buildFiscalDocument(
          sale: sale,
          electronicInvoice: electronicInvoice,
          businessSettings: agentSettings,
          paperSize: 'a4',
          compress: false,
        );

        final textNodes = AfipFiscalPdfService.findWidgets<pw.RichText>(doc);
        final plainTexts = textNodes.map((w) => w.text.toPlainText()).toList();
        final perceptionLine = plainTexts.firstWhere(
          (t) => t.contains('Percepción IIBB'),
          orElse: () => '',
        );

        expect(perceptionLine, contains('3.0%'));
        expect(perceptionLine, contains('247,93'));
      },
    );

    testWidgets(
      '6. Elegir Factura A y luego seleccionar cliente consumidor_final en Buscar Cliente mantiene Factura A y calcula IIBB',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerProv = _FakeCustomerProvider([losPrimos]);
        final ticket151 = _buildAnonymousSale(id: 151, total: 300.0);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(
                  value: customerProv),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EmitArcaInvoiceDialog(sale: ticket151),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Elegir Factura A manualmente antes de buscar cliente
        await tester.tap(find.text('Factura A'));
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          equals({1}),
        );

        // Buscar y seleccionar Supermercado Los Primos SRL (taxCondition: consumidor_final en BD)
        final searchBtn = find.text('Buscar Cliente');
        await tester.ensureVisible(searchBtn);
        await tester.tap(searchBtn);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Supermercado Los Primos SRL'));
        await tester.pumpAndSettle();

        // Debe conservar Factura A ({1}), CUIT (80), IVA Resp. Inscripto e IIBB 3.0%
        expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          equals({1}),
        );
        expect(find.text('CUIT (80)'), findsOneWidget);
        expect(find.text('IVA Resp. Inscripto'), findsOneWidget);
        expect(find.text('Percepción IIBB (Rentas):'), findsOneWidget);
        expect(find.text('+\$7,44'), findsOneWidget);
        expect(find.text('Total a facturar: \$307,44'), findsOneWidget);

        // Autorizar factura y verificar payload enviado al backend
        final authBtn = find.text('Autorizar Factura en ARCA');
        await tester.ensureVisible(authBtn);
        await tester.tap(authBtn);
        await tester.pumpAndSettle();

        expect(posProv.lastIssuedSaleId, equals(151));
        expect(posProv.lastIssuedPayload, isNotNull);
        expect(posProv.lastIssuedPayload!['voucher_type'], equals(1));
        expect(posProv.lastIssuedPayload!['doc_type'], equals(80));
        expect(
            posProv.lastIssuedPayload!['doc_number'], equals('27388231497'));
        expect(posProv.lastIssuedPayload!['receiver_tax_condition'],
            equals('responsable_inscripto'));
        expect(posProv.lastIssuedPayload!['iibb_perception_amount'],
            equals(7.44));
        expect(posProv.lastIssuedPayload!['iibb_perception_rate'], equals(3.0));
      },
    );

    testWidgets(
      '7. Elegir Factura A y escribir CUIT de cliente consumidor_final por teclado mantiene Factura A y calcula IIBB',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerProv = _FakeCustomerProvider([losPrimos]);
        final ticket151 = _buildAnonymousSale(id: 151, total: 300.0);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(
                  value: customerProv),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EmitArcaInvoiceDialog(sale: ticket151),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Factura A'));
        await tester.pumpAndSettle();

        final cuitField =
            find.widgetWithText(TextFormField, 'N° de CUIT (11 dígitos)');
        expect(cuitField, findsOneWidget);
        await tester.enterText(cuitField, '27388231497');
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          equals({1}),
        );
        expect(find.text('IVA Resp. Inscripto'), findsOneWidget);
        expect(find.text('Total a facturar: \$307,44'), findsOneWidget);
      },
    );

    testWidgets(
      '8. Sin elección manual previa de clase, seleccionar cliente Responsable Inscripto auto-selecciona Factura A y calcula IIBB',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final construcciones = Customer(
          id: 5,
          name: 'Construcciones & Servicios del Norte SA',
          documentNumber: '30659821432',
          documentType: 80,
          taxCondition: 'responsable_inscripto',
          fiscalAddress: 'Av. Gutnisky 2100',
          creditLimit: 0.0,
          balance: 0.0,
          isActive: true,
          appliesIibbPerception: false,
          iibbPerceptionRate: null,
        );

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerProv = _FakeCustomerProvider([construcciones]);
        final ticket10k = _buildAnonymousSale(id: 160, total: 10000.0);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(
                  value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(
                  value: customerProv),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EmitArcaInvoiceDialog(sale: ticket10k),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Por defecto arranca en Factura B ({6})
        expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          equals({6}),
        );

        final searchBtn = find.text('Buscar Cliente');
        await tester.ensureVisible(searchBtn);
        await tester.tap(searchBtn);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Construcciones & Servicios del Norte SA'));
        await tester.pumpAndSettle();

        // Auto-upgrade a Factura A y cálculo de 3.0% IIBB
        expect(
          tester
              .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
              .selected,
          equals({1}),
        );
        expect(find.text('Total a facturar: \$10.247,93'), findsOneWidget);
      },
    );

    testWidgets(
      '9. Cliente sin DNI en EmitArcaInvoiceDialog: habilita Factura B < \$340.000 con doc_type=99 y bloquea si supera tope',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final posProv = _FakePosProvider();
        final settingsProv = _FakeSettingsProvider(agentSettings);
        final customerSinDoc = Customer(
          id: 77,
          name: 'Kiosco El Barrio',
          documentNumber: '',
          documentType: 96, // incluso legacy 96 con doc vacío
          taxCondition: 'consumidor_final',
          creditLimit: 0.0,
          balance: 0.0,
          isActive: true,
        );
        final customerProv = _FakeCustomerProvider([customerSinDoc]);

        final saleSinDoc = SaleRecord(
          id: 301,
          total: 5000.0,
          status: 'completed',
          paymentStatus: 'paid',
          invoiceStatus: 'none',
          createdAt: DateTime(2026, 11, 25, 10, 0),
          customerId: 77,
          customerName: 'Kiosco El Barrio',
          customerDocumentType: 96,
          customerDocumentNumber: null,
          customerTaxCondition: 'consumidor_final',
          items: [
            SaleItemRecord(
              id: 1,
              productName: 'Gaseosa 2L',
              quantity: 2,
              unitPrice: 2500.0,
              subtotal: 5000.0,
              ivaRate: 21.0,
            ),
          ],
          payments: const [],
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<PosProvider>.value(value: posProv),
              ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
              ChangeNotifierProvider<CustomerProvider>.value(value: customerProv),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: EmitArcaInvoiceDialog(sale: saleSinDoc),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final authBtn = find.text('Autorizar Factura en ARCA');
        await tester.ensureVisible(authBtn);
        await tester.tap(authBtn);
        await tester.pumpAndSettle();

        expect(posProv.lastIssuedSaleId, equals(301));
        expect(posProv.lastIssuedPayload?['voucher_type'], equals(6));
        expect(posProv.lastIssuedPayload?['doc_type'], equals(99));
        expect(posProv.lastIssuedPayload?['doc_number'], equals('0'));
        expect(posProv.lastIssuedPayload?['receiver_name'], equals('Kiosco El Barrio'));
      },
    );
  });
}
