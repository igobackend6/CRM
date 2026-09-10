/// Phase 13 §"Bulk Actions" — mirrors the backend's `BulkLeadAction`
/// enum (backend/app/schemas/data_ops.py) exactly, one entry per
/// supported action.
enum LeadBulkAction { assign, unassign, changeStatus, delete }

extension LeadBulkActionWire on LeadBulkAction {
  String get wireValue => switch (this) {
        LeadBulkAction.assign => 'assign',
        LeadBulkAction.unassign => 'unassign',
        LeadBulkAction.changeStatus => 'change_status',
        LeadBulkAction.delete => 'delete',
      };

  String get label => switch (this) {
        LeadBulkAction.assign => 'Assign',
        LeadBulkAction.unassign => 'Unassign',
        LeadBulkAction.changeStatus => 'Change status',
        LeadBulkAction.delete => 'Delete',
      };
}
