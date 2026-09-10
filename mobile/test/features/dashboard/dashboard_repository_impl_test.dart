import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/errors/app_exception.dart';
import 'package:mobile/features/dashboard/data/dashboard_repository_impl.dart';

import 'fake_dashboard_api_data_source.dart';

Map<String, dynamic> _summaryJson() => {
      'total_active_leads': 4,
      'new_leads': 1,
      'customers': 2,
      'pending_follow_ups': 3,
      'overdue_follow_ups': 1,
      'completed_follow_ups': 5,
      'total_calls': 10,
      'todays_calls': 2,
      'unread_notifications': 1,
      'range': 'this_week',
      'leads_created_in_range': 3,
      'converted_leads_in_range': 1,
      'conversion_rate': 0.5,
      'calls_connected_in_range': 6,
      'calls_completed_in_range': 4,
      'completed_follow_ups_in_range': 2,
      'leads_by_status': [
        {
          'status': {'id': 's1', 'name': 'New', 'code': 'new', 'sort_order': 10, 'stage': 'in_progress', 'is_default': true},
          'count': 3,
        },
      ],
      'team_productivity': [
        {
          'member': {'id': 'm1', 'full_name': 'Jamie Rep'},
          'leads_count': 3,
          'calls_count': 6,
          'completed_follow_ups_count': 2,
        },
      ],
    };

Map<String, dynamic> _activityItemJson({String id = 'call:call-1', String type = 'call'}) => {
      'id': id,
      'type': type,
      'occurred_at': '2026-01-01T09:00:00Z',
      'actor_member': {'id': 'm1', 'full_name': 'Rep One'},
      'summary': 'Outbound call — ended',
      'details': <String, dynamic>{},
    };

void main() {
  group('DashboardRepositoryImpl', () {
    test('getSummary maps every field', () async {
      final dataSource = FakeDashboardApiDataSource()..summaryResponse = _summaryJson();
      final repo = DashboardRepositoryImpl(dataSource);

      final summary = await repo.getSummary(accessToken: 't', workspaceId: 'w1');

      expect(summary.totalActiveLeads, 4);
      expect(summary.newLeads, 1);
      expect(summary.customers, 2);
      expect(summary.pendingFollowUps, 3);
      expect(summary.overdueFollowUps, 1);
      expect(summary.completedFollowUps, 5);
      expect(summary.totalCalls, 10);
      expect(summary.todaysCalls, 2);
      expect(summary.unreadNotifications, 1);
      // Phase 17 — period analytics.
      expect(summary.range, 'this_week');
      expect(summary.leadsCreatedInRange, 3);
      expect(summary.convertedLeadsInRange, 1);
      expect(summary.conversionRate, 0.5);
      expect(summary.callsConnectedInRange, 6);
      expect(summary.callsCompletedInRange, 4);
      expect(summary.completedFollowUpsInRange, 2);
      expect(summary.leadsByStatus, hasLength(1));
      expect(summary.leadsByStatus.first.status.name, 'New');
      expect(summary.leadsByStatus.first.count, 3);
      expect(summary.teamProductivity, hasLength(1));
      expect(summary.teamProductivity.first.member.fullName, 'Jamie Rep');
      expect(summary.teamProductivity.first.leadsCount, 3);
    });

    test('getSummary forwards the range parameter to the data source', () async {
      final dataSource = FakeDashboardApiDataSource()..summaryResponse = _summaryJson();
      final repo = DashboardRepositoryImpl(dataSource);

      await repo.getSummary(accessToken: 't', workspaceId: 'w1', range: 'this_month');

      expect(dataSource.lastRange, 'this_month');
    });

    test('getSummary defaults range to "all"', () async {
      final dataSource = FakeDashboardApiDataSource()..summaryResponse = _summaryJson();
      final repo = DashboardRepositoryImpl(dataSource);

      await repo.getSummary(accessToken: 't', workspaceId: 'w1');

      expect(dataSource.lastRange, 'all');
    });

    test('getRecentActivity maps items, total, and pagination', () async {
      final dataSource = FakeDashboardApiDataSource()
        ..recentActivityResponse = {
          'items': [_activityItemJson()],
          'total': 1,
          'limit': 10,
          'offset': 0,
        };
      final repo = DashboardRepositoryImpl(dataSource);

      final page = await repo.getRecentActivity(accessToken: 't', workspaceId: 'w1');

      expect(page.items, hasLength(1));
      expect(page.items.first.type, 'call');
      expect(page.items.first.entityType, 'call');
      expect(page.items.first.entityId, 'call-1');
      expect(page.items.first.actorMember?.fullName, 'Rep One');
      expect(page.total, 1);
    });

    test('getRecentActivity forwards limit/offset', () async {
      final dataSource = FakeDashboardApiDataSource();
      final repo = DashboardRepositoryImpl(dataSource);

      await repo.getRecentActivity(accessToken: 't', workspaceId: 'w1', limit: 5, offset: 15);

      expect(dataSource.lastLimit, 5);
      expect(dataSource.lastOffset, 15);
    });

    test('an item with no actor_member maps to a null actorMember', () async {
      final json = _activityItemJson()..remove('actor_member');
      final dataSource = FakeDashboardApiDataSource()
        ..recentActivityResponse = {
          'items': [json],
          'total': 1,
          'limit': 10,
          'offset': 0,
        };
      final repo = DashboardRepositoryImpl(dataSource);

      final page = await repo.getRecentActivity(accessToken: 't', workspaceId: 'w1');

      expect(page.items.first.actorMember, isNull);
    });

    test('a data-source failure propagates as the same AppException', () async {
      final dataSource = FakeDashboardApiDataSource()..errorToThrow = const NetworkException('Could not reach the server.');
      final repo = DashboardRepositoryImpl(dataSource);

      expect(
        () => repo.getSummary(accessToken: 't', workspaceId: 'w1'),
        throwsA(isA<NetworkException>()),
      );
    });
  });
}
