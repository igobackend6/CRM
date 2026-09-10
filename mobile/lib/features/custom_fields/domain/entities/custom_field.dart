/// Mirrors backend `CustomFieldOut` (backend/app/schemas/custom_fields.py)
/// / `custom_fields` (000025_custom_fields.sql). Defined by an admin;
/// the mobile app only ever reads these to render the lead form.
class CustomField {
  const CustomField({
    required this.id,
    required this.name,
    required this.code,
    required this.fieldType,
    this.options = const [],
    required this.autoFill,
    required this.isFilterable,
    required this.isReadonly,
    required this.isMandatory,
    required this.sortOrder,
  });

  factory CustomField.fromJson(Map<String, dynamic> json) => CustomField(
        id: json['id'] as String,
        name: json['name'] as String,
        code: json['code'] as String,
        fieldType: json['field_type'] as String,
        options: (json['options'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(CustomFieldOption.fromJson)
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
        autoFill: json['auto_fill'] as bool? ?? true,
        isFilterable: json['is_filterable'] as bool? ?? false,
        isReadonly: json['is_readonly'] as bool? ?? false,
        isMandatory: json['is_mandatory'] as bool? ?? false,
        sortOrder: json['sort_order'] as int? ?? 0,
      );

  final String id;
  final String name;
  final String code;

  /// One of: `text`, `number`, `date`, `options`, `multi_options`.
  final String fieldType;
  final List<CustomFieldOption> options;
  final bool autoFill;
  final bool isFilterable;
  final bool isReadonly;
  final bool isMandatory;
  final int sortOrder;

  bool get isChoice => fieldType == 'options' || fieldType == 'multi_options';
}

class CustomFieldOption {
  const CustomFieldOption({required this.code, required this.label, this.sortOrder = 0});

  factory CustomFieldOption.fromJson(Map<String, dynamic> json) => CustomFieldOption(
        code: json['code'] as String,
        label: json['label'] as String? ?? json['code'] as String,
        sortOrder: json['sort_order'] as int? ?? 0,
      );

  final String code;
  final String label;
  final int sortOrder;
}
