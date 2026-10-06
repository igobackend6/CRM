import 'package:flutter/foundation.dart' show immutable;

/// Phase 14 — the Lead List's advanced filters, centralized as one value
/// object (mirrors LeadDraft's role for create/update) so the controller,
/// the repository/data-source layer, and saved-view persistence all
/// share one shape instead of eight loose parameters threaded through
/// every layer separately. `search` stays its own field on
/// [LeadListState] (Phase 5's debounced free-text box) rather than living
/// here — a saved "view" is a set of filters, not a saved search term.
@immutable
class LeadFilters {
  const LeadFilters({
    this.statusId,
    this.sourceId,
    this.assignedMemberId,
    this.priority,
    this.isCustomer,
    this.createdFrom,
    this.createdTo,
    this.tagId,
  });

  const LeadFilters.empty() : this();

  final String? statusId;
  final String? sourceId;
  final String? assignedMemberId;
  final String? priority;
  final bool? isCustomer;
  final DateTime? createdFrom;
  final DateTime? createdTo;
  final String? tagId;

  bool get isEmpty =>
      statusId == null &&
      sourceId == null &&
      assignedMemberId == null &&
      priority == null &&
      isCustomer == null &&
      createdFrom == null &&
      createdTo == null &&
      tagId == null;

  bool get isNotEmpty => !isEmpty;

  /// Same filters with only the status swapped (null = any status) — the
  /// Allocations header's status dropdown changes just this one dimension.
  LeadFilters withStatus(String? id) => LeadFilters(
        statusId: id,
        sourceId: sourceId,
        assignedMemberId: assignedMemberId,
        priority: priority,
        isCustomer: isCustomer,
        createdFrom: createdFrom,
        createdTo: createdTo,
        tagId: tagId,
      );

  /// Same filters with only the customer flag swapped (the Customers tab pins this to true).
  LeadFilters withIsCustomer(bool? value) => LeadFilters(
        statusId: statusId,
        sourceId: sourceId,
        assignedMemberId: assignedMemberId,
        priority: priority,
        isCustomer: value,
        createdFrom: createdFrom,
        createdTo: createdTo,
        tagId: tagId,
      );

  /// Same filters with only the created-date window swapped (both null =
  /// no date limit) — the Allocations date chips change just this pair.
  LeadFilters withDates({DateTime? from, DateTime? to}) => LeadFilters(
        statusId: statusId,
        sourceId: sourceId,
        assignedMemberId: assignedMemberId,
        priority: priority,
        isCustomer: isCustomer,
        createdFrom: from,
        createdTo: to,
        tagId: tagId,
      );

  /// Number of active filter dimensions — drives the Lead List app bar's
  /// filter-count badge (§"active-filter indicator/count").
  int get activeCount => [statusId, sourceId, assignedMemberId, priority, isCustomer, createdFrom, createdTo, tagId]
      .where((v) => v != null)
      .length;

  Map<String, dynamic> toJson() => {
        'status_id': statusId,
        'source_id': sourceId,
        'assigned_member_id': assignedMemberId,
        'priority': priority,
        'is_customer': isCustomer,
        'created_from': createdFrom?.toIso8601String(),
        'created_to': createdTo?.toIso8601String(),
        'tag_id': tagId,
      };

  factory LeadFilters.fromJson(Map<String, dynamic> json) => LeadFilters(
        statusId: json['status_id'] as String?,
        sourceId: json['source_id'] as String?,
        assignedMemberId: json['assigned_member_id'] as String?,
        priority: json['priority'] as String?,
        isCustomer: json['is_customer'] as bool?,
        createdFrom: json['created_from'] != null ? DateTime.parse(json['created_from'] as String) : null,
        createdTo: json['created_to'] != null ? DateTime.parse(json['created_to'] as String) : null,
        tagId: json['tag_id'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LeadFilters &&
          other.statusId == statusId &&
          other.sourceId == sourceId &&
          other.assignedMemberId == assignedMemberId &&
          other.priority == priority &&
          other.isCustomer == isCustomer &&
          other.createdFrom == createdFrom &&
          other.createdTo == createdTo &&
          other.tagId == tagId);

  @override
  int get hashCode =>
      Object.hash(statusId, sourceId, assignedMemberId, priority, isCustomer, createdFrom, createdTo, tagId);
}
