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

  bool get isLoading => _isLoading;
  List<Supplier> get suppliers => _suppliers;
  String get searchQuery => _searchQuery;

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
        throw Exception(_parseError(response));
      }
    } catch (e) {
      _suppliers = [];
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createSupplier(Map<String, dynamic> data) async {
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
        await fetchSuppliers(search: _searchQuery);
        return true;
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
  
  void setSearchQuery(String query) {
    _searchQuery = query;
    fetchSuppliers(search: query);
  }
}
