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

  double _kpiTotalIn = 0;
  double _kpiTotalOut = 0;
  double _kpiNet = 0;
  
  double get kpiTotalIn => _kpiTotalIn;
  double get kpiTotalOut => _kpiTotalOut;
  double get kpiNet => _kpiNet;

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

  String? _currentCategoryFilter;
  String? get currentCategoryFilter => _currentCategoryFilter;
  bool _currentAllFilter = false;
  bool get currentAllFilter => _currentAllFilter;
  
  DateTime? _startDate;
  DateTime? get startDate => _startDate;
  
  DateTime? _endDate;
  DateTime? get endDate => _endDate;

  int _fetchId = 0;

  Future<void> fetchMovements({
    bool refresh = false, 
    String? category, 
    bool? all, 
    bool clearCategory = false,
    DateTime? startDate,
    DateTime? endDate,
    bool clearDates = false,
  }) async {
    if (_isLoading && !refresh) return;

    final currentFetchId = ++_fetchId;

    if (refresh) {
      _currentPage = 1;
      _movements = [];
      _hasMore = true;
      if (clearCategory) {
        _currentCategoryFilter = null;
      } else if (category != null) {
        _currentCategoryFilter = category;
      }
      if (all != null) {
        _currentAllFilter = all;
      }
      if (clearDates) {
        _startDate = null;
        _endDate = null;
      } else {
        if (startDate != null) _startDate = startDate;
        if (endDate != null) _endDate = endDate;
      }
    }

    if (!_hasMore) return;

    _isLoading = true;
    notifyListeners();
    
    try {
      String url = '$baseUrl/cash-movements?page=$_currentPage';
      if (_currentCategoryFilter != null && _currentCategoryFilter!.isNotEmpty) {
        url += '&category=${Uri.encodeComponent(_currentCategoryFilter!)}';
      }
      if (_currentAllFilter) {
        url += '&all=1';
        if (_startDate != null && _endDate != null) {
          // Format as YYYY-MM-DD
          final sd = "${_startDate!.year}-${_startDate!.month.toString().padLeft(2, '0')}-${_startDate!.day.toString().padLeft(2, '0')}";
          final ed = "${_endDate!.year}-${_endDate!.month.toString().padLeft(2, '0')}-${_endDate!.day.toString().padLeft(2, '0')}";
          url += '&start_date=$sd&end_date=$ed';
        }
      }
      final response = await client.get(Uri.parse(url), headers: {
        'Accept': 'application/json',
      });

      if (currentFetchId != _fetchId) return;

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
        
        _kpiTotalIn = double.tryParse(body['kpi_total_in']?.toString() ?? '0') ?? 0.0;
        _kpiTotalOut = double.tryParse(body['kpi_total_out']?.toString() ?? '0') ?? 0.0;
        _kpiNet = double.tryParse(body['kpi_net']?.toString() ?? '0') ?? 0.0;

        if (_hasMore) {
           _currentPage++;
        }
      } else {
        throw Exception(_parseError(response));
      }
    } catch (e) {
      debugPrint('Error fetchMovements: $e');
    } finally {
      if (currentFetchId == _fetchId) {
        _isLoading = false;
        notifyListeners();
      }
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
        await fetchMovements(refresh: true);
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
        await fetchMovements(refresh: true);
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
