import 'entities/lead.dart';

/// Whether the signed-in member may edit [lead]'s details in the app.
///
/// Only leads the member created themselves are editable. A lead an admin allocates from the admin
/// web is the admin's record: the member works it (calls, notes, follow-ups, status) but does not
/// rewrite its details. If the creator or the current member is unknown, nothing is editable.
bool canEditLead(Lead lead, String? currentMemberId) {
  final creatorId = lead.createdByMember?.id;
  return creatorId != null && currentMemberId != null && creatorId == currentMemberId;
}
