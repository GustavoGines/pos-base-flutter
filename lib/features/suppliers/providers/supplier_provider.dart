import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/supplier_model.dart';
import '../../../core/network/api_client.dart';

class SupplierProvider extends ChangeNotifier {
  final String baseUrl;
  final ApiClient client;
  
  bool _isLoading = false;
  List<Supplier> _suppliers = [];
  String _searchQuery = '';
  String? _errorMessage;

  bool get isLoading => _isLoading;
  List<Supplier> get suppliers => _suppliers;
  String get searchQuery => _searchQuery;
  String? get errorMessage => _errorMessage;

  SupplierProvider({required this.baseUrl, required this.client});

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

  Future<void> fetchSuppliers({String? search}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    
    try {
      final response = await client.get(Uri.parse('$baseUrl/suppliers'), headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        _suppliers = data.map((e) => Supplier.fromJson(e)).toList();

        if (search != null && search.isNotEmpty) {
          final query = search.toLowerCase();
          _suppliers = _suppliers.where((s) {
            return s.name.toLowerCase().contains(query) || 
                   (s.cuit != null && s.cuit!.contains(query));
          }).toList();
        }
      } else {
        _errorMessage = _parseError(response);
      }
    } catch (e) {
      // No borramos la lista previa en caso de error de red ni propagamos excepción no capturada a PlatformDispatcher
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int?> createSupplier(Map<String, dynamic> data) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/suppliers'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 201) {
        final Map<String, dynamic> body = json.decode(response.body);
        final newId = body['id'] as int?;
        await fetchSuppliers(search: _searchQuery);
        return newId;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> updateSupplier(int id, Map<String, dynamic> data) async {
    try {
      final response = await client.put(
        Uri.parse('$baseUrl/suppliers/$id'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        await fetchSuppliers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> deleteSupplier(int id) async {
    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/suppliers/$id'),
        headers: {
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        await fetchSuppliers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> createInvoice(int supplierId, Map<String, dynamic> data) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/suppliers/$supplierId/invoices'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(data),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        await fetchSuppliers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> updateInvoice(int invoiceId, Map<String, dynamic> data, {String? adminPin}) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      if (adminPin != null && adminPin.isNotEmpty) {
        headers['X-Admin-Pin'] = adminPin;
      }
      final response = await client.put(
        Uri.parse('$baseUrl/supplier-invoices/$invoiceId'),
        headers: headers,
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        await fetchSuppliers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> deleteInvoice(int invoiceId, {String? reason, String? adminPin}) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      if (adminPin != null && adminPin.isNotEmpty) {
        headers['X-Admin-Pin'] = adminPin;
      }
      final response = await client.delete(
        Uri.parse('$baseUrl/supplier-invoices/$invoiceId'),
        headers: headers,
        body: json.encode({
          if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        await fetchSuppliers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<bool> restoreInvoice(int invoiceId, {String? adminPin}) async {
    try {
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (adminPin != null && adminPin.isNotEmpty) {
        headers['X-Admin-Pin'] = adminPin;
      }
      final response = await client.post(
        Uri.parse('$baseUrl/supplier-invoices/$invoiceId/restore'),
        headers: headers,
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        await fetchSuppliers(search: _searchQuery);
        return true;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<Map<String, dynamic>> fetchSupplierInvoiceDetail(int invoiceId, {String? adminPin}) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (adminPin != null && adminPin.isNotEmpty) {
        headers['X-Admin-Pin'] = adminPin;
      }
      final response = await client.get(
        Uri.parse('$baseUrl/supplier-invoices/$invoiceId'),
        headers: headers,
      );
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(json.decode(response.body) as Map);
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<Map<String, dynamic>> fetchCurrentAccount(int supplierId, {String? adminPin}) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (adminPin != null && adminPin.isNotEmpty) {
        headers['X-Admin-Pin'] = adminPin;
      }
      final response = await client.get(
        Uri.parse('$baseUrl/suppliers/$supplierId/current-account'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<List<Map<String, dynamic>>> fetchSupplierInvoices({
    int? supplierId,
    String? type,
    String? status,
    String? auditFilter,
    String? search,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? adminPin,
  }) async {
    try {
      final headers = <String, String>{'Accept': 'application/json'};
      if (adminPin != null && adminPin.isNotEmpty) {
        headers['X-Admin-Pin'] = adminPin;
      }
      final queryParams = <String, String>{};
      if (supplierId != null) queryParams['supplier_id'] = supplierId.toString();
      if (type != null && type.isNotEmpty && type != 'all') queryParams['type'] = type;
      if (status != null && status.isNotEmpty && status != 'all') queryParams['status'] = status;
      if (auditFilter != null && auditFilter.isNotEmpty) queryParams['audit_filter'] = auditFilter;
      if (search != null && search.trim().isNotEmpty) queryParams['search'] = search.trim();
      if (dateFrom != null) {
        queryParams['date_from'] =
            '${dateFrom.year.toString().padLeft(4, '0')}-${dateFrom.month.toString().padLeft(2, '0')}-${dateFrom.day.toString().padLeft(2, '0')}';
      }
      if (dateTo != null) {
        queryParams['date_to'] =
            '${dateTo.year.toString().padLeft(4, '0')}-${dateTo.month.toString().padLeft(2, '0')}-${dateTo.day.toString().padLeft(2, '0')}';
      }

      final uri = Uri.parse('$baseUrl/supplier-invoices').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final response = await client.get(uri, headers: headers);
      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        final list = (decoded is Map ? decoded['data'] : decoded) as List<dynamic>? ?? [];
        return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    fetchSuppliers(search: query);
  }
}
