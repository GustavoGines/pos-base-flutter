import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:frontend_desktop/features/customers/presentation/widgets/customer_form_dialog.dart';
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/features/users/presentation/widgets/employee_form_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/screens/mobile_network_settings_screen.dart';

class MockCustomerProvider extends ChangeNotifier implements CustomerProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dialog and Screen Disposal Verification Tests', () {
    testWidgets('CustomerFormDialog mounts and disposes controllers cleanly', (tester) async {
      final mockCustomerProvider = MockCustomerProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<CustomerProvider>.value(
            value: mockCustomerProvider,
            child: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const CustomerFormDialog(),
                    );
                  },
                  child: const Text('Open Customer Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open the dialog
      await tester.tap(find.text('Open Customer Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerFormDialog), findsOneWidget);
      expect(find.text('Nuevo Cliente'), findsOneWidget);

      // Verify text fields are present and enter text
      await tester.enterText(find.byType(TextFormField).at(0), 'Juan Perez');
      await tester.enterText(find.byType(TextFormField).at(1), '12345678');
      await tester.pump();

      // Dismiss dialog via Cancel button, triggering dispose()
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomerFormDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmployeeFormDialog mounts and disposes controllers cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const EmployeeFormDialog(),
                  );
                },
                child: const Text('Open Employee Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Employee Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeFormDialog), findsOneWidget);
      expect(find.text('Nuevo Empleado'), findsOneWidget);

      // Enter text into controllers
      await tester.enterText(find.byType(TextFormField).at(0), 'Carlos Gonzalez');
      await tester.enterText(find.byType(TextFormField).at(1), '1234');
      await tester.pump();

      // Dismiss dialog via Cancelar button, triggering dispose()
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.byType(EmployeeFormDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MobileNetworkSettingsScreen mounts and disposes controllers cleanly', (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'POS Test',
        packageName: 'com.example.pos',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      SharedPreferences.setMockInitialValues({
        'pos_api_local': 'http://192.168.1.50/Sistema_POS/pos-backend/public/api',
        'pos_api_remote': 'https://pos.test.com/api',
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: MobileNetworkSettingsScreen(),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(MobileNetworkSettingsScreen), findsOneWidget);
      expect(find.text('Configuración de Red'), findsOneWidget);

      // Re-pump a different widget to unmount and trigger dispose()
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Unmounted')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MobileNetworkSettingsScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
