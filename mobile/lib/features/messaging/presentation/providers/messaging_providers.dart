import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/api/messaging_api_data_source.dart';
import '../../data/messaging_repository_impl.dart';
import '../../domain/entities/conversation_list_state.dart';
import '../../domain/entities/message_list_state.dart';
import '../../domain/repositories/messaging_repository.dart';
import '../controllers/conversation_list_controller.dart';
import '../controllers/message_list_controller.dart';

final messagingApiDataSourceProvider = Provider<MessagingApiDataSource>((ref) => DioMessagingApiDataSource());

final messagingRepositoryProvider = Provider<MessagingRepository>((ref) {
  return MessagingRepositoryImpl(ref.watch(messagingApiDataSourceProvider));
});

final conversationListControllerProvider = StateNotifierProvider.autoDispose<ConversationListController, ConversationListState>((ref) {
  return ConversationListController(ref.watch(messagingRepositoryProvider), ref);
});

/// `.family` keyed by conversationId — a fresh controller (and load) per
/// conversation, same pattern as `callDetailControllerProvider`.
final messageListControllerProvider =
    StateNotifierProvider.autoDispose.family<MessageListController, MessageListState, String>((ref, conversationId) {
  return MessageListController(ref.watch(messagingRepositoryProvider), ref, conversationId);
});
