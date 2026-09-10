import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/message_template_api_data_source.dart';
import '../../data/message_template_repository_impl.dart';
import '../../domain/entities/message_template_list_state.dart';
import '../../domain/repositories/message_template_repository.dart';
import '../../domain/whatsapp_message_service.dart';
import '../controllers/message_template_list_controller.dart';

final messageTemplateApiDataSourceProvider = Provider<MessageTemplateApiDataSource>((ref) => DioMessageTemplateApiDataSource());

final messageTemplateRepositoryProvider = Provider<MessageTemplateRepository>((ref) {
  return MessageTemplateRepositoryImpl(ref.watch(messageTemplateApiDataSourceProvider));
});

final messageTemplateListControllerProvider =
    StateNotifierProvider.autoDispose<MessageTemplateListController, MessageTemplateListState>((ref) {
  return MessageTemplateListController(ref.watch(messageTemplateRepositoryProvider), ref);
});

/// Stateless, no request-scoped dependencies — a fresh instance is
/// cheap and never needs disposing/invalidating with the rest of the
/// session the way a StateNotifier would.
final whatsAppMessageServiceProvider = Provider<WhatsAppMessageService>((ref) => WhatsAppMessageService());
