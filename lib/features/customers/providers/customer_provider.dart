import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/customer_model.dart';
import '../../../../core/network/api_client.dart';

class CustomerProvider extends ChangeNotifier {
  final String baseUrl;
  final ApiClient client;

  bool _isLoading = false;
  List<Customer> _customers = [];
  String _searchQuery = '';
  List<Map<String, dynamic>> _pendingSales = [];
  final Map<String, Map<String, dynamic>> _padronCache = {};

  bool get isLoading => _isLoading;
  List<Customer> get customers => _customers;
  String get searchQuery => _searchQuery;
  List<Map<String, dynamic>> get pendingSales => _pendingSales;

  CustomerProvider({required this.baseUrl, required this.client});

  String _parseError(http.Response response) {
    try {
      final errData = json.decode(response.body);
      if (errData['errors'] != null && errData['errors'].isNotEmpty) {
        final firstKey = errData['errors'].keys.first;
        return errData['errors'][firstKey][0];
      }
      return errData['message'] ?? errData['error'] ?? 'Error desconocido';
    } catch (_) {
      return 'Error ${response.statusCode}';
    }
  }

  // Plan detectado para Feature Gating. Solo bloquea cuando fue confirmado.
  bool _hasAccessToModule = false;
  bool _accessConfirmed = false;

  void setAccess(bool hasAccess) {
    _hasAccessToModule = hasAccess;
    _accessConfirmed = true;
  }

  Future<void> fetchCustomers({String? search}) async {
    if (_accessConfirmed && !_hasAccessToModule) {
      throw Exception('El módulo de Cuentas Corrientes requiere el Plan Premium o el módulo adicional habilitado.');
    }
    _isLoading = true;
    notifyListeners();

    try {
      final queryParam = (search != null && search.isNotEmpty) ? '?search=$search' : '';
      final response = await client.get(Uri.parse('$baseUrl/customers$queryParam'), headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['data'] as List;
        _customers = items.map((e) => Customer.fromJson(e)).toList();
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      _customers = [];
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Consulta datos fiscales por DNI (7-8 dígitos) o CUIT/CUIL (11 dígitos)
  /// en el backend (Clientes locales -> Historial de facturas -> Padrón Oficial ARCA).
  Future<Map<String, dynamic>?> lookupFiscalRecipient(String rawDocNumber) async {
    final clean = rawDocNumber.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 7 || (clean.length > 8 && clean.length != 11)) {
      return null;
    }
    if (clean.length == 11 && !AfipModulo11.validateCuit(clean)) {
      return null;
    }
    if (_padronCache.containsKey(clean)) {
      return _padronCache[clean];
    }

    try {
      final response = await client.get(
        Uri.parse('$baseUrl/electronic-invoices/lookup-recipient?doc_number=$clean'),
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>?;
        if (data != null && data['found'] == true) {
          _padronCache[clean] = data;
          return data;
        }
      }
    } catch (_) {
      // Silencioso: no bloquea el flujo de cobro si ARCA no está disponible
    }
    return null;
  }

  Future<bool> createCustomer(Map<String, dynamic> data) async {
    if (_accessConfirmed && !_hasAccessToModule) {
      throw Exception('El módulo de Cuentas Corrientes requiere el Plan Premium o el módulo adicional habilitado.');
    }
    try {
      if (!data.containsKey('balance') || data['balance'].toString().isEmpty) {
        data['balance'] = 0.00;
      }

      final response = await client.post(
        Uri.parse('$baseUrl/customers'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 201) {
        await fetchCustomers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> updateCustomer(int id, Map<String, dynamic> data) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/customers/$id'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        await fetchCustomers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> deleteCustomer(int id) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/customers/$id'),
        headers: {
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        await fetchCustomers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> fetchPendingSales(int customerId) async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/customers/$customerId/pending-sales'),
        headers: {
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _pendingSales = data.map((item) => item as Map<String, dynamic>).toList();
        notifyListeners();
      }
    } catch (e) {
      _pendingSales = [];
      notifyListeners();
    }
  }

  Future<void> clearPendingSales() async {
    _pendingSales = [];
    notifyListeners();
  }

  Future<bool> registerPayment({
    required int customerId,
    double? amount,
    String? paymentMethod,
    List<Map<String, dynamic>>? payments,
    String description = '',
    List<int> saleIds = const [],
    dynamic checkDetails,
    int? cashShiftId,
    int? cashRegisterId,
    bool isRefund = false,
  }) async {
    try {
      final Map<String, dynamic> bodyPayload = {};

      if (payments != null && payments.isNotEmpty) {
        bodyPayload['payments'] = payments;
      } else if (amount != null && paymentMethod != null) {
        bodyPayload['amount'] = amount;
        bodyPayload['payment_method'] = paymentMethod;
      } else {
        throw Exception("Debes proveer 'payments' o bien 'amount' y 'paymentMethod'");
      }

      if (description.isNotEmpty) {
        bodyPayload['description'] = description;
      }

      if (saleIds.isNotEmpty) {
        bodyPayload['sale_ids'] = saleIds;
      }

      if (checkDetails != null) {
        bodyPayload['check_details'] = checkDetails;
      }

      if (cashShiftId != null) {
        bodyPayload['cash_shift_id'] = cashShiftId;
      }

      if (cashRegisterId != null && cashRegisterId > 0) {
        bodyPayload['cash_register_id'] = cashRegisterId;
      }

      bodyPayload['is_refund'] = isRefund;

      final response = await client.post(
        Uri.parse('$baseUrl/customers/$customerId/payments'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(bodyPayload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final idx = _customers.indexWhere((c) => c.id == customerId);
        if (idx != -1) {
          await fetchSingleCustomer(customerId);
        }
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> fetchSingleCustomer(int customerId) async {
    try {
      final response = await client.get(Uri.parse('$baseUrl/customers/$customerId'), headers: {
        'Accept': 'application/json',
      });
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final updatedCustomer = Customer.fromJson(data);
        final idx = _customers.indexWhere((c) => c.id == customerId);
        if (idx != -1) {
          _customers[idx] = updatedCustomer;
          notifyListeners();
        }
      }
    } catch (e) {
      // Silencioso
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    fetchCustomers(search: query);
  }
}
