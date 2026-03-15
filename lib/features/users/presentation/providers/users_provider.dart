import 'package:flutter/material.dart';
import '../../data/repositories/users_repository.dart';

class UsersProvider with ChangeNotifier {
  final UsersRepository repository;

  UsersProvider({required this.repository});

  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> get users => _users;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadUsers() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _users = await repository.getAll();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> createUser(Map<String, dynamic> data) async {
    try {
      final newUser = await repository.create(data);
      _users.add(newUser);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateUser(int id, Map<String, dynamic> data) async {
    try {
      final updated = await repository.update(id, data);
      final idx = _users.indexWhere((u) => u['id'] == id);
      if (idx >= 0) _users[idx] = updated;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteUser(int id, int currentUserId) async {
    try {
      await repository.delete(id, currentUserId);
      _users.removeWhere((u) => u['id'] == id);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }
}
