import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/messaging/data/messaging_repository_impl.dart';

import 'fake_messaging_api_data_source.dart';

Map<String, dynamic> _conversationJson({String id = 'conv-1', int unreadCount = 0}) => {
      'id': id,
      'workspace_id': 'w1',
      'lead': {'id': 'l1', 'name': 'Acme Corp'},
      'latest_message_preview': 'See you then',
      'latest_message_at': '2026-01-01T09:00:00Z',
      'unread_count': unreadCount,
      'created_at': '2026-01-01T08:00:00Z',
      'updated_at': '2026-01-01T09:00:00Z',
    };

Map<String, dynamic> _messageJson({String id = 'msg-1', String body = 'Hello there'}) => {
      'id': id,
      'workspace_id': 'w1',
      'conversation_id': 'conv-1',
      'sender_member': {'id': 'm1', 'full_name': 'Agent One'},
      'body': body,
      'created_at': '2026-01-01T09:00:00Z',
      'read_at': null,
    };

void main() {
  group('MessagingRepositoryImpl', () {
    test('listConversations maps items and total', () async {
      final dataSource = FakeMessagingApiDataSource()
        ..listConversationsResponse = {
          'items': [_conversationJson(unreadCount: 2)],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = MessagingRepositoryImpl(dataSource);

      final page = await repo.listConversations(accessToken: 't', workspaceId: 'w1');

      expect(page.items, hasLength(1));
      expect(page.items.first.lead.name, 'Acme Corp');
      expect(page.items.first.unreadCount, 2);
      expect(page.total, 1);
    });

    test('getOrCreateConversation maps a single conversation', () async {
      final dataSource = FakeMessagingApiDataSource()..getOrCreateConversationResponse = _conversationJson(id: 'conv-9');
      final repo = MessagingRepositoryImpl(dataSource);

      final conversation = await repo.getOrCreateConversation(accessToken: 't', workspaceId: 'w1', leadId: 'l1');

      expect(conversation.id, 'conv-9');
      expect(dataSource.lastLeadId, 'l1');
    });

    test('listMessages maps items and total', () async {
      final dataSource = FakeMessagingApiDataSource()
        ..listMessagesResponse = {
          'items': [_messageJson()],
          'total': 1,
          'limit': 30,
          'offset': 0,
        };
      final repo = MessagingRepositoryImpl(dataSource);

      final page = await repo.listMessages(accessToken: 't', workspaceId: 'w1', conversationId: 'conv-1');

      expect(page.items, hasLength(1));
      expect(page.items.first.senderMember.fullName, 'Agent One');
      expect(dataSource.lastConversationId, 'conv-1');
    });

    test('sendMessage sends the body and maps the created message', () async {
      final dataSource = FakeMessagingApiDataSource()..sendMessageResponse = _messageJson(body: 'Hi!');
      final repo = MessagingRepositoryImpl(dataSource);

      final message = await repo.sendMessage(accessToken: 't', workspaceId: 'w1', conversationId: 'conv-1', body: 'Hi!');

      expect(message.body, 'Hi!');
      expect(dataSource.lastSentBody, 'Hi!');
      expect(dataSource.lastConversationId, 'conv-1');
    });

    test('markConversationRead calls through to the data source', () async {
      final dataSource = FakeMessagingApiDataSource();
      final repo = MessagingRepositoryImpl(dataSource);

      await repo.markConversationRead(accessToken: 't', workspaceId: 'w1', conversationId: 'conv-1');

      expect(dataSource.markReadCalled, isTrue);
      expect(dataSource.lastConversationId, 'conv-1');
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeMessagingApiDataSource()..errorToThrow = const ValidationException('Message is too long.');
      final repo = MessagingRepositoryImpl(dataSource);

      expect(
        () => repo.sendMessage(accessToken: 't', workspaceId: 'w1', conversationId: 'conv-1', body: 'x' * 5000),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}
