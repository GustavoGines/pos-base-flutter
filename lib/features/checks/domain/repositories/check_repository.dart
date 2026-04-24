import '../entities/third_party_check.dart';

abstract class CheckRepository {
  Future<List<ThirdPartyCheck>> getThirdPartyChecks();
  Future<ThirdPartyCheck> updateCheckStatus(int checkId, String status, {String? endorsementNote});
}
