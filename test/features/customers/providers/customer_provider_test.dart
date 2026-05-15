import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:http/http.dart' as http;
import 'package:frontend_desktop/features/customers/providers/customer_provider.dart';
import 'package:frontend_desktop/core/network/api_client.dart';

@GenerateMocks([ApiClient])
import 'customer_provider_test.mocks.dart';

void main() {
  late CustomerProvider provider;
  late MockApiClient mockApiClient;

  setUp(() {
    mockApiClient = MockApiClient();
    provider = CustomerProvider(baseUrl: 'http://test.com', client: mockApiClient);
    provider.setAccess(true); // Simulamos que tiene licencia premium para Cuentas Corrientes
  });

  group('CustomerProvider (Cuentas Corrientes)', () {
    test('Simula pago parcial y actualiza el cliente correctamente', () async {
      final customerId = 1;
      
      // 1. Mock de fetchSingleCustomer (El cliente originalmente debe 1000)
      when(mockApiClient.get(Uri.parse('http://test.com/customers/$customerId'), headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response(json.encode({
                'id': customerId,
                'name': 'Juan Perez',
                'balance': 1000.0,
                'active': 1
              }), 200));

      // Cargamos el cliente en memoria para tenerlo en la lista
      when(mockApiClient.get(Uri.parse('http://test.com/customers'), headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response(json.encode({
                'data': [{
                  'id': customerId,
                  'name': 'Juan Perez',
                  'balance': 1000.0,
                  'active': 1
                }]
              }), 200));
              
      await provider.fetchCustomers();
      expect(provider.customers.first.balance, 1000.0);

      // 2. Mock del endpoint de pagos (Simulamos que paga 400 y devuelve OK)
      when(mockApiClient.post(
        Uri.parse('http://test.com/customers/$customerId/payments'),
        headers: anyNamed('headers'),
        body: anyNamed('body'),
      )).thenAnswer((_) async => http.Response(json.encode({'success': true}), 201));

      // 3. Mock de fetchSingleCustomer (Después del pago el cliente debe 600)
      when(mockApiClient.get(Uri.parse('http://test.com/customers/$customerId'), headers: anyNamed('headers')))
          .thenAnswer((_) async => http.Response(json.encode({
                'id': customerId,
                'name': 'Juan Perez',
                'balance': 600.0,
                'active': 1
              }), 200));

      // 4. Ejecutamos el pago parcial de 400
      final result = await provider.registerPayment(
        customerId: customerId,
        amount: 400.0,
        paymentMethod: 'cash',
        description: 'Abono parcial'
      );

      // 5. Validamos estado
      expect(result, true);
      // Validamos que el balance local se redujo correctamente a 600
      expect(provider.customers.first.balance, 600.0);
    });
  });
}
