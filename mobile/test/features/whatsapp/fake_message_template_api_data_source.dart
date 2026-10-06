import 'package:mobile/services/api/message_template_api_data_source.dart';

class FakeMessageTemplateApiDataSource implements MessageTemplateApiDataSource {
  List<dynamic> listTemplatesResponse = const [];
  Map<String, dynamic> createTemplateResponse = const {};
  Map<String, dynamic> updateTemplateResponse = const {};
  Object? errorToThrow;

  Map<String, dynamic>? lastUpdateChanges;

  @override
  Future<List<dynamic>> listTemplates({required String accessToken, required String workspaceId}) async {
    if (errorToThrow != null) throw errorToThrow!;
    return listTemplatesResponse;
  }

  @override
  Future<Map<String, dynamic>> createTemplate({
    required String accessToken,
    required String workspaceId,
    required String name,
    required String body,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    return createTemplateResponse;
  }

  @override
  Future<Map<String, dynamic>> updateTemplate({
    required String accessToken,
    required String workspaceId,
    required String templateId,
    Map<String, dynamic>? changes,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    lastUpdateChanges = changes;
    return updateTemplateResponse;
  }

}
