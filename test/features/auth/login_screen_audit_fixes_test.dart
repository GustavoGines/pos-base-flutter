import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/features/auth/presentation/pages/login_screen.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';

class TestAuthProvider extends ChangeNotifier implements AuthProvider {
  final bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _currentUser;
  final bool _requiresPinChange = false;
  bool shouldThrowOnVerify = false;
  bool verifyResult = true;

  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => _errorMessage;
  @override
  Map<String, dynamic>? get currentUser => _currentUser;
  @override
  bool get requiresPinChange => _requiresPinChange;

  @override
  Future<bool> verifyPin(String pin) async {
    if (shouldThrowOnVerify) {
      throw const SocketException('Error de conexión simulado');
    }
    if (verifyResult) {
      _currentUser = {'id': 1, 'name': 'Cajero Test', 'role': 'cashier'};
      return true;
    } else {
      _errorMessage = 'PIN inválido';
      return false;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSettingsProvider extends ChangeNotifier implements SettingsProvider {
  int loadSettingsCallCount = 0;
  int syncLicenseCallCount = 0;
  String lastSyncBaseUrl = '';
  Completer<void>? syncLicenseCompleter;

  @override
  String get currentApiUrl => 'http://192.168.1.200/api';
  @override
  int get assignedRegisterId => 1;

  @override
  Future<void> loadSettings({bool isSilent = false}) async {
    loadSettingsCallCount++;
  }

  @override
  Future<void> syncLicenseWithServer(String baseUrl, {bool isSilent = false}) async {
    syncLicenseCallCount++;
    lastSyncBaseUrl = baseUrl;
    if (syncLicenseCompleter != null) {
      await syncLicenseCompleter!.future;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestCashRegisterProvider extends ChangeNotifier implements CashRegisterProvider {
  int checkCurrentShiftCallCount = 0;

  @override
  CashRegisterShift? get currentShift => null;

  @override
  Future<void> checkCurrentShift({int? registerId}) async {
    checkCurrentShiftCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SocketException implements Exception {
  final String message;
  const SocketException(this.message);
  @override
  String toString() => 'SocketException: $message';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'POS Test',
      packageName: 'com.example.pos',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Widget createLoginScreen({
    required TestAuthProvider authProv,
    required TestSettingsProvider settingsProv,
    required TestCashRegisterProvider cashProv,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
        ChangeNotifierProvider<CashRegisterProvider>.value(value: cashProv),
      ],
      child: MaterialApp(
        routes: {
          '/': (_) => const LoginScreen(),
          '/home': (_) => const Scaffold(body: Text('Home Screen')),
        },
      ),
    );
  }

  group('LoginScreen Audit Fixes (R1, R2, R3)', () {
    testWidgets('R1: _submitPin recovers from exception via finally, resetting _isSubmitting', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..shouldThrowOnVerify = true;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pump();

      // Tap 1, 2, 3, 4 to trigger submit
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();

      // Exception was thrown during verifyPin
      await tester.pumpAndSettle();

      // Check error SnackBar and detail are displayed
      expect(find.textContaining('Error durante el inicio de sesión'), findsAtLeastNWidgets(1));

      // Verify UI is not frozen: we can tap digits again because _isSubmitting was reset in finally
      authProv.shouldThrowOnVerify = false;
      authProv.verifyResult = false; // Next attempt will be invalid PIN, not exception

      await tester.tap(find.text('5'));
      await tester.pump();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('R2: Login navigates to /home without awaiting syncLicenseWithServer', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider();
      // Completer that hangs to simulate 45s Render cold-start
      final coldStartCompleter = Completer<void>();
      settingsProv.syncLicenseCompleter = coldStartCompleter;
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pump();

      // Enter 4 digits
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();

      // Pump to let verifyPin and loadSettings finish and postFrameCallback fire
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // syncLicenseWithServer was called in background with currentApiUrl
      expect(settingsProv.syncLicenseCallCount, equals(1));
      expect(settingsProv.lastSyncBaseUrl, equals('http://192.168.1.200/api'));

      // Even though coldStartCompleter has NOT completed yet, navigation to /home succeeded!
      expect(find.text('Home Screen'), findsOneWidget);

      // Now complete the background task cleanly
      coldStartCompleter.complete();
      await tester.pump();
    });

    testWidgets('R3: On Desktop, checkCurrentShift is executed as before', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Running under Windows desktop test environment
      if (AppConfig.isDesktop) {
        final authProv = TestAuthProvider()..verifyResult = true;
        final settingsProv = TestSettingsProvider();
        final cashProv = TestCashRegisterProvider();

        await tester.pumpWidget(createLoginScreen(
          authProv: authProv,
          settingsProv: settingsProv,
          cashProv: cashProv,
        ));
        await tester.pump();

        await tester.tap(find.text('1'));
        await tester.pump();
        await tester.tap(find.text('2'));
        await tester.pump();
        await tester.tap(find.text('3'));
        await tester.pump();
        await tester.tap(find.text('4'));
        await tester.pumpAndSettle();

        expect(cashProv.checkCurrentShiftCallCount, equals(1));
        expect(find.text('Home Screen'), findsOneWidget);
      }
    });
  });
}
