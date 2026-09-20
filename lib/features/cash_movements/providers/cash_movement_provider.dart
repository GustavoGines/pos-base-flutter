import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/cash_movement_model.dart';
import '../../../core/network/api_client.dart';

class CashMovementProvider extends ChangeNotifier {
  final String baseUrl;
  final ApiClient client;
  
  bool _isLoading = false;
  List<CashMovementModel> _movements = [];
  int _currentPage = 1;
  int _lastPage = 1;
  bool _hasMore = true;

  bool get isLoading => _isLoading;
  List<CashMovementModel> get movements => _movements;
  bool get hasMore => _hasMore;

  CashMovementProvider({required this.baseUrl, required this.client});

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

  Future<void> fetchMovements({bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _currentPage = 1;
      _movements = [];
      _hasMore = true;
    }

    if (!_hasMore) return;

    _isLoading = true;
    notifyListeners();
    
    try {
      final response = await client.get(Uri.parse('$baseUrl/cash-movements?page=$_currentPage'), headers: {
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = json.decode(response.body);
        final List<dynamic> data = body['data'] ?? [];
        
        final newMovements = data.map((e) => CashMovementModel.fromJson(e)).toList();
        
        if (refresh) {
          _movements = newMovements;
        } else {
          _movements.addAll(newMovements);
        }

        _currentPage = body['current_page'] ?? 1;
        _lastPage = body['last_page'] ?? 1;
        _hasMore = _currentPage < _lastPage;
        
        if (_hasMore) {
           _currentPage++;
        }
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      debugPrint('Error fetchMovements: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Crea un movimiento de caja y retorna los IDs generados.
  /// Programación Defensiva: si el backend es viejo y no envía IDs, retorna lista vacía.
  Future<List<int>> createMovement(Map<String, dynamic> data, {String? adminPin}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final headers = {'Accept': 'application/json', 'Content-Type': 'application/json'};
      if (adminPin != null && adminPin.isNotEmpty) {
        headers['X-Admin-Pin'] = adminPin;
      }

      final response = await client.post(
        Uri.parse('$baseUrl/cash-movements'),
        headers: headers,
        body: json.encode(data),
      );

      if (response.statusCode == 201) {
        // Extraer IDs de los movimientos creados (Programación Defensiva)
        List<int> createdIds = [];
        try {
          final body = json.decode(response.body);
          if (body is Map && body['movements'] is List) {
            createdIds = (body['movements'] as List)
                .map((m) => m['id'] as int)
                .toList();
          }
        } catch (_) {
          // Backend viejo: no envía IDs, no pasa nada
          debugPrint('createMovement: backend no retornó IDs (versión antigua)');
        }

        // Recargar movimientos tras éxito
        await fetchMovements();
        return createdIds;
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      debugPrint('Error createMovement: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteMovement(int id, {required String adminPin}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await client.delete(
        Uri.parse('$baseUrl/cash-movements/$id'),
        headers: {
          'Accept': 'application/json',
          'X-Admin-Pin': adminPin,
        },
      );

      if (response.statusCode == 200) {
        await fetchMovements();
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      debugPrint('Error deleteMovement: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
