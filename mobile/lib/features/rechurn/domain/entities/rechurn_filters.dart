import 'package:flutter/foundation.dart' show immutable;

/// Rechurn queue filters (Phase 19) — mirrors `LeadFilters`' role
/// (Phase 14) as one value object shared by the controller and the
/// repository/data-source layer, just for the rechurn-specific
/// `segment`/`inactiveDays` dimensions plus the same assigned-member/
/// priority/status/source filters `LeadFilters` already has.
@immutable
class RechurnFilters {
  const RechurnFilters({
    this.segment,
    this.inactiveDays = 30,
    this.assignedMemberId,
    this.priority,
    this.statusId,
    this.sourceId,
  });

  const RechurnFilters.empty() : this();

  /// `null` (both), `'inactive'`, or `'lost'`.
  final String? segment;
  final int inactiveDays;
  final String? assignedMemberId;
  final String? priority;
  final String? statusId;
  final String? sourceId;

  int get activeCount =>
      [segment, assignedMemberId, priority, statusId, sourceId].where((v) => v != null).length +
      (inactiveDays == 30 ? 0 : 1);

  RechurnFilters copyWith({
    String? segment,
    bool clearSegment = false,
    int? inactiveDays,
    String? assignedMemberId,
    bool clearAssignedMemberId = false,
    String? priority,
    bool clearPriority = false,
    String? statusId,
    bool clearStatusId = false,
    String? sourceId,
    bool clearSourceId = false,
  }) {
    return RechurnFilters(
      segment: clearSegment ? null : (segment ?? this.segment),
      inactiveDays: inactiveDays ?? this.inactiveDays,
      assignedMemberId: clearAssignedMemberId ? null : (assignedMemberId ?? this.assignedMemberId),
      priority: clearPriority ? null : (priority ?? this.priority),
      statusId: clearStatusId ? null : (statusId ?? this.statusId),
      sourceId: clearSourceId ? null : (sourceId ?? this.sourceId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RechurnFilters &&
          other.segment == segment &&
          other.inactiveDays == inactiveDays &&
          other.assignedMemberId == assignedMemberId &&
          other.priority == priority &&
          other.statusId == statusId &&
          other.sourceId == sourceId);

  @override
  int get hashCode => Object.hash(segment, inactiveDays, assignedMemberId, priority, statusId, sourceId);
}
