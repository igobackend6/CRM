import '../../../services/api/custom_field_api_data_source.dart';
import '../domain/entities/custom_field.dart';
import '../domain/repositories/custom_field_repository.dart';

class CustomFieldRepositoryImpl implements CustomFieldRepository {
  CustomFieldRepositoryImpl(this._dataSource);

  final CustomFieldApiDataSource _dataSource;

  @override
  Future<List<CustomField>> listFields({required String accessToken, required String workspaceId}) async {
    final rows = await _dataSource.listFields(accessToken: accessToken, workspaceId: workspaceId);
    return rows
        .cast<Map<String, dynamic>>()
        .map(CustomField.fromJson)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
}
