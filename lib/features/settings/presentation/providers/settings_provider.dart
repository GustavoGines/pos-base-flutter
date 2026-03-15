import 'package:flutter/material.dart';
import '../../domain/entities/business_settings.dart';
import '../../domain/usecases/get_settings_usecase.dart';

class SettingsProvider with ChangeNotifier {
  final GetSettingsUseCase getSettingsUseCase;

  BusinessSettings? _settings;
  BusinessSettings? get settings => _settings;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  SettingsProvider({required this.getSettingsUseCase});

  Future<void> loadSettings() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _settings = await getSettingsUseCase();
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
