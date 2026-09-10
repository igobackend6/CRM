import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/rechurn/data/rechurn_repository_impl.dart';

import 'fake_rechurn_api_data_source.dart';

Map<String, dynamic> _cardJson({String id = 'lead-1', String name = 'Acme Corp'}) => {
      'id': id,
      'name': name,
      'phone': '+15551234567',
      'email': 'acme@example.com',
      'priority': 'medium',
      'status': {'id': 's1', 'name': 'New', 'code': 'new', 'sort_order': 10, 'stage': 'in_progress', 'is_default': true},
      'assigned_member': {'id': 'm1', 'full_name': 'Rep One'},
      'is_customer': false,
      'last_activity_at': '2026-01-01T00:00:00Z',
      'next_follow_up': null,
    };

void main() {
  group('RechurnRepositoryImpl', () {
    test('getQueue maps items, total, and forwards every filter', () async {
      final dataSource = FakeRechurnApiDataSource()
        ..queueResponse = {'items': [_cardJson()], 'total': 1, 'limit': 20, 'offset': 0};
      final repo = RechurnRepositoryImpl(dataSource);

      final page = await repo.getQueue(
        accessToken: 't',
        workspaceId: 'w1',
        segment: 'inactive',
        inactiveDays: 60,
        priority: 'high',
        search: 'acme',
        offset: 0,
      );

      expect(page.items, hasLength(1));
      expect(page.items.first.name, 'Acme Corp');
      expect(page.items.first.status?.name, 'New');
      expect(page.items.first.assignedMember?.fullName, 'Rep One');
      expect(page.total, 1);
      expect(dataSource.lastSegment, 'inactive');
      expect(dataSource.lastInactiveDays, 60);
      expect(dataSource.lastPriority, 'high');
      expect(dataSource.lastSearch, 'acme');
    });

    test('getQueue maps a present next_follow_up', () async {
      final dataSource = FakeRechurnApiDataSource()
        ..queueResponse = {
          'items': [
            {..._cardJson(), 'next_follow_up': {'id': 'f1', 'type': 'call', 'due_at': '2026-02-01T09:00:00Z'}},
          ],
          'total': 1,
          'limit': 20,
          'offset': 0,
        };
      final repo = RechurnRepositoryImpl(dataSource);

      final page = await repo.getQueue(accessToken: 't', workspaceId: 'w1');

      expect(page.items.first.nextFollowUp?.id, 'f1');
      expect(page.items.first.nextFollowUp?.type, 'call');
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeRechurnApiDataSource()..errorToThrow = const NetworkException('Could not reach the server.');
      final repo = RechurnRepositoryImpl(dataSource);

      expect(() => repo.getQueue(accessToken: 't', workspaceId: 'w1'), throwsA(isA<NetworkException>()));
    });
  });
}
