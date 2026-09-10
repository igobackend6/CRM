import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/customer360/data/customer_repository_impl.dart';

import 'fake_customer_api_data_source.dart';

Map<String, dynamic> _leadJson({String id = 'c1', bool isCustomer = true}) => {
      'id': id,
      'workspace_id': 'w1',
      'name': 'Acme Corp',
      'phone': '+15551234567',
      'email': 'acme@example.com',
      'priority': 'high',
      'status': {'id': 's1', 'name': 'Qualified', 'code': 'qualified', 'sort_order': 30, 'stage': 'in_progress', 'is_default': false},
      'source': null,
      'assigned_member': {'id': 'm1', 'full_name': 'Rep One'},
      'created_by_member': {'id': 'm1', 'full_name': 'Rep One'},
      'is_customer': isCustomer,
      'tags': [],
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    };

void main() {
  group('CustomerRepositoryImpl', () {
    test('getCustomer maps the lead JSON', () async {
      final dataSource = FakeCustomerApiDataSource()..getCustomerResponse = _leadJson();
      final repo = CustomerRepositoryImpl(dataSource);

      final customer = await repo.getCustomer(accessToken: 't', workspaceId: 'w1', customerId: 'c1');

      expect(customer.name, 'Acme Corp');
      expect(customer.isCustomer, isTrue);
      expect(customer.status?.name, 'Qualified');
    });

    test('getTimeline maps items and total', () async {
      final dataSource = FakeCustomerApiDataSource()
        ..getTimelineResponse = {
          'items': [
            {
              'id': 'note:i1',
              'type': 'note',
              'occurred_at': '2026-01-05T00:00:00Z',
              'actor_member': {'id': 'm1', 'full_name': 'Rep One'},
              'summary': 'Called back',
              'details': {'text': 'Called back'},
            },
          ],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = CustomerRepositoryImpl(dataSource);

      final page = await repo.getTimeline(accessToken: 't', workspaceId: 'w1', customerId: 'c1', limit: 20, offset: 0);

      expect(page.items, hasLength(1));
      expect(page.items.first.type, 'note');
      expect(page.items.first.summary, 'Called back');
      expect(page.total, 1);
    });

    test('listFollowUps maps the customer-scoped list', () async {
      final dataSource = FakeCustomerApiDataSource()
        ..listFollowUpsResponse = [
          {
            'id': 'fu-1',
            'workspace_id': 'w1',
            'lead': {'id': 'c1', 'name': 'Acme Corp'},
            'type': 'call',
            'due_at': '2026-02-01T09:00:00Z',
            'status': 'pending',
            'notes': null,
            'assigned_member': null,
            'created_by_member': null,
            'completed_at': null,
            'cancelled_at': null,
            'is_overdue': false,
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          },
        ];
      final repo = CustomerRepositoryImpl(dataSource);

      final followUps = await repo.listFollowUps(accessToken: 't', workspaceId: 'w1', customerId: 'c1');

      expect(followUps, hasLength(1));
      expect(followUps.first.status, 'pending');
    });

    test('createNote adapts the InteractionOut response into a TimelineItem', () async {
      final dataSource = FakeCustomerApiDataSource()
        ..createNoteResponse = {
          'id': 'i9',
          'type': 'note',
          'payload': {'text': 'Left a voicemail'},
          'actor_member': {'id': 'm1', 'full_name': 'Rep One'},
          'created_at': '2026-01-10T00:00:00Z',
        };
      final repo = CustomerRepositoryImpl(dataSource);

      final item = await repo.createNote(accessToken: 't', workspaceId: 'w1', customerId: 'c1', text: 'Left a voicemail');

      expect(item.id, 'interaction:i9');
      expect(item.type, 'note');
      expect(item.summary, 'Left a voicemail');
      expect(item.actorMember?.fullName, 'Rep One');
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeCustomerApiDataSource()..errorToThrow = const NotFoundException('Customer not found.');
      final repo = CustomerRepositoryImpl(dataSource);

      expect(
        () => repo.getCustomer(accessToken: 't', workspaceId: 'w1', customerId: 'missing'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
