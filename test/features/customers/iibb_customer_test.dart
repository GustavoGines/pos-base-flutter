import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';


import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/customers/models/customer_model.dart';
import 'package:frontend_desktop/features/customers/presentation/widgets/customer_form_dialog.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/settings/domain/entities/business_settings.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

// --- FAKES FOR WIDGET TESTING ---
class FakeCustomerProvider extends ChangeNotifier implements CustomerProvider {
  bool createCustomerCalled = false;
  bool updateCustomerCalled = false;
  Map<String, dynamic>? lastCreatedPayload;
  Map<String, dynamic>? lastUpdatedPayload;
  int? lastUpdatedId;

  @override
  Future<bool> createCustomer(Map<String, dynamic> data) async {
    createCustomerCalled = true;
    lastCreatedPayload = data;
    return true;
  }

  @override
  Future<bool> updateCustomer(int id, Map<String, dynamic> data) async {
    updateCustomerCalled = true;
    lastUpdatedId = id;
    lastUpdatedPayload = data;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCustomerSettingsProvider extends ChangeNotifier implements SettingsProvider {
  final BusinessSettings? _settings;

  FakeCustomerSettingsProvider({BusinessSettings? settings}) : _settings = settings;

  @override
  BusinessSettings? get settings => _settings;

  @override
  bool get isIibbPerceptionAgent => _settings?.isIibbPerceptionAgent ?? false;

  @override
  double get defaultIibbPerceptionRate => _settings?.defaultIibbPerceptionRate ?? 0.0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCustomerAuthProvider extends ChangeNotifier implements AuthProvider {
  @override
  bool get isAdmin => true;

  @override
  bool hasPermission(String permission) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Customer Model IIBB Perception Tests', () {
    test('Customer model defaults appliesIibbPerception to false and rate to null', () {
      final customer = Customer(
        id: 1,
        name: 'Consumidor Final',
        documentNumber: '00000000',
        creditLimit: 0,
        balance: 0,
        isActive: true,
      );

      expect(customer.appliesIibbPerception, isFalse);
      expect(customer.iibbPerceptionRate, isNull);
    });

    test('Customer.fromJson correctly deserializes boolean and numeric perception fields', () {
      // Direct boolean and double
      final c1 = Customer.fromJson({
        'id': 1,
        'name': 'Mayorista Formosa',
        'document_number': '20123456789',
        'applies_iibb_perception': true,
        'iibb_perception_rate': 3.5,
      });
      expect(c1.appliesIibbPerception, isTrue);
      expect(c1.iibbPerceptionRate, equals(3.5));

      // Integer 1 and string rate
      final c2 = Customer.fromJson({
        'id': 2,
        'name': 'Ferretería Central',
        'document_number': '20987654321',
        'applies_iibb_perception': 1,
        'iibb_perception_rate': '4.25',
      });
      expect(c2.appliesIibbPerception, isTrue);
      expect(c2.iibbPerceptionRate, equals(4.25));

      // Rate with comma
      final c3 = Customer.fromJson({
        'id': 3,
        'name': 'Distribuidora Norte',
        'document_number': '20111111119',
        'applies_iibb_perception': '1',
        'iibb_perception_rate': '3,00',
      });
      expect(c3.appliesIibbPerception, isTrue);
      expect(c3.iibbPerceptionRate, equals(3.0));

      // Falsy perception
      final c4 = Customer.fromJson({
        'id': 4,
        'name': 'Cliente Común',
        'document_number': '20222222229',
        'applies_iibb_perception': false,
        'iibb_perception_rate': null,
      });
      expect(c4.appliesIibbPerception, isFalse);
      expect(c4.iibbPerceptionRate, isNull);
    });

    test('Customer.toJson correctly serializes IIBB perception attributes', () {
      final customer = Customer(
        id: 10,
        name: 'Mayorista El Sol',
        documentNumber: '20333333339',
        creditLimit: 10000,
        balance: 0,
        isActive: true,
        appliesIibbPerception: true,
        iibbPerceptionRate: 3.5,
      );

      final json = customer.toJson();
      expect(json['applies_iibb_perception'], isTrue);
      expect(json['iibb_perception_rate'], equals(3.5));

      final customerNoPerception = customer.copyWith(
        appliesIibbPerception: false,
        iibbPerceptionRate: null,
      );
      final jsonNoPerception = customerNoPerception.toJson();
      expect(jsonNoPerception['applies_iibb_perception'], isFalse);
      expect(jsonNoPerception.containsKey('iibb_perception_rate'), isFalse);
    });

    test('Customer copyWith clones and updates IIBB fields correctly', () {
      final customer = Customer(
        id: 5,
        name: 'Comercial del Sur',
        documentNumber: '20444444449',
        creditLimit: 5000,
        balance: 0,
        isActive: true,
        appliesIibbPerception: false,
      );

      final updated = customer.copyWith(
        appliesIibbPerception: true,
        iibbPerceptionRate: 2.75,
      );

      expect(updated.appliesIibbPerception, isTrue);
      expect(updated.iibbPerceptionRate, equals(2.75));
      expect(updated.name, equals('Comercial del Sur'));
    });
  });

  group('CustomerFormDialog IIBB Widget Tests', () {
    Widget buildDialogTestApp({
      required FakeCustomerProvider customerProv,
      required FakeCustomerSettingsProvider settingsProv,
      Customer? customer,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<CustomerProvider>.value(value: customerProv),
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
          ChangeNotifierProvider<AuthProvider>.value(value: FakeCustomerAuthProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: CustomerFormDialog(customer: customer),
          ),
        ),
      );
    }

    testWidgets('Renders perception switch off by default, and auto-populates rate from settings when enabled', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final customerProv = FakeCustomerProvider();
      final settingsProv = FakeCustomerSettingsProvider(
        settings: const BusinessSettings(
          isIibbPerceptionAgent: true,
          defaultIibbPerceptionRate: 3.0,
        ),
      );

      await tester.pumpWidget(buildDialogTestApp(
        customerProv: customerProv,
        settingsProv: settingsProv,
      ));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(const ValueKey('switch_applies_iibb_perception'));
      expect(switchFinder, findsOneWidget);

      final rateFieldFinder = find.byKey(const ValueKey('field_iibb_perception_rate'));
      expect(rateFieldFinder, findsNothing);

      // Toggle switch ON
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Rate field is now visible
      expect(rateFieldFinder, findsOneWidget);

      // Verify auto-population with default rate from settings (3.0)
      final rateField = tester.widget<TextFormField>(rateFieldFinder);
      expect(rateField.controller?.text, equals('3.0'));
    });

    testWidgets('Validates that rate is required and between 0-100 when perception is enabled', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final customerProv = FakeCustomerProvider();
      final settingsProv = FakeCustomerSettingsProvider(
        settings: const BusinessSettings(defaultIibbPerceptionRate: 3.0),
      );

      await tester.pumpWidget(buildDialogTestApp(
        customerProv: customerProv,
        settingsProv: settingsProv,
      ));
      await tester.pumpAndSettle();

      // Enable switch
      await tester.tap(find.byKey(const ValueKey('switch_applies_iibb_perception')));
      await tester.pumpAndSettle();

      final rateFieldFinder = find.byKey(const ValueKey('field_iibb_perception_rate'));

      // Clear the rate field
      await tester.enterText(rateFieldFinder, '');
      await tester.pumpAndSettle();

      // Try to submit
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('La alícuota es requerida si aplica percepción'), findsOneWidget);

      // Enter invalid percentage (>100)
      await tester.enterText(rateFieldFinder, '120');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Ingrese un porcentaje válido (0 - 100)'), findsOneWidget);
    });

    testWidgets('Submits correct perception payload for new customer', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final customerProv = FakeCustomerProvider();
      final settingsProv = FakeCustomerSettingsProvider(
        settings: const BusinessSettings(defaultIibbPerceptionRate: 3.5),
      );

      await tester.pumpWidget(buildDialogTestApp(
        customerProv: customerProv,
        settingsProv: settingsProv,
      ));
      await tester.pumpAndSettle();

      // Fill Name
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre / Razón Social *'), 'Distribuidora Central S.R.L.');
      // Fill DNI/CUIT (default document type is 96 DNI, enter valid 8 digit DNI: 12345678)
      await tester.enterText(find.widgetWithText(TextFormField, 'DNI (7 u 8 dígitos) *'), '12345678');

      // Enable Perception switch
      await tester.tap(find.byKey(const ValueKey('switch_applies_iibb_perception')));
      await tester.pumpAndSettle();

      // Rate is automatically 3.5, customize to 4.0
      final rateFieldFinder = find.byKey(const ValueKey('field_iibb_perception_rate'));
      await tester.enterText(rateFieldFinder, '4.0');
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(customerProv.createCustomerCalled, isTrue);
      expect(customerProv.lastCreatedPayload?['name'], equals('Distribuidora Central S.R.L.'));
      expect(customerProv.lastCreatedPayload?['applies_iibb_perception'], isTrue);
      expect(customerProv.lastCreatedPayload?['iibb_perception_rate'], equals(4.0));
    });

    testWidgets('Pre-loads existing customer perception settings in edit mode', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final existingCustomer = Customer(
        id: 42,
        name: 'Mayorista Registrado',
        documentNumber: '20123456789',
        documentType: 80,
        taxCondition: 'responsable_inscripto',
        creditLimit: 50000,
        balance: 1500,
        isActive: true,
        appliesIibbPerception: true,
        iibbPerceptionRate: 3.85,
      );

      final customerProv = FakeCustomerProvider();
      final settingsProv = FakeCustomerSettingsProvider();

      await tester.pumpWidget(buildDialogTestApp(
        customerProv: customerProv,
        settingsProv: settingsProv,
        customer: existingCustomer,
      ));
      await tester.pumpAndSettle();

      // Switch should be ON
      final switchWidget = tester.widget<SwitchListTile>(find.byKey(const ValueKey('switch_applies_iibb_perception')));
      expect(switchWidget.value, isTrue);

      // Rate field should display 3.85
      final rateField = tester.widget<TextFormField>(find.byKey(const ValueKey('field_iibb_perception_rate')));
      expect(rateField.controller?.text, equals('3.85'));
    });
  });
}
