import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import 'package:frontend_desktop/features/cash_register/presentation/pages/close_shift_screen.dart';
import 'package:frontend_desktop/features/cash_register/presentation/providers/cash_register_provider.dart';
import 'package:frontend_desktop/features/cash_register/domain/entities/cash_register_shift.dart';
import 'package:frontend_desktop/features/auth/presentation/providers/auth_provider.dart';

import '../../providers/cash_register_provider_test.mocks.dart';
import '../../../auth/providers/auth_provider_test.mocks.dart';

void main() {
  late MockGetCurrentShiftUseCase mockGetCurrentShiftUseCase;
  late MockOpenShiftUseCase mockOpenShiftUseCase;
  late MockCloseShiftUseCase mockCloseShiftUseCase;
  late CashRegisterProvider cashRegisterProvider;
  late MockAuthRepository mockAuthRepository;
  late AuthProvider authProvider;

  final activeShift = CashRegisterShift(
    id: 42,
    cashRegisterId: 1,
    userId: 5,
    openingBalance: 1000.0,
    status: 'open',
    openedAt: DateTime(2026, 9, 27, 8, 0),
  );

  setUp(() {
    mockGetCurrentShiftUseCase = MockGetCurrentShiftUseCase();
    mockOpenShiftUseCase = MockOpenShiftUseCase();
    mockCloseShiftUseCase = MockCloseShiftUseCase();

    cashRegisterProvider = CashRegisterProvider(
      getCurrentShiftUseCase: mockGetCurrentShiftUseCase,
      openShiftUseCase: mockOpenShiftUseCase,
      closeShiftUseCase: mockCloseShiftUseCase,
    );

    mockAuthRepository = MockAuthRepository();
    authProvider = AuthProvider(repository: mockAuthRepository);
  });

  void setDesktopSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('RenderFlex overflowed')) {
        return; // Ignore Ahem font overflow
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  group('Empirical PIN Stress Tests (Requirement 2)', () {
    testWidgets('PIN TextFormField validator blocks null, empty, whitespace and <4 digits', (tester) async {
      setDesktopSize(tester);
      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => activeShift);
      await cashRegisterProvider.checkCurrentShift();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: cashRegisterProvider),
              ChangeNotifierProvider.value(value: authProvider),
            ],
            child: const CloseShiftScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find TextFormField for PIN
      final pinFormFieldFinder = find.byType(TextFormField);
      expect(pinFormFieldFinder, findsOneWidget);

      final pinFormField = tester.widget<TextFormField>(pinFormFieldFinder);
      final validator = pinFormField.validator!;

      // 1. Blocks null
      expect(validator(null), equals('El PIN es obligatorio'));

      // 2. Blocks empty string
      expect(validator(''), equals('El PIN es obligatorio'));

      // 3. Blocks whitespace only
      expect(validator('   '), equals('El PIN es obligatorio'));

      // 4. Blocks 1 digit
      expect(validator('1'), equals('El PIN debe tener al menos 4 dígitos'));

      // 5. Blocks 2 digits
      expect(validator('12'), equals('El PIN debe tener al menos 4 dígitos'));

      // 6. Blocks 3 digits
      expect(validator('123'), equals('El PIN debe tener al menos 4 dígitos'));

      // 7. Blocks 3 digits with whitespace
      expect(validator(' 12 '), equals('El PIN debe tener al menos 4 dígitos'));

      // 8. Allows valid 4 digits
      expect(validator('1234'), isNull);

      // 9. Allows valid 6 digits
      expect(validator('123456'), isNull);
    });

    testWidgets('UI blocks shift closure when PIN is empty or <4 digits without calling provider', (tester) async {
      setDesktopSize(tester);
      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => activeShift);
      await cashRegisterProvider.checkCurrentShift();

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: cashRegisterProvider),
              ChangeNotifierProvider.value(value: authProvider),
            ],
            child: const CloseShiftScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter valid cash amount first
      final textFields = find.byType(TextField);
      // The first TextField is the counted cash input
      await tester.enterText(textFields.first, '1500.0');

      // Attempt 1: Empty PIN
      final submitButton = find.widgetWithText(ElevatedButton, 'Cerrar Turno y Generar Z');
      expect(submitButton, findsOneWidget);
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Provider closeShiftUseCase must NOT have been called
      verifyNever(mockCloseShiftUseCase.call(any, any, pin: anyNamed('pin'), closerUserId: anyNamed('closerUserId')));
      // Confirmation dialog must NOT be shown
      expect(find.text('Confirmar Cierre de Caja'), findsNothing);

      // Attempt 2: 3-digit PIN ("999")
      final pinFormFieldFinder = find.byType(TextFormField);
      await tester.enterText(pinFormFieldFinder, '999');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      verifyNever(mockCloseShiftUseCase.call(any, any, pin: anyNamed('pin'), closerUserId: anyNamed('closerUserId')));
      expect(find.text('Confirmar Cierre de Caja'), findsNothing);
    });

    testWidgets('UI forwards exact PIN to provider and usecase when >= 4 digits', (tester) async {
      setDesktopSize(tester);
      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => activeShift);
      await cashRegisterProvider.checkCurrentShift();

      when(mockCloseShiftUseCase.call(42, 1500.0, pin: '8842', closerUserId: anyNamed('closerUserId')))
          .thenThrow(Exception('Simulated API rejection for PIN forwarding test'));

      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: cashRegisterProvider),
              ChangeNotifierProvider.value(value: authProvider),
            ],
            child: const CloseShiftScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter counted cash
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.first, '1500.0');

      // Enter valid 4-digit PIN
      final pinFormFieldFinder = find.byType(TextFormField);
      await tester.enterText(pinFormFieldFinder, '8842');

      // Tap submit
      final submitButton = find.widgetWithText(ElevatedButton, 'Cerrar Turno y Generar Z');
      await tester.ensureVisible(submitButton);
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.text('Confirmar Cierre de Caja'), findsOneWidget);

      // Confirm closing
      final confirmButton = find.widgetWithText(ElevatedButton, 'Cerrar Turno');
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      // Verify that mockCloseShiftUseCase was called with the exact PIN '8842'
      verify(mockCloseShiftUseCase.call(42, 1500.0, pin: '8842', closerUserId: anyNamed('closerUserId'))).called(1);
    });

    test('CashRegisterProvider forwards PIN correctly down the pipeline', () async {
      when(mockGetCurrentShiftUseCase.call(registerId: anyNamed('registerId')))
          .thenAnswer((_) async => activeShift);
      await cashRegisterProvider.checkCurrentShift();

      when(mockCloseShiftUseCase.call(42, 2000.0, pin: '5566', closerUserId: 7))
          .thenAnswer((_) async => CashRegisterShift(
                id: 42,
                cashRegisterId: 1,
                userId: 5,
                openingBalance: 1000.0,
                status: 'closed',
                openedAt: DateTime.now(),
              ));

      final result = await cashRegisterProvider.closeShift(
        2000.0,
        pin: '5566',
        closerUserId: 7,
      );

      expect(result, isNotNull);
      expect(result!.status, 'closed');
      verify(mockCloseShiftUseCase.call(42, 2000.0, pin: '5566', closerUserId: 7)).called(1);
    });
  });
}
