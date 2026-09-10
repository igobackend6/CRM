import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/pipeline/data/pipeline_repository_impl.dart';

import 'fake_pipeline_api_data_source.dart';

Map<String, dynamic> _leadStatusJson({String id = 's1', String name = 'New', int sortOrder = 10}) => {
      'id': id,
      'name': name,
      'code': 'new',
      'sort_order': sortOrder,
      'stage': 'in_progress',
      'is_default': true,
    };

Map<String, dynamic> _cardJson({String id = 'lead-1', String name = 'Acme Corp'}) => {
      'id': id,
      'name': name,
      'phone': '+15551234567',
      'email': null,
      'priority': 'high',
      'status': _leadStatusJson(),
      'assigned_member': {'id': 'm1', 'full_name': 'Rep One'},
      'updated_at': '2026-01-01T00:00:00Z',
    };

Map<String, dynamic> _leadJson({String id = 'lead-1', String statusId = 's2'}) => {
      'id': id,
      'workspace_id': 'w1',
      'name': 'Acme Corp',
      'priority': 'medium',
      'status': _leadStatusJson(id: statusId, name: 'Won'),
      'is_customer': false,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

void main() {
  group('PipelineRepositoryImpl', () {
    test('getPipeline maps columns, cards, and totals', () async {
      final dataSource = FakePipelineApiDataSource()
        ..pipelineResponse = {
          'columns': [
            {
              'status': _leadStatusJson(),
              'leads': [_cardJson()],
              'total': 3,
            },
          ],
          'limit': 50,
          'offset': 0,
        };
      final repo = PipelineRepositoryImpl(dataSource);

      final columns = await repo.getPipeline(accessToken: 't', workspaceId: 'w1');

      expect(columns, hasLength(1));
      expect(columns.first.status.name, 'New');
      expect(columns.first.total, 3);
      expect(columns.first.leads.first.name, 'Acme Corp');
      expect(columns.first.leads.first.priority, 'high');
      expect(columns.first.leads.first.assignedMember?.fullName, 'Rep One');
      expect(columns.first.hasMore, true);
    });

    test('getPipeline forwards the search term', () async {
      final dataSource = FakePipelineApiDataSource();
      final repo = PipelineRepositoryImpl(dataSource);

      await repo.getPipeline(accessToken: 't', workspaceId: 'w1', search: 'acme');

      expect(dataSource.lastSearch, 'acme');
    });

    test('an empty columns list maps to an empty list', () async {
      final dataSource = FakePipelineApiDataSource();
      final repo = PipelineRepositoryImpl(dataSource);

      final columns = await repo.getPipeline(accessToken: 't', workspaceId: 'w1');

      expect(columns, isEmpty);
    });

    test('changeLeadStatus maps the returned lead and forwards ids', () async {
      final dataSource = FakePipelineApiDataSource()..changeStatusResponse = _leadJson(statusId: 's2');
      final repo = PipelineRepositoryImpl(dataSource);

      final lead = await repo.changeLeadStatus(accessToken: 't', workspaceId: 'w1', leadId: 'lead-1', statusId: 's2');

      expect(lead.status?.id, 's2');
      expect(dataSource.lastLeadId, 'lead-1');
      expect(dataSource.lastStatusId, 's2');
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakePipelineApiDataSource()..errorToThrow = const NetworkException('Could not reach the server.');
      final repo = PipelineRepositoryImpl(dataSource);

      expect(() => repo.getPipeline(accessToken: 't', workspaceId: 'w1'), throwsA(isA<NetworkException>()));
    });
  });
}
