import '../../leads/domain/entities/lead_status.dart';

/// One status row inside a funnel stage.
class FunnelStatusRow {
  const FunnelStatusRow({required this.name, required this.count});

  final String name;
  final int count;
}

/// One pipeline stage — the fixed four-value bucket (`start`,
/// `in_progress`, `closed_won`, `closed_lost`) every workspace-configurable
/// status belongs to — with the statuses under it.
class FunnelStage {
  const FunnelStage({required this.stage, required this.label, required this.statuses});

  final String stage;
  final String label;
  final List<FunnelStatusRow> statuses;

  int get total => statuses.fold(0, (sum, row) => sum + row.count);
}

const _stageOrder = ['start', 'in_progress', 'closed_won', 'closed_lost'];

const _stageLabels = {
  'start': 'Start',
  'in_progress': 'In progress',
  'closed_won': 'Won',
  'closed_lost': 'Lost',
};

/// Groups per-status lead counts into the funnel the Customer Analytics
/// screen draws: stages in pipeline order, statuses within a stage in the
/// workspace's own `sortOrder`. A stage with no configured status is left
/// out (nothing to draw); a status with zero leads is kept, so the funnel
/// shows the whole pipeline rather than only the populated part of it.
List<FunnelStage> buildCustomerFunnel(Iterable<({LeadStatus status, int count})> counts) {
  final byStage = <String, List<({LeadStatus status, int count})>>{};
  for (final entry in counts) {
    byStage.putIfAbsent(entry.status.stage, () => []).add(entry);
  }

  // A stage value outside the known four (a future backend addition)
  // still renders, after the known ones, instead of silently vanishing.
  final stages = [
    ..._stageOrder,
    ...byStage.keys.where((s) => !_stageOrder.contains(s)),
  ];

  return [
    for (final stage in stages)
      if (byStage[stage] != null)
        FunnelStage(
          stage: stage,
          label: _stageLabels[stage] ?? stage,
          statuses: [
            for (final entry in (byStage[stage]!..sort((a, b) => a.status.sortOrder.compareTo(b.status.sortOrder))))
              FunnelStatusRow(name: entry.status.name, count: entry.count),
          ],
        ),
  ];
}
