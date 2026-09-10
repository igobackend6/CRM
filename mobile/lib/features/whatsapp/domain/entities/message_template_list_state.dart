import 'message_template.dart';

enum MessageTemplateListStatus { initial, loading, success, empty, error }

/// Workspace-scoped, unpaginated (§7 "Do not create a generic CMS" —
/// a workspace's own template list is expected to be small).
class MessageTemplateListState {
  const MessageTemplateListState._({required this.status, this.items = const [], this.errorMessage, this.saving = false});

  const MessageTemplateListState.initial() : this._(status: MessageTemplateListStatus.initial);

  final MessageTemplateListStatus status;
  final List<MessageTemplate> items;
  final String? errorMessage;
  final bool saving;

  MessageTemplateListState copyWith({
    MessageTemplateListStatus? status,
    List<MessageTemplate>? items,
    String? errorMessage,
    bool clearError = false,
    bool? saving,
  }) {
    return MessageTemplateListState._(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      saving: saving ?? this.saving,
    );
  }
}
