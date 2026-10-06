import '../../custom_fields/domain/entities/custom_field.dart';

/// Finds the admin-defined "Interested In" field (the project types: Joint venture, nursery,
/// polyhouse, ...) among the workspace's custom fields: a single-choice field whose code is
/// `interested_in` or whose name reads "Interested In". Null while the admin has not created it.
CustomField? findInterestedInField(List<CustomField> fields) {
  for (final field in fields) {
    if (field.fieldType != 'options') continue;
    if (field.code == 'interested_in' || field.name.trim().toLowerCase() == 'interested in') return field;
  }
  return null;
}

/// The option matching a value already stored on a lead, by option code or (for values an admin tool
/// stored as plain text) by label. Null when nothing matches.
CustomFieldOption? optionForStoredValue(CustomField field, Object? stored) {
  if (stored is! String || stored.isEmpty) return null;
  for (final option in field.options) {
    if (option.code == stored) return option;
  }
  final lowered = stored.trim().toLowerCase();
  for (final option in field.options) {
    if (option.label.trim().toLowerCase() == lowered) return option;
  }
  return null;
}
