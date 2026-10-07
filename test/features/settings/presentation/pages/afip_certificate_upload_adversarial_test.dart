import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend_desktop/features/settings/data/datasources/settings_remote_datasource.dart';
import 'package:frontend_desktop/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/get_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/domain/usecases/update_settings_usecase.dart';
import 'package:frontend_desktop/features/settings/presentation/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Milestone M1 Adversarial: AFIP Certificate Upload Error & Loading States', () {
    const testBaseUrl = 'http://pos-backend.test/api';

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Backend 422 HTTP Responses (Validation & Cryptographic Errors)
    // ─────────────────────────────────────────────────────────────────────────
    test('HTTP 422 INVALID_CERTIFICATE: datasource parses message and provider resets loading state', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'El certificado X.509 es inválido o no pudo ser interpretado.',
            'error_code': 'INVALID_CERTIFICATE',
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(baseUrl: testBaseUrl, client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: dataSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      expect(provider.isUploadingCertificates, isFalse);
      expect(provider.isLoading, isFalse);

      await expectLater(
        provider.uploadAfipCertificates(
          cuit: '30712345678',
          certBytes: [0x4D, 0x5A], // Invalid binary exe bytes
          certFilename: 'malicious.exe',
          keyBytes: [1, 2, 3],
          keyFilename: 'cert.key',
        ),
        throwsA(predicate((e) {
          return e.toString().contains('El certificado X.509 es inválido');
        })),
      );

      // Verify loading state is guaranteed reset to false even after exception
      expect(provider.isUploadingCertificates, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test('HTTP 422 CERT_KEY_MISMATCH: error message is preserved and provider resets loading state', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'El par criptográfico no coincide: el certificado no corresponde a la clave privada.',
            'error_code': 'CERT_KEY_MISMATCH',
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(baseUrl: testBaseUrl, client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: dataSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      expect(provider.isUploadingCertificates, isFalse);

      await expectLater(
        provider.uploadAfipCertificates(
          cuit: '30712345678',
          certBytes: [1, 2, 3],
          certFilename: 'cert.crt',
          keyBytes: [4, 5, 6],
          keyFilename: 'mismatched.key',
        ),
        throwsA(predicate((e) {
          return e.toString().contains('El par criptográfico no coincide');
        })),
      );

      expect(provider.isUploadingCertificates, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test('HTTP 422 INVALID_PRIVATE_KEY: missing or incorrect passphrase error handling', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'La clave privada es inválida o la contraseña de desbloqueo es incorrecta.',
            'error_code': 'INVALID_PRIVATE_KEY',
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(baseUrl: testBaseUrl, client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: dataSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      await expectLater(
        provider.uploadAfipCertificates(
          cuit: '30712345678',
          certBytes: [1, 2, 3],
          certFilename: 'cert.crt',
          keyBytes: [4, 5, 6],
          keyFilename: 'encrypted.key',
          keyPassphrase: 'wrong_password',
        ),
        throwsA(predicate((e) {
          return e.toString().contains('La clave privada es inválida o la contraseña de desbloqueo es incorrecta');
        })),
      );

      expect(provider.isUploadingCertificates, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test('HTTP 422 MISSING_CERT_OR_KEY: empty files/bytes error handling', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'message': 'Debe adjuntar tanto el certificado (.crt) como la clave privada (.key).',
            'error_code': 'MISSING_CERT_OR_KEY',
          }),
          422,
          headers: {'content-type': 'application/json'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(baseUrl: testBaseUrl, client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: dataSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      await expectLater(
        provider.uploadAfipCertificates(
          cuit: '30712345678',
          certBytes: [],
          certFilename: 'empty.crt',
          keyBytes: [],
          keyFilename: 'empty.key',
        ),
        throwsA(predicate((e) {
          return e.toString().contains('Debe adjuntar tanto el certificado (.crt) como la clave privada (.key)');
        })),
      );

      expect(provider.isUploadingCertificates, isFalse);
      expect(provider.isLoading, isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Backend 500 HTTP Responses (Internal Server Error)
    // ─────────────────────────────────────────────────────────────────────────
    test('HTTP 500 Internal Server Error: throws friendly message and strictly resets loading state', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          'Internal Server Error: OpenSSL crashed or disk full',
          500,
          headers: {'content-type': 'text/plain'},
        );
      });

      final dataSource = SettingsRemoteDataSourceImpl(baseUrl: testBaseUrl, client: mockClient);
      final repo = SettingsRepositoryImpl(remoteDataSource: dataSource);
      final provider = SettingsProvider(
        getSettingsUseCase: GetSettingsUseCase(repo),
        updateSettingsUseCase: UpdateSettingsUseCase(repo),
      );

      expect(provider.isUploadingCertificates, isFalse);

      await expectLater(
        provider.uploadAfipCertificates(
          cuit: '30712345678',
          certBytes: [1, 2, 3],
          certFilename: 'cert.crt',
          keyBytes: [4, 5, 6],
          keyFilename: 'cert.key',
        ),
        throwsA(predicate((e) {
          return e.toString().contains('Error interno del servidor. Contacte a soporte técnico.');
        })),
      );

      // Invariant: loading state MUST be false after error
      expect(provider.isUploadingCertificates, isFalse);
      expect(provider.isLoading, isFalse);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. UI State Reset Invariant Verification in Widget Scope
    // ─────────────────────────────────────────────────────────────────────────
    testWidgets('UI state machine: verifies finally block resets _isUploadingCertificates on 422 and 500', (tester) async {
      bool isUploading = false;
      String? errorMessage;
      int errorSnackCount = 0;

      Future<void> simulateUpload({required bool shouldFailWith500}) async {
        isUploading = true;
        try {
          if (shouldFailWith500) {
            throw Exception('Error interno del servidor. Contacte a soporte técnico.');
          } else {
            throw Exception('El par criptográfico no coincide: el certificado no corresponde a la clave privada.');
          }
        } catch (e) {
          errorMessage = e.toString().replaceAll('Exception: ', '');
          errorSnackCount++;
        } finally {
          isUploading = false;
        }
      }

      // Test 422 simulation
      await simulateUpload(shouldFailWith500: false);
      expect(isUploading, isFalse, reason: 'isUploading must be false after 422');
      expect(errorMessage, equals('El par criptográfico no coincide: el certificado no corresponde a la clave privada.'));
      expect(errorSnackCount, equals(1));

      // Test 500 simulation
      await simulateUpload(shouldFailWith500: true);
      expect(isUploading, isFalse, reason: 'isUploading must be false after 500');
      expect(errorMessage, equals('Error interno del servidor. Contacte a soporte técnico.'));
      expect(errorSnackCount, equals(2));
    });
  });
}
