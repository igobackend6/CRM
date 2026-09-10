import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/calls/data/call_repository_impl.dart';
import 'package:mobile/features/calls/domain/entities/call_draft.dart';

import 'fake_call_api_data_source.dart';

Map<String, dynamic> _callJson({String id = 'call-1', String direction = 'outbound', int? durationSeconds}) => {
      'id': id,
      'workspace_id': 'w1',
      'lead': {'id': 'l1', 'name': 'Acme Corp'},
      'agent_member': {'id': 'm1', 'full_name': 'Agent One'},
      'direction': direction,
      'state': 'ENDED',
      'outcome': {'id': 'oc-1', 'name': 'Connected', 'code': 'connected', 'is_positive': true, 'is_default': false},
      'started_at': '2026-01-01T09:00:00Z',
      'connected_at': durationSeconds != null ? '2026-01-01T09:00:00Z' : null,
      'ended_at': durationSeconds != null ? '2026-01-01T09:01:30Z' : null,
      'duration_seconds': durationSeconds,
      'notes': 'Discussed pricing',
      'created_at': '2026-01-01T09:02:00Z',
    };

void main() {
  group('CallRepositoryImpl', () {
    test('listCalls maps items and total', () async {
      final dataSource = FakeCallApiDataSource()
        ..listCallsResponse = {
          'items': [_callJson()],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = CallRepositoryImpl(dataSource);

      final page = await repo.listCalls(accessToken: 't', workspaceId: 'w1', offset: 0);

      expect(page.items, hasLength(1));
      expect(page.items.first.lead.name, 'Acme Corp');
      expect(page.total, 1);
    });

    test('getCall maps a single call, including duration and outcome', () async {
      final dataSource = FakeCallApiDataSource()..getCallResponse = _callJson(id: 'call-2', durationSeconds: 90);
      final repo = CallRepositoryImpl(dataSource);

      final call = await repo.getCall(accessToken: 't', workspaceId: 'w1', callId: 'call-2');

      expect(call.id, 'call-2');
      expect(call.durationSeconds, 90);
      expect(call.outcome?.name, 'Connected');
      expect(call.agentMember?.fullName, 'Agent One');
    });

    test('createCall sends lead_id plus the draft as the request body', () async {
      final dataSource = FakeCallApiDataSource()..createCallResponse = _callJson();
      final repo = CallRepositoryImpl(dataSource);

      await repo.createCall(
        accessToken: 't',
        workspaceId: 'w1',
        leadId: 'l1',
        draft: const CallDraft(direction: 'outbound', notes: 'Discussed pricing', durationSeconds: 90),
      );

      expect(dataSource.lastCreateBody?['lead_id'], 'l1');
      expect(dataSource.lastCreateBody?['direction'], 'outbound');
      expect(dataSource.lastCreateBody?['duration_seconds'], 90);
      // Never sends workspace_id/agent_member_id/state — see CallDraft's docstring.
      expect(dataSource.lastCreateBody?.containsKey('agent_member_id'), isFalse);
      expect(dataSource.lastCreateBody?.containsKey('workspace_id'), isFalse);
      expect(dataSource.lastCreateBody?.containsKey('state'), isFalse);
    });

    test('listLeadCalls maps the lead-scoped list', () async {
      final dataSource = FakeCallApiDataSource()..leadCallsResponse = [_callJson()];
      final repo = CallRepositoryImpl(dataSource);

      final calls = await repo.listLeadCalls(accessToken: 't', workspaceId: 'w1', leadId: 'l1');

      expect(calls, hasLength(1));
      expect(dataSource.lastLeadId, 'l1');
    });

    test('listCallOutcomes maps the outcome catalogue', () async {
      final dataSource = FakeCallApiDataSource()
        ..callOutcomesResponse = [
          {'id': 'oc-1', 'name': 'Connected', 'code': 'connected', 'is_positive': true, 'is_default': false},
        ];
      final repo = CallRepositoryImpl(dataSource);

      final outcomes = await repo.listCallOutcomes(accessToken: 't', workspaceId: 'w1');

      expect(outcomes, hasLength(1));
      expect(outcomes.first.code, 'connected');
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeCallApiDataSource()..errorToThrow = const NotFoundException('Call not found.');
      final repo = CallRepositoryImpl(dataSource);

      expect(
        () => repo.getCall(accessToken: 't', workspaceId: 'w1', callId: 'missing'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
