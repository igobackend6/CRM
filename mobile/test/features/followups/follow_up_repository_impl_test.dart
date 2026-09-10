import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/followups/data/follow_up_repository_impl.dart';
import 'package:mobile/features/followups/domain/entities/follow_up_draft.dart';

import 'fake_follow_up_api_data_source.dart';

Map<String, dynamic> _followUpJson({String id = 'fu-1', String status = 'pending'}) => {
      'id': id,
      'workspace_id': 'w1',
      'lead': {'id': 'l1', 'name': 'Acme Corp'},
      'type': 'call',
      'due_at': '2026-02-01T09:00:00Z',
      'status': status,
      'notes': 'Confirm budget',
      'assigned_member': {'id': 'm1', 'full_name': 'Rep One'},
      'created_by_member': {'id': 'm1', 'full_name': 'Rep One'},
      'completed_at': null,
      'cancelled_at': null,
      'is_overdue': false,
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

void main() {
  group('FollowUpRepositoryImpl', () {
    test('listFollowUps maps items and total', () async {
      final dataSource = FakeFollowUpApiDataSource()
        ..listFollowUpsResponse = {
          'items': [_followUpJson()],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = FollowUpRepositoryImpl(dataSource);

      final page = await repo.listFollowUps(accessToken: 't', workspaceId: 'w1', offset: 0);

      expect(page.items, hasLength(1));
      expect(page.items.first.lead.name, 'Acme Corp');
      expect(page.total, 1);
    });

    test('getFollowUp maps a single follow-up', () async {
      final dataSource = FakeFollowUpApiDataSource()..getFollowUpResponse = _followUpJson(id: 'fu-2');
      final repo = FollowUpRepositoryImpl(dataSource);

      final followUp = await repo.getFollowUp(accessToken: 't', workspaceId: 'w1', followUpId: 'fu-2');

      expect(followUp.id, 'fu-2');
      expect(followUp.assignedMember?.fullName, 'Rep One');
      expect(followUp.notes, 'Confirm budget');
    });

    test('createFollowUp sends lead_id plus the draft as the request body', () async {
      final dataSource = FakeFollowUpApiDataSource()..createFollowUpResponse = _followUpJson();
      final repo = FollowUpRepositoryImpl(dataSource);

      await repo.createFollowUp(
        accessToken: 't',
        workspaceId: 'w1',
        leadId: 'l1',
        draft: FollowUpDraft(dueAt: DateTime.utc(2026, 2, 1, 9), type: 'call', notes: 'Confirm budget'),
      );

      expect(dataSource.lastCreateBody?['lead_id'], 'l1');
      expect(dataSource.lastCreateBody?['type'], 'call');
      expect(dataSource.lastCreateBody?['notes'], 'Confirm budget');
      // Never sends created_by_member_id — see FollowUpDraft's docstring.
      expect(dataSource.lastCreateBody?.containsKey('created_by_member_id'), isFalse);
    });

    test('updateFollowUp sends the draft and maps the response', () async {
      final dataSource = FakeFollowUpApiDataSource()..updateFollowUpResponse = _followUpJson(status: 'completed');
      final repo = FollowUpRepositoryImpl(dataSource);

      final followUp = await repo.updateFollowUp(
        accessToken: 't',
        workspaceId: 'w1',
        followUpId: 'fu-1',
        draft: FollowUpDraft(dueAt: DateTime.utc(2026, 2, 1, 9), type: 'call', status: 'completed'),
      );

      expect(dataSource.lastUpdateFollowUpId, 'fu-1');
      expect(dataSource.lastUpdateBody?['status'], 'completed');
      expect(followUp.status, 'completed');
    });

    test('updateFollowUpStatus sends only the status field', () async {
      final dataSource = FakeFollowUpApiDataSource()..updateFollowUpResponse = _followUpJson(status: 'cancelled');
      final repo = FollowUpRepositoryImpl(dataSource);

      await repo.updateFollowUpStatus(accessToken: 't', workspaceId: 'w1', followUpId: 'fu-1', status: 'cancelled');

      expect(dataSource.lastUpdateBody, {'status': 'cancelled'});
    });

    test('listLeadFollowUps maps the lead-scoped list', () async {
      final dataSource = FakeFollowUpApiDataSource()..leadFollowUpsResponse = [_followUpJson()];
      final repo = FollowUpRepositoryImpl(dataSource);

      final followUps = await repo.listLeadFollowUps(accessToken: 't', workspaceId: 'w1', leadId: 'l1');

      expect(followUps, hasLength(1));
      expect(dataSource.lastLeadId, 'l1');
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeFollowUpApiDataSource()..errorToThrow = const NotFoundException('Follow-up not found.');
      final repo = FollowUpRepositoryImpl(dataSource);

      expect(
        () => repo.getFollowUp(accessToken: 't', workspaceId: 'w1', followUpId: 'missing'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
