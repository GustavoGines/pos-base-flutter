import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_desktop/features/pos/data/datasources/pos_remote_datasource.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const baseUrl = 'http://localhost/api';

  group('PosRemoteDataSourceImpl.createDeliveryNoteFromSale', () {
    test('retorna JSON cuando el backend responde 201 (nuevo remito creado)', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/delivery-notes/from-sale/123');
        expect(request.method, 'POST');
        return http.Response(
          json.encode({'id': 1, 'sale_id': 123, 'status': 'pending'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final datasource = PosRemoteDataSourceImpl(baseUrl: baseUrl, client: mockClient);
      final result = await datasource.createDeliveryNoteFromSale(123, fulfillmentStatus: 'pending');

      expect(result['id'], 1);
      expect(result['sale_id'], 123);
      expect(result['status'], 'pending');
    });

    test('retorna JSON cuando el backend responde 200 (remito preexistente idempotente)', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/delivery-notes/from-sale/123');
        return http.Response(
          json.encode({'id': 1, 'sale_id': 123, 'status': 'pending'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final datasource = PosRemoteDataSourceImpl(baseUrl: baseUrl, client: mockClient);
      final result = await datasource.createDeliveryNoteFromSale(123, fulfillmentStatus: 'pending');

      expect(result['id'], 1);
      expect(result['sale_id'], 123);
    });

    test('lanza Exception cuando el backend responde con error 500', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final datasource = PosRemoteDataSourceImpl(baseUrl: baseUrl, client: mockClient);

      expect(
        () => datasource.createDeliveryNoteFromSale(123),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'mensaje',
          contains('Error al crear remito'),
        )),
      );
    });
  });
}
