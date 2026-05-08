import '../../data/datasources/auth_remote_datasource.dart';

class AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepository({required this.remoteDataSource});

  /// Login completo: devuelve { user: {...}, session_token: "..." }
  Future<Map<String, dynamic>> verifyPin(String pin) async {
    return await remoteDataSource.verifyPin(pin);
  }

  /// Autorización puntual (AdminPinDialog): devuelve el user sin tocar tokens.
  Future<Map<String, dynamic>> authorizePin(String pin) async {
    return await remoteDataSource.authorizePin(pin);
  }

  /// Logout: nullifica el token en BD.
  Future<void> logout(String sessionToken) async {
    return await remoteDataSource.logout(sessionToken);
  }

  /// Valida el token restaurado desde disco contra el servidor.
  /// Retorna el Map del usuario si el token sigue siendo válido, null si fue invalidado.
  /// Lanza excepción solo en caso de error de red (para modo offline).
  Future<Map<String, dynamic>?> validateToken(String sessionToken) async {
    return await remoteDataSource.validateToken(sessionToken);
  }
}
