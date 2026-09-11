/// The editable subset of a lead, as submitted from the create/edit form.
/// Mirrors backend `LeadCreate`/`LeadUpdate` (backend/app/schemas/leads.py)
/// — deliberately carries no workspace_id/assigned_member_id/
/// created_by_member_id fields: those are never client-supplied
/// (Phase 5 §9), so there's nothing here to trust or not trust.
class LeadDraft {
  const LeadDraft({
    required this.name,
    this.phone,
    this.email,
    this.addressLine,
    this.city,
    this.stateRegion,
    this.country,
    this.sourceId,
    this.statusId,
    this.priority = 'medium',
    this.customFields,
  });

  final String name;
  final String? phone;
  final String? email;
  final String? addressLine;
  final String? city;
  final String? stateRegion;
  final String? country;
  final String? sourceId;
  final String? statusId;
  final String priority;

  /// `{field_code: value}` for workspace-defined custom fields
  /// (000025_custom_fields.sql). Null when the form has no custom
  /// fields to submit; a null *value* inside the map clears that field.
  final Map<String, Object?>? customFields;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (email != null && email!.isNotEmpty) 'email': email,
        if (addressLine != null && addressLine!.isNotEmpty) 'address_line': addressLine,
        if (city != null && city!.isNotEmpty) 'city': city,
        if (stateRegion != null && stateRegion!.isNotEmpty) 'state_region': stateRegion,
        if (country != null && country!.isNotEmpty) 'country': country,
        if (sourceId != null) 'source_id': sourceId,
        if (statusId != null) 'status_id': statusId,
        'priority': priority,
        if (customFields != null) 'custom_fields': customFields,
      };
}
