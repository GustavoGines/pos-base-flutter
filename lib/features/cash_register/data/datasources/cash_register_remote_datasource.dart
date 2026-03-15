import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cash_register_shift_model.dart';

abstract class CashRegisterRemoteDataSource {
  Future<CashRegisterShiftModel?> getCurrentShift();
  Future<List<CashRegisterShiftModel>> getAllShifts();
  Future<CashRegisterShiftModel> openShift(double openingBalance, int userId);
  Future<CashRegisterShiftModel> closeShift(double countedCash);
}

class CashRegisterRemoteDataSourceImpl implements CashRegisterRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  CashRegisterRemoteDataSourceImpl({required this.baseUrl, required this.client});

  @override
  Future<CashRegisterShiftModel?> getCurrentShift() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/cash-register/current'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        if (response.body.trim().isEmpty || response.body == 'null' || response.body == '{}') {
           return null;
        }
        final jsonMap = json.decode(response.body);
        if (jsonMap.isEmpty) return null;
        return CashRegisterShiftModel.fromJson(jsonMap);
      } else {
        throw Exception('Failed to load current shift (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en getCurrentShift: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<CashRegisterShiftModel>> getAllShifts() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/cash-register/shifts'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> jsonResponse = json.decode(response.body);
        final List<dynamic> data = jsonResponse['data'] ?? [];
        return data.map((e) => CashRegisterShiftModel.fromJson(e)).toList();
      } else {
        throw Exception('Failed to load shifts history (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en getAllShifts: $e ===');
      rethrow;
    }
  }

  @override
  Future<CashRegisterShiftModel> openShift(double openingBalance, int userId) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/cash-register/open'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'opening_balance': openingBalance, 'user_id': userId}),
      );

      if (response.statusCode == 201) {
        return CashRegisterShiftModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to open shift (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en openShift: $e ===');
      rethrow;
    }
  }

  @override
  Future<CashRegisterShiftModel> closeShift(double countedCash) async {
    try {
      final response = await client.post(
        Uri.parse('$baseUrl/cash-register/close'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode({'counted_cash': countedCash}),
      );

      if (response.statusCode == 200) {
        return CashRegisterShiftModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to close shift (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en closeShift: $e ===');
      rethrow;
    }
  }
}
