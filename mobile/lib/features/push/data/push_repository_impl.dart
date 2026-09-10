import '../../../../services/api/device_token_api_data_source.dart';
import '../domain/repositories/push_repository.dart';

class PushRepositoryImpl implements PushRepository {
  PushRepositoryImpl(this._dataSource);

  final DeviceTokenApiDataSource _dataSource;

  @override
  Future<void> registerToken({required String accessToken, required String token, required String platform}) =>
      _dataSource.register(accessToken: accessToken, token: token, platform: platform);

  @override
  Future<void> deregisterToken({required String accessToken, required String token}) =>
      _dataSource.deregister(accessToken: accessToken, token: token);
}
