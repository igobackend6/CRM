import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_status_chip.dart';
import '../../../../core/widgets/detail_info_row.dart';
import '../../../custom_fields/domain/entities/custom_field.dart';
import '../../../custom_fields/presentation/providers/custom_field_providers.dart';
import '../../domain/interested_in_field.dart';
import '../../domain/outcome_fields.dart';

/// The project a lead is interested in (the admin's "Interested In" field) as text: the option's
/// label, or a value that matches no option as it was stored. Null when nothing is saved.
String? interestedInText(List<CustomField> fields, Map<String, dynamic> customFields) {
  final field = findInterestedInField(fields);
  final stored = field == null ? customFields['interested_in'] : customFields[field.code];
  final label = field == null ? null : optionForStoredValue(field, stored)?.label;
  if (label != null) return label;
  return stored is String && stored.trim().isNotEmpty ? stored.trim() : null;
}

/// Every CRM field the admin defined, as rows on the lead / customer detail screen ("Interested In",
/// "Status", and any field added later), each with the value last saved on the lead - the after-call
/// pop-up writes them, and refreshes the screen. A field with no value shows a dash.
class CustomFieldRows extends ConsumerWidget {
  const CustomFieldRows({super.key, required this.customFields});

  /// The lead's `custom_fields`.
  final Map<String, dynamic> customFields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(workspaceCustomFieldsProvider).valueOrNull ?? const <CustomField>[];
    final ordered = [...fields]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return Column(
      children: [
        for (final field in ordered)
          DetailInfoRow(
            key: Key('custom-field-row-${field.code}'),
            label: field.name,
            value: customFieldDisplay(field, customFields[field.code]) ?? '—',
          ),
      ],
    );
  }
}

/// The lead's built-in pipeline status as a detail row, hidden when the admin has a CRM field coded
/// `status` (the after-call pop-up's "Status"), so the screen never shows two rows with the same name.
class BuiltInStatusRow extends ConsumerWidget {
  const BuiltInStatusRow({super.key, required this.name});

  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(workspaceCustomFieldsProvider).valueOrNull ?? const <CustomField>[];
    if (fields.any((f) => f.code == 'status')) return const SizedBox.shrink();
    return DetailInfoRow(label: 'Status', value: name ?? '—');
  }
}

/// A green chip with the project name, for the lead's header next to its status. Nothing is shown
/// when no project is saved.
class InterestedInChip extends ConsumerWidget {
  const InterestedInChip({super.key, required this.customFields});

  final Map<String, dynamic> customFields;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fields = ref.watch(workspaceCustomFieldsProvider).valueOrNull ?? const <CustomField>[];
    final text = interestedInText(fields, customFields);
    if (text == null) return const SizedBox.shrink();
    return AppStatusChip(key: const Key('interested-in-chip'), label: text, tone: ChipTone.positive, icon: Icons.apartment_outlined);
  }
}
