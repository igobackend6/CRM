import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../custom_fields/domain/entities/custom_field.dart';
import '../../../custom_fields/presentation/providers/custom_field_providers.dart';
import '../../../custom_fields/presentation/widgets/custom_field_form_field.dart';
import '../../domain/entities/lead_draft.dart';
import '../../domain/entities/lead_form_state.dart';
import '../../domain/entities/lead_status.dart';
import '../providers/leads_providers.dart';

/// Create Lead (Phase 5 §3) and Edit Lead (§4) — same form, mode decided
/// by whether [leadId] is set.
class LeadFormScreen extends ConsumerStatefulWidget {
  const LeadFormScreen({super.key, this.leadId});

  final String? leadId;

  bool get isEditing => leadId != null;

  @override
  ConsumerState<LeadFormScreen> createState() => _LeadFormScreenState();
}

class _LeadFormScreenState extends ConsumerState<LeadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _countryController = TextEditingController();
  final _stateController = TextEditingController();
  final _cityController = TextEditingController();
  String? _sourceId;
  String? _statusId;
  String _priority = 'medium';
  final Map<String, Object?> _customValues = {};
  bool _prefilled = false;
  bool _defaultStatusApplied = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _countryController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  void _prefillIfEditing() {
    if (_prefilled || !widget.isEditing) return;
    final detail = ref.read(leadDetailControllerProvider(widget.leadId!));
    final lead = detail.lead;
    if (lead == null) return;
    _nameController.text = lead.name;
    _phoneController.text = lead.phone ?? '';
    _emailController.text = lead.email ?? '';
    _addressController.text = lead.addressLine ?? '';
    _countryController.text = lead.country ?? '';
    _stateController.text = lead.stateRegion ?? '';
    _cityController.text = lead.city ?? '';
    _sourceId = lead.source?.id;
    _statusId = lead.status?.id;
    _priority = lead.priority;
    _customValues
      ..clear()
      ..addAll(lead.customFields);
    _prefilled = true;
    _defaultStatusApplied = true;
  }

  LeadStatus? _findDefault(List<LeadStatus> statuses) {
    for (final status in statuses) {
      if (status.isDefault) return status;
    }
    return null;
  }

  void _submit(List<CustomField> customFields) {
    if (!_formKey.currentState!.validate()) return;
    // Only submit codes the form actually rendered — the backend
    // rejects unknown codes, and a stale/removed field shouldn't travel.
    final shown = {for (final f in customFields) f.code};
    final customPayload = {
      for (final entry in _customValues.entries)
        if (shown.contains(entry.key)) entry.key: entry.value,
    };
    final draft = LeadDraft(
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      addressLine: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      city: _cityController.text.trim().isEmpty ? null : _cityController.text.trim(),
      stateRegion: _stateController.text.trim().isEmpty ? null : _stateController.text.trim(),
      country: _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
      sourceId: _sourceId,
      statusId: _statusId,
      priority: _priority,
      customFields: customFields.isEmpty ? null : customPayload,
    );
    final controller = ref.read(leadFormControllerProvider.notifier);
    if (widget.isEditing) {
      controller.update(widget.leadId!, draft);
    } else {
      controller.create(draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing) _prefillIfEditing();

    final referenceAsync = ref.watch(leadReferenceDataProvider);
    final customFieldsAsync = ref.watch(workspaceCustomFieldsProvider);
    final formState = ref.watch(leadFormControllerProvider);

    ref.listen<LeadFormState>(leadFormControllerProvider, (previous, next) {
      if (next.status == LeadFormStatus.success && next.lead != null) {
        if (widget.isEditing) {
          ref.invalidate(leadDetailControllerProvider(widget.leadId!));
        } else {
          ref.invalidate(leadListControllerProvider);
        }
        context.pop(next.lead);
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Edit lead' : 'New lead')),
      body: referenceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('Could not load status/source options.')),
        data: (reference) {
          if (!widget.isEditing && !_defaultStatusApplied) {
            _statusId ??= _findDefault(reference.statuses)?.id;
            _defaultStatusApplied = true;
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (formState.status == LeadFormStatus.error && formState.errorMessage != null) ...[
                    AppErrorBanner(message: formState.errorMessage!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name *'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Name is required.' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Grouped sections below — the Runo-reference "Personal
                  // Information / Custom Fields / Priority / Others"
                  // pattern (docs/design/design-tokens.md), relabeled to
                  // this app's own terms: "Custom Fields" here means only
                  // the genuine workspace-defined fields (000025), so
                  // Source/Status (core lead classification, not
                  // per-workspace config) get their own group instead of
                  // borrowing that name.
                  CollapsibleSection(
                    title: 'Personal Information',
                    initiallyExpanded: widget.isEditing,
                    children: [
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                      ),
                      TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(labelText: 'Address'),
                      ),
                      TextFormField(
                        controller: _countryController,
                        decoration: const InputDecoration(labelText: 'Country'),
                      ),
                      TextFormField(
                        controller: _stateController,
                        decoration: const InputDecoration(labelText: 'State'),
                      ),
                      TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(labelText: 'City'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CollapsibleSection(
                    title: 'Classification',
                    initiallyExpanded: widget.isEditing,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _sourceId,
                        decoration: const InputDecoration(labelText: 'Source'),
                        items: reference.sources.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                        onChanged: (value) => setState(() => _sourceId = value),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _statusId,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: reference.statuses.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
                        onChanged: (value) => setState(() => _statusId = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CollapsibleSection(
                    title: 'Priority',
                    initiallyExpanded: widget.isEditing,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _priority,
                        decoration: const InputDecoration(labelText: 'Priority'),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                          DropdownMenuItem(value: 'medium', child: Text('Medium')),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                          DropdownMenuItem(value: 'urgent', child: Text('Urgent')),
                        ],
                        onChanged: (value) => setState(() => _priority = value ?? 'medium'),
                      ),
                    ],
                  ),
                  ..._buildCustomFieldsSection(customFieldsAsync),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    onPressed: (formState.status == LeadFormStatus.submitting || customFieldsAsync.isLoading)
                        ? null
                        : () => _submit(customFieldsAsync.valueOrNull ?? const []),
                    child: formState.status == LeadFormStatus.submitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(widget.isEditing ? 'Save changes' : 'Create lead'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The genuine workspace-defined fields (000025_custom_fields.sql) —
  /// its own group, only rendered once loaded and non-empty; a loading
  /// or error state renders inline (not inside a collapsed section the
  /// user might never open) so it's never silently hidden.
  List<Widget> _buildCustomFieldsSection(AsyncValue<List<CustomField>> async) {
    return async.when(
      loading: () => const [SizedBox(height: AppSpacing.md), LinearProgressIndicator()],
      error: (_, _) => const [
        SizedBox(height: AppSpacing.md),
        AppErrorBanner(message: "Could not load this workspace's custom fields."),
      ],
      data: (fields) {
        if (fields.isEmpty) return const [];
        return [
          const SizedBox(height: AppSpacing.md),
          CollapsibleSection(
            title: 'Custom Fields',
            initiallyExpanded: widget.isEditing,
            children: [
              for (final field in fields)
                CustomFieldFormField(
                  key: ValueKey(field.id),
                  field: field,
                  initialValue: _customValues[field.code],
                  onChanged: (value) => _customValues[field.code] = value,
                ),
            ],
          ),
        ];
      },
    );
  }
}
