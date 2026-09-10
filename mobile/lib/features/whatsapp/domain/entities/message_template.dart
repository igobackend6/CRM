/// Mirrors the backend's `MessageTemplateOut` (backend/app/schemas/message_templates.py)
/// — a reusable, workspace-scoped WhatsApp/CRM message body with
/// `{{variable}}` placeholders (see message_template_renderer.dart).
class MessageTemplate {
  const MessageTemplate({required this.id, required this.name, required this.body, required this.createdAt, required this.updatedAt});

  factory MessageTemplate.fromJson(Map<String, dynamic> json) => MessageTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        body: json['body'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final String name;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;
}
