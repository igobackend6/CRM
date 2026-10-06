import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/whatsapp/domain/entities/message_template_list_state.dart';
import 'package:mobile/features/whatsapp/presentation/providers/whatsapp_providers.dart';

import 'fake_message_template_repository.dart';
import 'whatsapp_test_container.dart';

void main() {
  group('MessageTemplateListController', () {
    test('refresh loads the template list', () async {
      final repo = FakeMessageTemplateRepository()..templatesToReturn = [testTemplate(id: 't1', name: 'Follow-up')];
      final container = await buildWhatsAppTestContainer(templateRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageTemplateListControllerProvider).close);

      await container.read(messageTemplateListControllerProvider.notifier).refresh();

      final state = container.read(messageTemplateListControllerProvider);
      expect(state.status, MessageTemplateListStatus.success);
      expect(state.items, hasLength(1));
    });

    test('an empty result is represented as the empty status', () async {
      final container = await buildWhatsAppTestContainer();
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageTemplateListControllerProvider).close);

      await container.read(messageTemplateListControllerProvider.notifier).refresh();

      expect(container.read(messageTemplateListControllerProvider).status, MessageTemplateListStatus.empty);
    });

    test('createTemplate appends the new template on success', () async {
      final repo = FakeMessageTemplateRepository();
      final container = await buildWhatsAppTestContainer(templateRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageTemplateListControllerProvider).close);

      final ok = await container
          .read(messageTemplateListControllerProvider.notifier)
          .createTemplate(name: 'Reminder', body: 'Hi {{name}}, following up.');

      expect(ok, isTrue);
      expect(repo.lastCreatedName, 'Reminder');
      expect(container.read(messageTemplateListControllerProvider).items, hasLength(1));
    });

    test('a duplicate-name conflict surfaces the server error message', () async {
      final repo = FakeMessageTemplateRepository()..createError = const ConflictException("A template named 'Reminder' already exists.");
      final container = await buildWhatsAppTestContainer(templateRepository: repo);
      addTearDown(container.dispose);
      addTearDown(keepAlive(container, messageTemplateListControllerProvider).close);

      final ok = await container.read(messageTemplateListControllerProvider.notifier).createTemplate(name: 'Reminder', body: 'Hi');

      expect(ok, isFalse);
      expect(container.read(messageTemplateListControllerProvider).errorMessage, contains('already exists'));
    });

  });
}
