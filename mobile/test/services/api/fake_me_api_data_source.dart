import 'package:mobile/services/api/me_api_data_source.dart';

class FakeMeApiDataSource implements MeApiDataSource {
  BackendMeResult result = const BackendMeSuccess({});
  int callCount = 0;

  @override
  Future<BackendMeResult> fetchMe(String accessToken) async {
    callCount++;
    return result;
  }
}
