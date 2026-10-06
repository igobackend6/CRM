import '../../../services/api/message_template_api_data_source.dart';
import '../domain/entities/message_template.dart';
import '../domain/repositories/message_template_repository.dart';

class MessageTemplateRepositoryImpl implements MessageTemplateRepository {
  MessageTemplateRepositoryImpl(this._dataSource);

  final MessageTemplateApiDataSource _dataSource;

  @override
  Future<List<MessageTemplate>> listTemplates({required String accessToken, required String workspaceId}) async {
    final list = await _dataSource.listTemplates(accessToken: accessToken, workspaceId: workspaceId);
    return list.cast<Map<String, dynamic>>().map(MessageTemplate.fromJson).toList();
  }

  @override
  Future<MessageTemplate> createTemplate({
    required String accessToken,
    required String workspaceId,
    required String name,
    required String body,
  }) async {
    final json = await _dataSource.createTemplate(accessToken: accessToken, workspaceId: workspaceId, name: name, body: body);
    return MessageTemplate.fromJson(json);
  }

  @override
  Future<MessageTemplate> updateTemplate({
    required String accessToken,
    required String workspaceId,
    required String templateId,
    String? name,
    String? body,
  }) async {
    final changes = <String, dynamic>{'name': ?name, 'body': ?body};
    final json = await _dataSource.updateTemplate(accessToken: accessToken, workspaceId: workspaceId, templateId: templateId, changes: changes);
    return MessageTemplate.fromJson(json);
  }

}
