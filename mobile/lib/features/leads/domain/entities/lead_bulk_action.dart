/// Phase 13 §"Bulk Actions" — mirrors the backend's `BulkLeadAction`
/// enum (backend/app/schemas/data_ops.py), one entry per action the app offers.
/// Deleting leads is deliberately not offered here: deletes are done by admins in the admin web.
enum LeadBulkAction { assign, unassign, changeStatus }

extension LeadBulkActionWire on LeadBulkAction {
  String get wireValue => switch (this) {
        LeadBulkAction.assign => 'assign',
        LeadBulkAction.unassign => 'unassign',
        LeadBulkAction.changeStatus => 'change_status',
      };

  String get label => switch (this) {
        LeadBulkAction.assign => 'Assign',
        LeadBulkAction.unassign => 'Unassign',
        LeadBulkAction.changeStatus => 'Change status',
      };
}
