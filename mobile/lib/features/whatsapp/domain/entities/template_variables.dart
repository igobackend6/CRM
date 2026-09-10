/// The fixed variable set Phase 21A §7 defines — `{{name}}`,
/// `{{phone}}`, `{{company}}`, `{{status}}`, `{{assigned_member}}` —
/// resolved from data the caller already has on screen (the lead
/// itself), never fetched separately.
class TemplateVariables {
  const TemplateVariables({this.name, this.phone, this.company, this.status, this.assignedMember});

  final String? name;
  final String? phone;
  final String? company;
  final String? status;
  final String? assignedMember;

  /// Missing values render as an empty string (§7 "safely handle
  /// missing values") rather than the literal "null" or leaving the
  /// `{{token}}` in place — a message with a blank where the assigned
  /// rep's name would go is a safer default to send than one that
  /// leaks template syntax to the customer.
  Map<String, String> toMap() => {
        'name': name ?? '',
        'phone': phone ?? '',
        'company': company ?? '',
        'status': status ?? '',
        'assigned_member': assignedMember ?? '',
      };
}
