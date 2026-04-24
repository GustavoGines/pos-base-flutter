import '../../domain/repositories/check_repository.dart';
import '../../domain/entities/third_party_check.dart';
import '../datasources/check_remote_datasource.dart';

class CheckRepositoryImpl implements CheckRepository {
  final CheckRemoteDataSource remoteDataSource;

  CheckRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<ThirdPartyCheck>> getThirdPartyChecks() async {
    final data = await remoteDataSource.fetchThirdPartyChecks();
    return data.map((json) => ThirdPartyCheck.fromJson(json)).toList();
  }

  @override
  Future<ThirdPartyCheck> updateCheckStatus(int checkId, String status, {String? endorsementNote}) async {
    final data = await remoteDataSource.updateCheckStatus(checkId, status, endorsementNote: endorsementNote);
    return ThirdPartyCheck.fromJson(data['check']);
  }
}
