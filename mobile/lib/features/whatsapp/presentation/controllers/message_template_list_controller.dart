import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../domain/entities/message_template_list_state.dart';
import '../../domain/repositories/message_template_repository.dart';

/// One instance per workspace (implicitly — see providers.dart: not a
/// `.family`, since templates are workspace-wide, not per-lead).
class MessageTemplateListController extends StateNotifier<MessageTemplateListState> {
  MessageTemplateListController(this._repository, this._ref) : super(const MessageTemplateListState.initial());

  final MessageTemplateRepository _repository;
  final Ref _ref;

  Future<void> refresh() async {
    final context = resolveLeadContext(_ref.read);
    if (context == null) return;

    state = state.copyWith(status: MessageTemplateListStatus.loading, clearError: true);
    try {
      final items = await _repository.listTemplates(accessToken: context.accessToken, workspaceId: context.workspaceId);
      state = state.copyWith(status: items.isEmpty ? MessageTemplateListStatus.empty : MessageTemplateListStatus.success, items: items);
    } on AppException catch (e) {
      state = state.copyWith(status: MessageTemplateListStatus.error, errorMessage: e.message);
    } catch (e) {
      AppLogger.error('Failed to load message templates', error: e);
      state = state.copyWith(status: MessageTemplateListStatus.error, errorMessage: 'Could not load templates.');
    }
  }

  Future<bool> createTemplate({required String name, required String body}) => _mutate(() async {
        final context = resolveLeadContext(_ref.read)!;
        final created = await _repository.createTemplate(accessToken: context.accessToken, workspaceId: context.workspaceId, name: name, body: body);
        state = state.copyWith(status: MessageTemplateListStatus.success, items: [...state.items, created]);
      });

  Future<bool> updateTemplate(String templateId, {String? name, String? body}) => _mutate(() async {
        final context = resolveLeadContext(_ref.read)!;
        final updated = await _repository.updateTemplate(
          accessToken: context.accessToken,
          workspaceId: context.workspaceId,
          templateId: templateId,
          name: name,
          body: body,
        );
        state = state.copyWith(items: [for (final t in state.items) if (t.id == templateId) updated else t]);
      });

  Future<bool> _mutate(Future<void> Function() action) async {
    if (resolveLeadContext(_ref.read) == null) return false;
    state = state.copyWith(saving: true, clearError: true);
    try {
      await action();
      state = state.copyWith(saving: false);
      return true;
    } on AppException catch (e) {
      state = state.copyWith(saving: false, errorMessage: e.message);
      return false;
    } catch (e) {
      AppLogger.error('Failed to save a message template', error: e);
      state = state.copyWith(saving: false, errorMessage: 'Could not save this template.');
      return false;
    }
  }
}
