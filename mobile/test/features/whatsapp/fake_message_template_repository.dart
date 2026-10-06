import 'package:mobile/features/whatsapp/domain/entities/message_template.dart';
import 'package:mobile/features/whatsapp/domain/repositories/message_template_repository.dart';

MessageTemplate testTemplate({String id = 't1', String name = 'Follow-up', String body = 'Hi {{name}}'}) => MessageTemplate(
      id: id,
      name: name,
      body: body,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class FakeMessageTemplateRepository implements MessageTemplateRepository {
  List<MessageTemplate> templatesToReturn = const [];
  Object? listError;

  MessageTemplate? createResult;
  Object? createError;
  String? lastCreatedName;
  String? lastCreatedBody;

  MessageTemplate? updateResult;
  Object? updateError;


  @override
  Future<List<MessageTemplate>> listTemplates({required String accessToken, required String workspaceId}) async {
    if (listError != null) throw listError!;
    return templatesToReturn;
  }

  @override
  Future<MessageTemplate> createTemplate({
    required String accessToken,
    required String workspaceId,
    required String name,
    required String body,
  }) async {
    if (createError != null) throw createError!;
    lastCreatedName = name;
    lastCreatedBody = body;
    return createResult ?? testTemplate(name: name, body: body);
  }

  @override
  Future<MessageTemplate> updateTemplate({
    required String accessToken,
    required String workspaceId,
    required String templateId,
    String? name,
    String? body,
  }) async {
    if (updateError != null) throw updateError!;
    return updateResult ?? testTemplate(id: templateId, name: name ?? 'Follow-up', body: body ?? 'Hi {{name}}');
  }

}
