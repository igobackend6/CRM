import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/whatsapp/data/message_template_repository_impl.dart';

import 'fake_message_template_api_data_source.dart';

void main() {
  group('MessageTemplateRepositoryImpl', () {
    test('listTemplates maps the raw JSON list', () async {
      final dataSource = FakeMessageTemplateApiDataSource()
        ..listTemplatesResponse = [
          {
            'id': 't1',
            'name': 'Follow-up',
            'body': 'Hi {{name}}',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
        ];
      final repo = MessageTemplateRepositoryImpl(dataSource);

      final templates = await repo.listTemplates(accessToken: 't', workspaceId: 'w1');

      expect(templates, hasLength(1));
      expect(templates.first.name, 'Follow-up');
    });

    test('createTemplate maps the created row', () async {
      final dataSource = FakeMessageTemplateApiDataSource()
        ..createTemplateResponse = {
          'id': 't1',
          'name': 'Reminder',
          'body': 'Hi {{name}}, following up.',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        };
      final repo = MessageTemplateRepositoryImpl(dataSource);

      final template = await repo.createTemplate(accessToken: 't', workspaceId: 'w1', name: 'Reminder', body: 'Hi {{name}}, following up.');

      expect(template.name, 'Reminder');
    });

    test('updateTemplate only sends the fields that changed', () async {
      final dataSource = FakeMessageTemplateApiDataSource()
        ..updateTemplateResponse = {
          'id': 't1',
          'name': 'Renamed',
          'body': 'Hi {{name}}',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        };
      final repo = MessageTemplateRepositoryImpl(dataSource);

      await repo.updateTemplate(accessToken: 't', workspaceId: 'w1', templateId: 't1', name: 'Renamed');

      expect(dataSource.lastUpdateChanges, {'name': 'Renamed'});
    });

    test('deleteTemplate forwards the template id', () async {
      final dataSource = FakeMessageTemplateApiDataSource();
      final repo = MessageTemplateRepositoryImpl(dataSource);

      await repo.deleteTemplate(accessToken: 't', workspaceId: 'w1', templateId: 't1');

      expect(dataSource.lastDeletedTemplateId, 't1');
    });
  });
}
