import '../../custom_fields/domain/entities/custom_field.dart';

/// The admin's CRM fields the after-call pop-up asks about: every field the member may edit, in the
/// admin's order. Nothing is named here, so a field the admin adds later appears without an app update.
List<CustomField> outcomeFields(List<CustomField> all) {
  final fields = [for (final f in all) if (!f.isReadonly) f]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return fields;
}

/// What a field starts on: the value already saved on the lead, matched to the field's own kind. An
/// option stored as plain text (by an admin tool) is matched by code or label, and a value that no
/// longer exists is dropped rather than shown as a ghost choice.
Object? initialOutcomeValue(CustomField field, Object? stored) {
  switch (field.fieldType) {
    case 'options':
      return _optionCode(field, stored);
    case 'multi_options':
      final list = stored is List ? stored : (stored is String && stored.isNotEmpty ? [stored] : const []);
      return [
        for (final item in list)
          if (_optionCode(field, item) != null) _optionCode(field, item)!,
      ];
    default:
      return stored?.toString() ?? '';
  }
}

String? _optionCode(CustomField field, Object? stored) {
  if (stored is! String || stored.isEmpty) return null;
  for (final o in field.options) {
    if (o.code == stored) return o.code;
  }
  final lowered = stored.trim().toLowerCase();
  for (final o in field.options) {
    if (o.label.trim().toLowerCase() == lowered) return o.code;
  }
  return null;
}

bool outcomeIsEmpty(Object? value) => value == null || (value is String && value.trim().isEmpty) || (value is List && value.isEmpty);

/// Mandatory fields still empty - Submit stays disabled while there are any.
List<CustomField> outcomeMissingMandatory(List<CustomField> fields, Map<String, Object?> values) =>
    [for (final f in fields) if (f.isMandatory && outcomeIsEmpty(values[f.code])) f];

/// What is sent to the server: every field that has a value. A number is sent as a number.
Map<String, Object?> outcomePayload(List<CustomField> fields, Map<String, Object?> values) {
  final out = <String, Object?>{};
  for (final f in fields) {
    final v = values[f.code];
    if (outcomeIsEmpty(v)) continue;
    if (f.fieldType == 'number' && v is String) {
      final n = num.tryParse(v.trim());
      if (n == null) continue;
      out[f.code] = n;
    } else {
      out[f.code] = v is String ? v.trim() : v;
    }
  }
  return out;
}

String outcomeDateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// A saved value as text for a detail screen: an option's label (several joined with commas), or the
/// text/number/date as stored. A value that matches no option is shown as stored. Null when empty.
String? customFieldDisplay(CustomField field, Object? stored) {
  if (stored == null) return null;
  final items = stored is List ? stored : [stored];
  final labels = <String>[];
  for (final item in items) {
    if (item == null) continue;
    final text = item.toString().trim();
    if (text.isEmpty) continue;
    if (field.isChoice) {
      CustomFieldOption? match;
      for (final o in field.options) {
        if (o.code == text || o.label.trim().toLowerCase() == text.toLowerCase()) match = o;
      }
      labels.add(match?.label ?? text);
    } else {
      labels.add(text);
    }
  }
  return labels.isEmpty ? null : labels.join(', ');
}
