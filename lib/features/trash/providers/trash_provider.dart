import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/network/api_client.dart';

class TrashItem {
  final int id;
  final String title;
  final String subtitle;
  final DateTime deletedAt;

  TrashItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.deletedAt,
  });

  factory TrashItem.fromJson(Map<String, dynamic> json, String type) {
    String title = json['name'] ?? 'Sin nombre';
    String subtitle = '';

    if (type == 'customers') {
      subtitle = 'DNI: ${json['document_number'] ?? '-'}';
    } else if (type == 'products') {
      subtitle = 'Cód: ${json['barcode'] ?? json['internal_code'] ?? '-'}';
    } else if (type == 'suppliers') {
      subtitle = 'CUIT: ${json['cuit'] ?? '-'}';
    } else if (type == 'cash_movements') {
      title = '${json['category']} (\$${json['amount']})';
      subtitle = json['description'] ?? 'Movimiento de caja';
    }

    return TrashItem(
      id: json['id'],
      title: title,
      subtitle: subtitle,
      deletedAt: DateTime.parse(json['deleted_at']).toLocal(),
    );
  }
}

class TrashProvider extends ChangeNotifier {
  final String baseUrl;
  final ApiClient client;
  
  bool _isLoading = false;
  List<TrashItem> _items = [];
  String _currentType = 'customers';
  
  bool get isLoading => _isLoading;
  List<TrashItem> get items => _items;
  String get currentType => _currentType;

  TrashProvider({required this.baseUrl, required this.client});

  Future<void> fetchTrash(String type) async {
    _currentType = type;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await client.get(Uri.parse('$baseUrl/trash/$type'), headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _items = (data['data'] as List).map((e) => TrashItem.fromJson(e, type)).toList();
      } else {
        throw Exception('Error al cargar la papelera');
      }
    } catch (e) {
      debugPrint('Error en fetchTrash: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _parseError(http.Response response) {
    try {
      final errData = json.decode(response.body);
      return errData['message'] ?? errData['error'] ?? 'Error del servidor';
    } catch (_) {
      return 'Error ${response.statusCode}';
    }
  }

  Future<void> restoreItem(int id) async {
    final response = await client.post(
      Uri.parse('$baseUrl/trash/$_currentType/$id/restore'),
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      _items.removeWhere((item) => item.id == id);
      notifyListeners();
    } else {
      throw Exception(_parseError(response));
    }
  }

  Future<void> forceDeleteItem(int id) async {
    final response = await client.delete(
      Uri.parse('$baseUrl/trash/$_currentType/$id/force'),
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      _items.removeWhere((item) => item.id == id);
      notifyListeners();
    } else {
      throw Exception(_parseError(response));
    }
  }
}
