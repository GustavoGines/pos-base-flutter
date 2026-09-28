import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/cash_register/data/models/cash_register_shift_model.dart';

void main() {
  group('CashRegisterShiftModel check_details JSON parsing stress tests', () {
    final baseJson = {
      'id': 1,
      'cash_register_id': 1,
      'user_id': 1,
      'opened_at': '2026-09-28T00:00:00Z',
      'opening_balance': 1000.0,
      'status': 'open',
    };

    test('Case 1: check_details is null', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['check_details'] = null;

      final model = CashRegisterShiftModel.fromJson(json);
      expect(model.checkDetails, isNull);
    });

    test('Case 2: check_details is an empty List []', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['check_details'] = <dynamic>[];

      final model = CashRegisterShiftModel.fromJson(json);
      expect(model.checkDetails, isNotNull);
      expect(model.checkDetails, isEmpty);
    });

    test('Case 3: check_details is an empty string ""', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['check_details'] = '';

      final model = CashRegisterShiftModel.fromJson(json);
      expect(model.checkDetails, isNotNull);
      expect(model.checkDetails, isEmpty);
    });

    test('Case 4: check_details is a JSON-encoded empty array "[]"', () {
      final json = Map<String, dynamic>.from(baseJson);
      json['check_details'] = '[]';

      final model = CashRegisterShiftModel.fromJson(json);
      expect(model.checkDetails, isNotNull);
      expect(model.checkDetails, isEmpty);
    });

    test('Case 5: check_details is a JSON encoded string array with checks (reproducing Master Report bug scenario)', () {
      final checks = [
        {
          'bank': 'Banco Santander',
          'number': '00123456',
          'amount': 45000.0,
          'due_date': '2026-10-15',
        },
        {
          'bank': 'Banco Galicia',
          'number': '99887766',
          'amount': 22500.50,
          'due_date': '2026-10-20',
        },
      ];
      final json = Map<String, dynamic>.from(baseJson);
      json['check_details'] = jsonEncode(checks);

      final model = CashRegisterShiftModel.fromJson(json);
      expect(model.checkDetails, isNotNull);
      expect(model.checkDetails!.length, equals(2));
      expect(model.checkDetails![0]['bank'], equals('Banco Santander'));
      expect(model.checkDetails![0]['amount'], equals(45000.0));
      expect(model.checkDetails![1]['bank'], equals('Banco Galicia'));
      expect(model.checkDetails![1]['number'], equals('99887766'));
    });

    test('Case 6: check_details is already a List of Maps (direct Dart objects from decoded response)', () {
      final checks = [
        {
          'bank': 'BBVA',
          'number': '55443322',
          'amount': 12000.0,
        },
      ];
      final json = Map<String, dynamic>.from(baseJson);
      json['check_details'] = checks;

      final model = CashRegisterShiftModel.fromJson(json);
      expect(model.checkDetails, isNotNull);
      expect(model.checkDetails!.length, equals(1));
      expect(model.checkDetails![0]['bank'], equals('BBVA'));
      expect(model.checkDetails![0]['amount'], equals(12000.0));
    });

    test('Case 7: check_details with special characters / accents in JSON string', () {
      final checkString = '[{"bank": "Banco de la Nación Argentina", "number": "123-Ñ-ñ", "issuer": "José Pérez"}]';
      final json = Map<String, dynamic>.from(baseJson);
      json['check_details'] = checkString;

      final model = CashRegisterShiftModel.fromJson(json);
      expect(model.checkDetails, isNotNull);
      expect(model.checkDetails!.length, equals(1));
      expect(model.checkDetails![0]['bank'], equals('Banco de la Nación Argentina'));
      expect(model.checkDetails![0]['issuer'], equals('José Pérez'));
    });
  });
}
