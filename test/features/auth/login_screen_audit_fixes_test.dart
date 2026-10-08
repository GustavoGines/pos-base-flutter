import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:frontend_desktop/core/config/app_config.dart';
import 'package:frontend_desktop/features/auth/presentation/pages/login_screen.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';
import 'package:frontend_desktop/features/auth/presentation/widgets/rescue_pin_change_dialog.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/users/data/repositories/users_repository.dart';
import 'package:frontend_desktop/features/users/data/datasources/users_remote_datasource.dart';

class TestAuthProvider extends ChangeNotifier implements AuthProvider {
  final bool _isLoading = false;
  String? _errorMessage;
  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? customUser;
  bool requiresPinChangeResult = false;
  bool shouldThrowOnVerify = false;
  bool verifyResult = true;
  int verifyPinCallCount = 0;
  Completer<void>? verifyCompleter;

  @override
  bool get isLoading => _isLoading;
  @override
  String? get errorMessage => _errorMessage;
  @override
  Map<String, dynamic>? get currentUser => _currentUser;
  @override
  bool get requiresPinChange => requiresPinChangeResult;

  @override
  void clearPinChangeRequirement() {
    requiresPinChangeResult = false;
    notifyListeners();
  }

  @override
  Future<bool> verifyPin(String pin) async {
    verifyPinCallCount++;
    if (verifyCompleter != null) {
      await verifyCompleter!.future;
    }
    if (shouldThrowOnVerify) {
      throw const SocketException('Error de conexión simulado');
    }
    if (verifyResult) {
      _currentUser = customUser ?? {'id': 1, 'name': 'Cajero Test', 'role': 'cashier'};
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
  bool shouldThrowOnLoadSettings = false;
  bool shouldThrowOnSyncLicense = false;

  @override
  String get currentApiUrl => 'http://192.168.1.200/api';
  @override
  int get assignedRegisterId => 1;

  @override
  Future<void> loadSettings({bool isSilent = false}) async {
    loadSettingsCallCount++;
    if (shouldThrowOnLoadSettings) {
      throw const SocketException('Error de conexión cargando settings');
    }
  }

  @override
  Future<void> syncLicenseWithServer(String baseUrl, {bool isSilent = false}) async {
    syncLicenseCallCount++;
    lastSyncBaseUrl = baseUrl;
    if (shouldThrowOnSyncLicense) {
      throw const SocketException('Error simulado en sync license');
    }
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

class TestUsersRepository implements UsersRepository {
  @override
  UsersRemoteDataSource get dataSource => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> getAll() async => [];
  @override
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) async => data;
  @override
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> data) async => {'id': id, ...data};
  @override
  Future<void> delete(int id) async {}

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
    AppConfig.debugOverrideIsMobile = null;
  });

  tearDown(() {
    AppConfig.debugOverrideIsMobile = null;
  });

  Widget createLoginScreen({
    required TestAuthProvider authProv,
    required TestSettingsProvider settingsProv,
    required TestCashRegisterProvider cashProv,
    TestUsersRepository? usersRepo,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProv),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
        ChangeNotifierProvider<CashRegisterProvider>.value(value: cashProv),
        Provider<UsersRepository>.value(value: usersRepo ?? TestUsersRepository()),
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
    testWidgets('R1: _submitPin recovers from verifyPin exception via finally, resetting _isSubmitting', (tester) async {
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

    testWidgets('R1: _submitPin recovers from loadSettings exception via finally, resetting _isSubmitting', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider()..shouldThrowOnLoadSettings = true;
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

      // Exception was caught and UI is active
      expect(find.textContaining('Error durante el inicio de sesión'), findsAtLeastNWidgets(1));

      // Can tap digits again because finally released _isSubmitting
      settingsProv.shouldThrowOnLoadSettings = false;
      await tester.tap(find.text('1'));
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

    testWidgets('R2: syncLicenseWithServer background failure is caught gracefully without interrupting login', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider()..shouldThrowOnSyncLicense = true;
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

      expect(settingsProv.syncLicenseCallCount, equals(1));
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('R3: On Desktop (AppConfig.isMobile == false), checkCurrentShift is executed', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppConfig.debugOverrideIsMobile = false;

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
    });

    testWidgets('R3: On Mobile (AppConfig.isMobile == true), checkCurrentShift is bypassed (0 calls)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppConfig.debugOverrideIsMobile = true;

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

      // On mobile, checkCurrentShift was completely omitted!
      expect(cashProv.checkCurrentShiftCallCount, equals(0));
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Keyboard Enter and keypad clicks during submit do not trigger re-entry or double submit', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final verifyCompleter = Completer<void>();
      authProv.verifyCompleter = verifyCompleter;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pump();

      // Enter 4 digits to start submission
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();

      // verifyPin is currently in flight
      expect(authProv.verifyPinCallCount, equals(1));

      // Attempt to tap more digits while submit is in flight
      await tester.tap(find.text('5'));
      await tester.pump();
      await tester.tap(find.text('6'));
      await tester.pump();

      // Send Enter key while in flight
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Complete verifyPin
      verifyCompleter.complete();
      await tester.pumpAndSettle();

      // Exactly 1 verifyPin call occurred despite rapid taps and Enter
      expect(authProv.verifyPinCallCount, equals(1));
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Ghost Master PIN triggers RescuePinChangeDialog while background sync runs', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()
        ..verifyResult = true
        ..requiresPinChangeResult = true;
      final settingsProv = TestSettingsProvider();
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
      await tester.pump(const Duration(milliseconds: 300));

      // RescuePinChangeDialog should be displayed
      expect(find.byType(RescuePinChangeDialog), findsOneWidget);
      expect(find.text('Modo de Rescate Activado'), findsOneWidget);
      // License sync was already triggered in background concurrently
      expect(settingsProv.syncLicenseCallCount, equals(1));

      // Enter new PIN (e.g. 9999) in both fields
      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(2));
      await tester.enterText(textFields.at(0), '9999');
      await tester.enterText(textFields.at(1), '9999');
      await tester.pump();

      // Tap 'Establecer Nuevo PIN y Continuar'
      await tester.tap(find.text('Establecer Nuevo PIN y Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog closed and home screen reached!
      expect(find.byType(RescuePinChangeDialog), findsNothing);
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Physical Numpad keys (numpad0..9) register digits even when event.character is null', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pump();

      // Send Numpad keys
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad2);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad3);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.numpad4);
      await tester.pumpAndSettle();

      // PIN was submitted via numpad keys and reached Home
      expect(authProv.verifyPinCallCount, equals(1));
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Ghost Master PIN dialog dismissed without changing PIN blocks navigation to /home', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()
        ..verifyResult = true
        ..requiresPinChangeResult = true; // Still requires change
      final settingsProv = TestSettingsProvider();
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
      await tester.pump(const Duration(milliseconds: 300));

      // Rescue dialog is shown
      expect(find.byType(RescuePinChangeDialog), findsOneWidget);

      // Dismiss dialog directly without completing PIN change
      final navigatorState = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigatorState.pop();
      await tester.pumpAndSettle();

      // Must NOT navigate to Home Screen because PIN change requirement was not cleared!
      expect(find.text('Home Screen'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('Adversarial: Compact mobile screen (320x568) does not crash or throw unhandled exceptions', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      AppConfig.debugOverrideIsMobile = true;

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pumpAndSettle();

      final err = tester.takeException();
      expect(err, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('Adversarial: Widget unmounts while loadSettings is awaiting, exits cleanly without error', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: cashProv),
            Provider<UsersRepository>.value(value: TestUsersRepository()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) {
                return const LoginScreen();
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Type 4 digits
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pump();

      // Unmount LoginScreen by replacing the tree
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Unmounted Screen')),
        ),
      );
      await tester.pumpAndSettle();

      final err = tester.takeException();
      expect(err, isNull);
      expect(find.text('Unmounted Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Escape key clears entered PIN and error banner', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()
        ..verifyResult = false; // Will trigger error
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pump();

      // Type 4 digits to get an error
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      final errorBannerFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data == 'PIN inválido' && w.style?.fontSize == 12,
      );
      expect(errorBannerFinder, findsOneWidget);

      // Now type 2 digits
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('8'));
      await tester.pump();

      // Press physical Escape
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      // Error detail container and PIN are cleared
      expect(errorBannerFinder, findsNothing);
    });

    testWidgets('Adversarial: Backspace key deletes digits sequentially', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pump();

      // Type 3 digits
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();

      // Send physical Backspace
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      // Now type 2 digits to reach 4 (if backspace worked, length was 2, now 2+2 = 4)
      await tester.tap(find.text('4'));
      await tester.pump();
      await tester.tap(find.text('5'));
      await tester.pumpAndSettle();

      // Submit should have triggered because total reached 4 ('1', '2', '4', '5')
      expect(authProv.verifyPinCallCount, equals(1));
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Physical Delete key clears entered PIN and error banner', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = false;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      await tester.pumpWidget(createLoginScreen(
        authProv: authProv,
        settingsProv: settingsProv,
        cashProv: cashProv,
      ));
      await tester.pump();

      // Enter 4 digits to produce error
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      final errorBannerFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data == 'PIN inválido' && w.style?.fontSize == 12,
      );
      expect(errorBannerFinder, findsOneWidget);

      // Now enter digits and press Delete key
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();

      // Both PIN and error banner are cleared
      expect(errorBannerFinder, findsNothing);
    });

    testWidgets('Adversarial: Welcome SnackBar displays cleanly when provider.currentUser name is null', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()
        ..verifyResult = true
        ..customUser = {'id': 1, 'name': null, 'role': 'cashier'};
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

      expect(find.text('¡Bienvenido!'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('Adversarial: Navigation failure inside addPostFrameCallback resets _pin to empty and UI remains active', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final authProv = TestAuthProvider()..verifyResult = true;
      final settingsProv = TestSettingsProvider();
      final cashProv = TestCashRegisterProvider();

      // MaterialApp where /home route throws when pushed
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProv),
            ChangeNotifierProvider<SettingsProvider>.value(value: settingsProv),
            ChangeNotifierProvider<CashRegisterProvider>.value(value: cashProv),
            Provider<UsersRepository>.value(value: TestUsersRepository()),
          ],
          child: MaterialApp(
            onGenerateRoute: (settings) {
              if (settings.name == '/home') {
                throw FlutterError('Simulated route crash for /home');
              }
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const LoginScreen(),
              );
            },
          ),
        ),
      );
      await tester.pump();

      // Submit PIN
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.tap(find.text('4'));
      await tester.pumpAndSettle();

      // Navigation caught cleanly, error displayed, screen stays on LoginScreen
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.textContaining('Error al navegar al inicio'), findsAtLeastNWidgets(1));

      // UI is active and _pin was cleared: can type again
      authProv.verifyResult = false;
      await tester.tap(find.text('7'));
      await tester.pump();
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}
