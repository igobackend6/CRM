import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/analytics/domain/customer_funnel.dart';
import 'package:mobile/features/leads/domain/entities/lead_status.dart';

LeadStatus _status(String name, String stage, int sortOrder) =>
    LeadStatus(id: name, name: name, code: name.toLowerCase(), sortOrder: sortOrder, stage: stage, isDefault: false);

({LeadStatus status, int count}) _row(String name, String stage, int sortOrder, int count) =>
    (status: _status(name, stage, sortOrder), count: count);

void main() {
  test('orders stages start -> in progress -> won -> lost regardless of input order', () {
    final funnel = buildCustomerFunnel([
      _row('Lost', 'closed_lost', 90, 1),
      _row('Won', 'closed_won', 80, 2),
      _row('Contacted', 'in_progress', 20, 3),
      _row('New', 'start', 10, 4),
    ]);

    expect(funnel.map((s) => s.stage), ['start', 'in_progress', 'closed_won', 'closed_lost']);
    expect(funnel.map((s) => s.label), ['Start', 'In progress', 'Won', 'Lost']);
  });

  test('orders the statuses inside a stage by the workspace sort order', () {
    final funnel = buildCustomerFunnel([
      _row('Negotiation', 'in_progress', 30, 1),
      _row('Contacted', 'in_progress', 10, 2),
      _row('Proposal', 'in_progress', 20, 3),
    ]);

    expect(funnel.single.statuses.map((r) => r.name), ['Contacted', 'Proposal', 'Negotiation']);
  });

  test('a stage total is the sum of its statuses', () {
    final funnel = buildCustomerFunnel([_row('A', 'in_progress', 1, 4), _row('B', 'in_progress', 2, 6)]);

    expect(funnel.single.total, 10);
  });

  test('keeps statuses that have zero leads so the whole pipeline is visible', () {
    final funnel = buildCustomerFunnel([_row('New', 'start', 1, 0), _row('Won', 'closed_won', 2, 0)]);

    expect(funnel.length, 2);
    expect(funnel.first.statuses.single.count, 0);
  });

  test('leaves out a stage that has no configured status', () {
    final funnel = buildCustomerFunnel([_row('New', 'start', 1, 5)]);

    expect(funnel.map((s) => s.stage), ['start']);
  });

  test('an unknown future stage still renders, after the known ones', () {
    final funnel = buildCustomerFunnel([_row('On hold', 'paused', 5, 2), _row('New', 'start', 1, 1)]);

    expect(funnel.map((s) => s.stage), ['start', 'paused']);
    expect(funnel.last.label, 'paused');
  });

  test('no statuses at all gives an empty funnel', () {
    expect(buildCustomerFunnel(const []), isEmpty);
  });
}
