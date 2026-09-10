import 'package:flutter/material.dart';

import '../../domain/entities/custom_field.dart';

/// Renders one [CustomField] as the right input for its type, reports
/// changes through [onChanged], and validates `is_mandatory` /
/// `is_readonly`. Value shapes match what the backend stores:
/// `text` → `String`, `number` → `num`, `date` → `"YYYY-MM-DD"` string,
/// `options` → option-code string, `multi_options` → list of option codes.
class CustomFieldFormField extends StatefulWidget {
  const CustomFieldFormField({
    super.key,
    required this.field,
    required this.initialValue,
    required this.onChanged,
  });

  final CustomField field;
  final Object? initialValue;
  final ValueChanged<Object?> onChanged;

  @override
  State<CustomFieldFormField> createState() => _CustomFieldFormFieldState();
}

class _CustomFieldFormFieldState extends State<CustomFieldFormField> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.initialValue?.toString() ?? '');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _label => widget.field.isMandatory ? '${widget.field.name} *' : widget.field.name;

  String? _requiredText(String? v) =>
      widget.field.isMandatory && (v == null || v.trim().isEmpty) ? '${widget.field.name} is required.' : null;

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    switch (f.fieldType) {
      case 'number':
        return TextFormField(
          controller: _text,
          enabled: !f.isReadonly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: _label),
          validator: (v) {
            final req = _requiredText(v);
            if (req != null) return req;
            if (v != null && v.trim().isNotEmpty && num.tryParse(v.trim()) == null) return 'Enter a number.';
            return null;
          },
          onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : num.tryParse(v.trim())),
        );

      case 'date':
        final current = widget.initialValue as String?;
        return InkWell(
          onTap: f.isReadonly
              ? null
              : () async {
                  final now = DateTime.now();
                  final parsed = current != null ? DateTime.tryParse(current) : null;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: parsed ?? now,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (picked != null) {
                    widget.onChanged('${picked.year.toString().padLeft(4, '0')}-'
                        '${picked.month.toString().padLeft(2, '0')}-'
                        '${picked.day.toString().padLeft(2, '0')}');
                  }
                },
          child: InputDecorator(
            decoration: InputDecoration(labelText: _label),
            child: Text(current ?? 'Select a date', style: current == null ? Theme.of(context).textTheme.bodyMedium : null),
          ),
        );

      case 'options':
        final value = widget.initialValue as String?;
        return DropdownButtonFormField<String>(
          initialValue: f.options.any((o) => o.code == value) ? value : null,
          decoration: InputDecoration(labelText: _label),
          items: f.options.map((o) => DropdownMenuItem(value: o.code, child: Text(o.label))).toList(),
          onChanged: f.isReadonly ? null : (v) => widget.onChanged(v),
          validator: (v) => _requiredText(v),
        );

      case 'multi_options':
        final selected = ((widget.initialValue as List?) ?? const []).cast<String>().toSet();
        return FormField<Set<String>>(
          initialValue: selected,
          validator: (v) => widget.field.isMandatory && (v == null || v.isEmpty) ? '${f.name} is required.' : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(_label, style: Theme.of(context).textTheme.bodySmall),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: f.options.map((o) {
                  final on = selected.contains(o.code);
                  return FilterChip(
                    label: Text(o.label),
                    selected: on,
                    onSelected: f.isReadonly
                        ? null
                        : (want) {
                            want ? selected.add(o.code) : selected.remove(o.code);
                            state.didChange(selected);
                            widget.onChanged(selected.toList());
                          },
                  );
                }).toList(),
              ),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(state.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
                ),
            ],
          ),
        );

      case 'text':
      default:
        return TextFormField(
          controller: _text,
          enabled: !f.isReadonly,
          decoration: InputDecoration(labelText: _label),
          validator: _requiredText,
          onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v),
        );
    }
  }
}
