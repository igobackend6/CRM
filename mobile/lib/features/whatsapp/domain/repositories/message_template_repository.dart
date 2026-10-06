import '../entities/message_template.dart';

abstract class MessageTemplateRepository {
  Future<List<MessageTemplate>> listTemplates({required String accessToken, required String workspaceId});

  Future<MessageTemplate> createTemplate({
    required String accessToken,
    required String workspaceId,
    required String name,
    required String body,
  });

  Future<MessageTemplate> updateTemplate({
    required String accessToken,
    required String workspaceId,
    required String templateId,
    String? name,
    String? body,
  });

}
