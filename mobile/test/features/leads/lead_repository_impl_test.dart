import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/leads/data/lead_repository_impl.dart';
import 'package:mobile/features/leads/domain/entities/lead_bulk_action.dart';
import 'package:mobile/features/leads/domain/entities/lead_draft.dart';

import 'fake_lead_api_data_source.dart';

Map<String, dynamic> _leadJson({String id = 'lead-1', String name = 'Acme Corp'}) => {
      'id': id,
      'workspace_id': 'w1',
      'name': name,
      'phone': '+15551234567',
      'email': 'acme@example.com',
      'priority': 'medium',
      'status': {'id': 's1', 'name': 'New', 'code': 'new', 'sort_order': 10, 'stage': 'in_progress', 'is_default': true},
      'source': {'id': 'src1', 'name': 'Website', 'code': 'website', 'is_default': false},
      'assigned_member': {'id': 'm1', 'full_name': 'Rep One'},
      'created_by_member': {'id': 'm1', 'full_name': 'Rep One'},
      'is_customer': false,
      'tags': <dynamic>[],
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

void main() {
  group('LeadRepositoryImpl', () {
    test('listLeads maps items and forwards the search term/offset', () async {
      final dataSource = FakeLeadApiDataSource()
        ..listLeadsResponse = {
          'items': [_leadJson()],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = LeadRepositoryImpl(dataSource);

      final page = await repo.listLeads(accessToken: 't', workspaceId: 'w1', search: 'acme', offset: 0);

      expect(page.items, hasLength(1));
      expect(page.items.first.name, 'Acme Corp');
      expect(page.total, 1);
      expect(dataSource.lastSearch, 'acme');
    });

    test('listLeads forwards every Phase 14 filter to the data source', () async {
      final dataSource = FakeLeadApiDataSource();
      final repo = LeadRepositoryImpl(dataSource);
      final from = DateTime.utc(2026, 1, 1);
      final to = DateTime.utc(2026, 12, 31);

      await repo.listLeads(
        accessToken: 't',
        workspaceId: 'w1',
        statusId: 's1',
        sourceId: 'src1',
        assignedMemberId: 'm2',
        priority: 'urgent',
        isCustomer: true,
        createdFrom: from,
        createdTo: to,
        tagId: 'tag1',
      );

      expect(dataSource.lastStatusId, 's1');
      expect(dataSource.lastSourceId, 'src1');
      expect(dataSource.lastFilterAssignedMemberId, 'm2');
      expect(dataSource.lastPriority, 'urgent');
      expect(dataSource.lastIsCustomer, isTrue);
      expect(dataSource.lastCreatedFrom, from);
      expect(dataSource.lastCreatedTo, to);
      expect(dataSource.lastTagId, 'tag1');
    });

    test('getLead maps a single lead', () async {
      final dataSource = FakeLeadApiDataSource()..getLeadResponse = _leadJson(id: 'lead-2', name: 'Globex');
      final repo = LeadRepositoryImpl(dataSource);

      final lead = await repo.getLead(accessToken: 't', workspaceId: 'w1', leadId: 'lead-2');

      expect(lead.id, 'lead-2');
      expect(lead.name, 'Globex');
      expect(lead.status?.name, 'New');
      expect(lead.assignedMember?.fullName, 'Rep One');
    });

    test('createLead sends the draft as the request body', () async {
      final dataSource = FakeLeadApiDataSource()..createLeadResponse = _leadJson();
      final repo = LeadRepositoryImpl(dataSource);

      await repo.createLead(
        accessToken: 't',
        workspaceId: 'w1',
        draft: const LeadDraft(name: 'Acme Corp', phone: '+15551234567', priority: 'high'),
      );

      expect(dataSource.lastCreateBody?['name'], 'Acme Corp');
      expect(dataSource.lastCreateBody?['priority'], 'high');
      // Never sends an owner/assignment field — see LeadDraft's docstring.
      expect(dataSource.lastCreateBody?.containsKey('assigned_member_id'), isFalse);
    });

    test('updateLead sends the draft and maps the response', () async {
      final dataSource = FakeLeadApiDataSource()..updateLeadResponse = _leadJson(name: 'Renamed Co');
      final repo = LeadRepositoryImpl(dataSource);

      final lead = await repo.updateLead(
        accessToken: 't',
        workspaceId: 'w1',
        leadId: 'lead-1',
        draft: const LeadDraft(name: 'Renamed Co'),
      );

      expect(dataSource.lastUpdateBody?['name'], 'Renamed Co');
      expect(lead.name, 'Renamed Co');
    });

    test('convertLead calls the data source and maps the returned (now-customer) lead', () async {
      final dataSource = FakeLeadApiDataSource()
        ..convertLeadResponse = _leadJson()
        ..convertLeadResponse['is_customer'] = true;
      final repo = LeadRepositoryImpl(dataSource);

      final lead = await repo.convertLead(accessToken: 't', workspaceId: 'w1', leadId: 'lead-1');

      expect(dataSource.lastConvertCalled, isTrue);
      expect(lead.id, 'lead-1');
      expect(lead.isCustomer, isTrue);
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeLeadApiDataSource()..errorToThrow = const NotFoundException('Lead not found.');
      final repo = LeadRepositoryImpl(dataSource);

      expect(
        () => repo.getLead(accessToken: 't', workspaceId: 'w1', leadId: 'missing'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('listWorkspaceMembers maps the member list', () async {
      final dataSource = FakeLeadApiDataSource()
        ..membersResponse = [
          {'id': 'm1', 'full_name': 'Rep One'},
          {'id': 'm2', 'full_name': 'Rep Two'},
        ];
      final repo = LeadRepositoryImpl(dataSource);

      final members = await repo.listWorkspaceMembers(accessToken: 't', workspaceId: 'w1');

      expect(members.map((m) => m.fullName), ['Rep One', 'Rep Two']);
    });

    test('assignLead sends the member id and maps the updated lead', () async {
      final dataSource = FakeLeadApiDataSource()
        ..assignLeadResponse = _leadJson()
        ..assignLeadResponse['assigned_member'] = {'id': 'm2', 'full_name': 'Rep Two'};
      final repo = LeadRepositoryImpl(dataSource);

      final lead = await repo.assignLead(accessToken: 't', workspaceId: 'w1', leadId: 'lead-1', memberId: 'm2');

      expect(dataSource.lastAssignedMemberId, 'm2');
      expect(lead.assignedMember?.id, 'm2');
    });

    test('assignLead with a null memberId requests unassignment', () async {
      final dataSource = FakeLeadApiDataSource()..assignLeadResponse = _leadJson();
      final repo = LeadRepositoryImpl(dataSource);

      await repo.assignLead(accessToken: 't', workspaceId: 'w1', leadId: 'lead-1', memberId: null);

      expect(dataSource.lastAssignedMemberId, isNull);
      expect(dataSource.lastAssignHadMemberId, isTrue);
    });

    test('listAllocations maps the allocation history', () async {
      final dataSource = FakeLeadApiDataSource()
        ..allocationsResponse = [
          {
            'id': 'a1',
            'previous_member': null,
            'assigned_member': {'id': 'm1', 'full_name': 'Rep One'},
            'assigned_by': {'id': 'm0', 'full_name': 'Manager'},
            'status': 'new',
            'assigned_at': '2026-01-01T00:00:00Z',
            'created_at': '2026-01-01T00:00:00Z',
          },
        ];
      final repo = LeadRepositoryImpl(dataSource);

      final allocations = await repo.listAllocations(accessToken: 't', workspaceId: 'w1', leadId: 'lead-1');

      expect(allocations, hasLength(1));
      expect(allocations.first.assignedMember?.fullName, 'Rep One');
      expect(allocations.first.previousMember, isNull);
    });

    test('bulkAction sends the action and target ids and maps the per-lead results', () async {
      final dataSource = FakeLeadApiDataSource()
        ..bulkActionResponse = {
          'action': 'assign',
          'total': 2,
          'succeeded': 1,
          'failed': 1,
          'results': [
            {'lead_id': 'lead-1', 'success': true, 'error': null},
            {'lead_id': 'lead-2', 'success': false, 'error': 'Lead lead-2 not found.'},
          ],
        };
      final repo = LeadRepositoryImpl(dataSource);

      final result = await repo.bulkAction(
        accessToken: 't',
        workspaceId: 'w1',
        leadIds: ['lead-1', 'lead-2'],
        action: LeadBulkAction.assign,
        memberId: 'm2',
      );

      expect(dataSource.lastBulkLeadIds, ['lead-1', 'lead-2']);
      expect(dataSource.lastBulkAction, 'assign');
      expect(dataSource.lastBulkMemberId, 'm2');
      expect(result.total, 2);
      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(result.items.last.error, 'Lead lead-2 not found.');
    });

    test('bulkAction sends change_status as the wire value for LeadBulkAction.changeStatus', () async {
      final dataSource = FakeLeadApiDataSource();
      final repo = LeadRepositoryImpl(dataSource);

      await repo.bulkAction(accessToken: 't', workspaceId: 'w1', leadIds: ['lead-1'], action: LeadBulkAction.changeStatus, statusId: 's2');

      expect(dataSource.lastBulkAction, 'change_status');
      expect(dataSource.lastBulkStatusId, 's2');
    });

    test('importLeads sends the csv content and maps the row-level summary', () async {
      final dataSource = FakeLeadApiDataSource()
        ..importLeadsResponse = {
          'total': 2,
          'created': 1,
          'failed': 1,
          'errors': [
            {'row': 3, 'error': 'name is required.'},
          ],
        };
      final repo = LeadRepositoryImpl(dataSource);

      final result = await repo.importLeads(accessToken: 't', workspaceId: 'w1', csvContent: 'name\nAcme Corp\n');

      expect(dataSource.lastImportCsvContent, 'name\nAcme Corp\n');
      expect(result.total, 2);
      expect(result.created, 1);
      expect(result.failed, 1);
      expect(result.errors.single.row, 3);
    });

    // ---- Phase 15: unified activity feed & notes ----

    test('getActivity maps items and total', () async {
      final dataSource = FakeLeadApiDataSource()
        ..activityResponse = {
          'items': [
            {
              'id': 'call:c1',
              'type': 'call',
              'occurred_at': '2026-01-05T00:00:00Z',
              'actor_member': {'id': 'm1', 'full_name': 'Rep One'},
              'summary': 'Outbound call — ended',
              'details': {'duration_seconds': 60, 'state': 'ENDED'},
            },
          ],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = LeadRepositoryImpl(dataSource);

      final page = await repo.getActivity(accessToken: 't', workspaceId: 'w1', leadId: 'lead-1', limit: 20, offset: 0);

      expect(page.items, hasLength(1));
      expect(page.items.first.type, 'call');
      expect(page.items.first.sourceId, 'c1');
      expect(page.total, 1);
    });

    test('createNote adapts the InteractionOut response into a TimelineItem', () async {
      final dataSource = FakeLeadApiDataSource()
        ..createNoteResponse = {
          'id': 'i9',
          'type': 'note',
          'payload': {'text': 'Left a voicemail'},
          'actor_member': {'id': 'm1', 'full_name': 'Rep One'},
          'created_at': '2026-01-10T00:00:00Z',
        };
      final repo = LeadRepositoryImpl(dataSource);

      final item = await repo.createNote(accessToken: 't', workspaceId: 'w1', leadId: 'lead-1', text: 'Left a voicemail');

      expect(item.id, 'interaction:i9');
      expect(item.type, 'note');
      expect(item.summary, 'Left a voicemail');
      expect(item.actorMember?.fullName, 'Rep One');
      expect(dataSource.lastNoteLeadId, 'lead-1');
      expect(dataSource.lastNoteText, 'Left a voicemail');
    });
  });
}
