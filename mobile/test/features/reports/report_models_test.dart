import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/reports/domain/entities/personal_report.dart';
import 'package:mobile/features/reports/domain/entities/pipeline_report.dart';
import 'package:mobile/features/reports/domain/entities/team_report.dart';

void main() {
  group('PersonalReport.fromJson', () {
    test('parses every section from a full backend payload', () {
      final json = {
        'range': 'this_week',
        'since': '2026-01-05T00:00:00+00:00',
        'until': null,
        'calls': {
          'total_calls': 10,
          'connected_calls': 6,
          'unconnected_calls': 4,
          'completed_calls': 6,
          'calls_by_outcome': [
            {
              'outcome': {'id': 'o1', 'name': 'Connected', 'code': 'connected', 'is_positive': true, 'is_default': true},
              'count': 6,
            },
          ],
          'total_talk_time_seconds': 600,
          'average_call_duration_seconds': 100.0,
        },
        'follow_ups': {
          'total_follow_ups': 3,
          'pending_follow_ups': 1,
          'completed_follow_ups': 2,
          'cancelled_follow_ups': 0,
          'overdue_follow_ups': 0,
        },
        'leads': {
          'leads_created': 4,
          'leads_assigned': 5,
          'leads_contacted': 3,
          'leads_converted': 2,
          'conversion_rate': 0.4,
        },
        'pipeline': {
          'leads_by_status': [
            {
              'status': {'id': 's1', 'name': 'New', 'code': 'new', 'sort_order': 10, 'stage': 'in_progress', 'is_default': true},
              'count': 2,
            },
          ],
          'customer_count': 2,
          'lost_leads': 1,
          'active_pipeline_count': 2,
        },
      };

      final report = PersonalReport.fromJson(json);

      expect(report.range, 'this_week');
      expect(report.since, DateTime.parse('2026-01-05T00:00:00+00:00'));
      expect(report.until, isNull);
      expect(report.calls.totalCalls, 10);
      expect(report.calls.callsByOutcome, hasLength(1));
      expect(report.calls.callsByOutcome.first.outcome.name, 'Connected');
      expect(report.followUps.pendingFollowUps, 1);
      expect(report.leads.conversionRate, 0.4);
      expect(report.pipeline.leadsByStatus.first.status.name, 'New');
      expect(report.pipeline.activePipelineCount, 2);
    });

    test('missing optional sections fall back to zeroed defaults, not a crash', () {
      final report = PersonalReport.fromJson(const {'range': 'all_time'});

      expect(report.calls.totalCalls, 0);
      expect(report.followUps.totalFollowUps, 0);
      expect(report.leads.conversionRate, 0.0);
      expect(report.pipeline.leadsByStatus, isEmpty);
    });
  });

  group('TeamReportPage.fromJson', () {
    test('parses items and totals', () {
      final json = {
        'range': 'all_time',
        'items': [
          {
            'member': {'id': 'm1', 'full_name': 'Jamie Rep'},
            'leads_assigned': 3,
            'leads_converted': 1,
            'conversion_rate': 0.33,
            'calls': 5,
            'connected_calls': 3,
            'talk_time_seconds': 300,
            'completed_follow_ups': 2,
            'pending_follow_ups': 1,
          },
        ],
        'total': 1,
        'limit': 20,
        'offset': 0,
        'totals': {
          'leads_assigned': 3,
          'leads_converted': 1,
          'conversion_rate': 0.33,
          'calls': 5,
          'connected_calls': 3,
          'talk_time_seconds': 300,
          'completed_follow_ups': 2,
          'pending_follow_ups': 1,
        },
      };

      final page = TeamReportPage.fromJson(json);

      expect(page.items, hasLength(1));
      expect(page.items.first.member.displayName, 'Jamie Rep');
      expect(page.total, 1);
      expect(page.totals.calls, 5);
    });

    test('an empty page parses to zero totals, not a crash', () {
      final page = TeamReportPage.fromJson(const {'range': 'all_time', 'items': [], 'total': 0, 'limit': 20, 'offset': 0});

      expect(page.items, isEmpty);
      expect(page.totals.conversionRate, 0.0);
    });
  });

  group('PipelineReport.fromJson', () {
    test('parses status, source, and priority breakdowns', () {
      final json = {
        'range': 'all_time',
        'leads_by_status': [
          {
            'status': {'id': 's1', 'name': 'New', 'code': 'new', 'sort_order': 10, 'stage': 'in_progress', 'is_default': true},
            'count': 5,
            'percentage': 100.0,
          },
        ],
        'converted_customers': 3,
        'lost_leads': 1,
        'active_leads': 4,
        'source_performance': [
          {
            'source': {'id': 'src1', 'name': 'Website', 'code': 'website', 'is_default': false},
            'leads_count': 5,
            'converted_count': 2,
            'conversion_rate': 0.4,
          },
        ],
        'priority_distribution': [
          {'priority': 'medium', 'count': 5, 'percentage': 100.0},
        ],
      };

      final report = PipelineReport.fromJson(json);

      expect(report.leadsByStatus.first.percentage, 100.0);
      expect(report.sourcePerformance.first.source.name, 'Website');
      expect(report.priorityDistribution.first.priority, 'medium');
      expect(report.convertedCustomers, 3);
    });
  });
}
