import 'package:flutter/material.dart';
import '../../domain/repositories/check_repository.dart';
import '../../domain/entities/third_party_check.dart';

class CheckProvider with ChangeNotifier {
  final CheckRepository repository;

  CheckProvider({required this.repository});

  List<ThirdPartyCheck> _checks = [];
  List<ThirdPartyCheck> get checks => _checks;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Future<void> loadChecks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _checks = await repository.getThirdPartyChecks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateCheckStatus(int checkId, String status, {String? endorsementNote}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedCheck = await repository.updateCheckStatus(checkId, status, endorsementNote: endorsementNote);
      final index = _checks.indexWhere((c) => c.id == checkId);
      if (index != -1) {
        _checks[index] = updatedCheck;
      }
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
