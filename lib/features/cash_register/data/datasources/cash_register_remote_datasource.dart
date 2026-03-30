import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/cash_register_shift_model.dart';

abstract class CashRegisterRemoteDataSource {
  Future<CashRegisterShiftModel?> getCurrentShift({int? registerId});
  Future<List<CashRegisterShiftModel>> getAllShifts();
  Future<CashRegisterShiftModel> openShift(double openingBalance, int userId, [int? registerId]);
  Future<CashRegisterShiftModel> closeShift(int shiftId, double countedCash, {int? closerUserId});
  Future<List<dynamic>> getRegisters();
}

class CashRegisterRemoteDataSourceImpl implements CashRegisterRemoteDataSource {
  final String baseUrl;
  final http.Client client;

  CashRegisterRemoteDataSourceImpl({required this.baseUrl, required this.client});

  @override
  Future<CashRegisterShiftModel?> getCurrentShift({int? registerId}) async {
    try {
      final uri = registerId != null
          ? Uri.parse('$baseUrl/shifts/current?cash_register_id=$registerId')
          : Uri.parse('$baseUrl/shifts/current');
      final response = await client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final jsonMap = json.decode(response.body);
        return CashRegisterShiftModel.fromJson(jsonMap);
      } else if (response.statusCode == 404) {
        return null;
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
        Uri.parse('$baseUrl/shifts'),
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
  Future<CashRegisterShiftModel> openShift(double openingBalance, int userId, [int? registerId]) async {
    try {
      final body = <String, dynamic>{
        'opening_balance': openingBalance,
        'user_id': userId,
      };
      
      if (registerId != null) {
        body['cash_register_id'] = registerId;
      }

      final response = await client.post(
        Uri.parse('$baseUrl/shifts/open'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return CashRegisterShiftModel.fromJson(json.decode(response.body)['shift']);
      } else {
        final errorMsg = json.decode(response.body)['message'] ?? 'Failed to open shift';
        throw Exception(errorMsg);
      }
    } catch (e) {
      print('=== API Error en openShift: $e ===');
      rethrow;
    }
  }

  @override
  Future<CashRegisterShiftModel> closeShift(int shiftId, double countedCash, {int? closerUserId}) async {
    try {
      final body = <String, dynamic>{'actual_balance': countedCash};
      if (closerUserId != null) body['closer_user_id'] = closerUserId;

      final response = await client.post(
        Uri.parse('$baseUrl/shifts/$shiftId/close'),
        headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return CashRegisterShiftModel.fromJson(json.decode(response.body)['shift']);
      } else {
        throw Exception(
            json.decode(response.body)['message'] ?? 'Failed to close shift (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en closeShift: $e ===');
      rethrow;
    }
  }

  @override
  Future<List<dynamic>> getRegisters() async {
    try {
      final response = await client.get(
        Uri.parse('$baseUrl/registers'),
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load registers (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('=== API Error en getRegisters: $e ===');
      rethrow;
    }
  }
}
