import '../datasources/users_remote_datasource.dart';

class UsersRepository {
  final UsersRemoteDataSource dataSource;
  UsersRepository({required this.dataSource});

  Future<List<Map<String, dynamic>>> getAll() => dataSource.getAll();
  Future<Map<String, dynamic>> create(Map<String, dynamic> data) => dataSource.create(data);
  Future<Map<String, dynamic>> update(int id, Map<String, dynamic> data) => dataSource.update(id, data);
  Future<void> delete(int id, int currentUserId) => dataSource.delete(id, currentUserId);
}
