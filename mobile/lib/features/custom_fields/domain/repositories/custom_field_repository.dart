import '../entities/custom_field.dart';

abstract class CustomFieldRepository {
  Future<List<CustomField>> listFields({required String accessToken, required String workspaceId});
}
