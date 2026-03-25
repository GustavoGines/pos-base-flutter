import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/customer_model.dart';

class CustomerProvider extends ChangeNotifier {
  final String baseUrl;
  
  bool _isLoading = false;
  List<Customer> _customers = [];
  String _searchQuery = '';
  List<Map<String, dynamic>> _pendingSales = [];

  bool get isLoading => _isLoading;
  List<Customer> get customers => _customers;
  String get searchQuery => _searchQuery;
  List<Map<String, dynamic>> get pendingSales => _pendingSales;

  CustomerProvider({required this.baseUrl});

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

  // Plan detectado para Feature Gating. Solo bloquea cuando el plan fue confirmado.
  String _currentPlan = 'basic';
  bool _planConfirmed = false;

  void setCurrentPlan(String plan) {
    _currentPlan = plan;
    _planConfirmed = true;
  }

  Future<void> fetchCustomers({String? search}) async {
    if (_planConfirmed && _currentPlan == 'basic') {
      throw Exception('El módulo de Cuentas Corrientes requiere el Plan PRO.');
    }
    _isLoading = true;
    notifyListeners();
    
    try {
      final queryParam = (search != null && search.isNotEmpty) ? '?search=$search' : '';
      final response = await http.get(Uri.parse('$baseUrl/customers$queryParam'), headers: {
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

  Future<bool> createCustomer(Map<String, dynamic> data) async {
    if (_planConfirmed && _currentPlan == 'basic') {
      throw Exception('El módulo de Cuentas Corrientes requiere el Plan PRO.');
    }
    try {
      if (!data.containsKey('balance') || data['balance'].toString().isEmpty) {
        data['balance'] = 0.00;
      }
      
      final response = await http.post(
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
      final response = await http.put(
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
      final response = await http.delete(
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
      final response = await http.get(
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
    required double amount, 
    required String paymentMethod,
    String description = '',
    List<int> saleIds = const [],
  }) async {
    try {
      final Map<String, dynamic> bodyPayload = {
        'amount': amount,
        'payment_method': paymentMethod,
      };

      if (description.isNotEmpty) {
        bodyPayload['description'] = description;
      }
      
      if (saleIds.isNotEmpty) {
        bodyPayload['sale_ids'] = saleIds;
      }

      final response = await http.post(
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
      final response = await http.get(Uri.parse('$baseUrl/customers/$customerId'), headers: {
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
