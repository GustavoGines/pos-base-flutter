import '../../data/datasources/auth_remote_datasource.dart';

class AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepository({required this.remoteDataSource});

  Future<Map<String, dynamic>> verifyPin(String pin) async {
    return await remoteDataSource.verifyPin(pin);
  }
}
