import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/location_service.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../custom_fields/domain/entities/custom_field.dart';
import '../../../custom_fields/presentation/providers/custom_field_providers.dart';
import '../../../custom_fields/presentation/widgets/custom_field_form_field.dart';
import '../../../documents/domain/entities/picked_document_file.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../domain/entities/lead_draft.dart';
import '../../domain/entities/lead_form_state.dart';
import '../../domain/entities/lead_status.dart';
import '../../domain/lead_edit_access.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../controllers/lead_request_context.dart';
import '../providers/leads_providers.dart';

/// 25MB — matches the real backend limit (documents/validation.py's
/// MAX_SIZE_BYTES), not the reference screenshot's "2MB" caption, which
/// doesn't correspond to anything this app actually enforces.
const _kMaxDocumentBytes = 25 * 1024 * 1024;

/// Create Lead (Phase 5 §3) and Edit Lead (§4) — same form, mode decided
/// by whether [leadId] is set.
class LeadFormScreen extends ConsumerStatefulWidget {
  const LeadFormScreen({super.key, this.leadId, this.initialPhone});

  final String? leadId;

  /// Pre-fills the Phone field on create — used by the dialer
  /// (`RoutePaths.dialer`)'s "Create new customer" shortcut so a number
  /// already typed there isn't retyped. Ignored in edit mode, where the
  /// lead's own phone always wins.
  final String? initialPhone;

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
  final _notesController = TextEditingController();
  String? _sourceId;
  String? _statusId;
  String _priority = 'medium';
  final Map<String, Object?> _customValues = {};
  bool _prefilled = false;
  bool _defaultStatusApplied = false;

  // "Others" section (create-only — see the CollapsibleSection below for
  // why this doesn't also show up in edit mode).
  LocationResult? _location;
  bool _locationBusy = false;
  String? _locationMessage;
  final List<PickedDocumentFile> _stagedDocuments = [];

  @override
  void initState() {
    super.initState();
    if (!widget.isEditing && widget.initialPhone != null) {
      _phoneController.text = widget.initialPhone!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _countryController.dispose();
    _stateController.dispose();
    _cityController.dispose();
    _notesController.dispose();
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

  Future<void> _grantLocation() async {
    setState(() {
      _locationBusy = true;
      _locationMessage = null;
    });
    final result = await ref.read(leadLocationServiceProvider).requestAndGetLocation();
    if (!mounted) return;
    setState(() {
      _locationBusy = false;
      _location = result;
      if (result == null) {
        _locationMessage = 'Location service disabled or permission denied.';
      }
    });
  }

  Future<void> _pickDocument() async {
    final file = await ref.read(documentFilePickerProvider).pickDocumentFile();
    if (file == null || !mounted) return;
    if (file.bytes.length > _kMaxDocumentBytes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File exceeds the 25MB size limit.')));
      return;
    }
    setState(() => _stagedDocuments.add(file));
  }

  void _removeDocument(int index) => setState(() => _stagedDocuments.removeAt(index));

  /// Fire-and-forget: the lead itself is already created by the time
  /// this runs (see the `ref.listen` success handler below), so a note/
  /// document failure here shouldn't block the user from moving on —
  /// it's supplementary to the record, not the record itself. Logged,
  /// not surfaced, same tradeoff FCM push (services/push) makes.
  void _uploadStagedExtras(String leadId) {
    final requestContext = resolveLeadContext(ref.read);
    if (requestContext == null) return;

    final notes = _notesController.text.trim();
    if (notes.isNotEmpty) {
      unawaited(
        ref
            .read(leadRepositoryProvider)
            .createNote(
              accessToken: requestContext.accessToken,
              workspaceId: requestContext.workspaceId,
              leadId: leadId,
              text: notes,
            )
            .then((_) {}, onError: (Object e) => AppLogger.warning('Could not save the new lead\'s note: $e')),
      );
    }

    for (final file in _stagedDocuments) {
      unawaited(
        ref
            .read(documentRepositoryProvider)
            .uploadDocument(
              accessToken: requestContext.accessToken,
              workspaceId: requestContext.workspaceId,
              leadId: leadId,
              file: file,
            )
            .then((_) {}, onError: (Object e) => AppLogger.warning('Could not upload a document for the new lead: $e')),
      );
    }
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
      latitude: _location?.latitude,
      longitude: _location?.longitude,
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
          if (_notesController.text.trim().isNotEmpty || _stagedDocuments.isNotEmpty) {
            _uploadStagedExtras(next.lead!.id);
          }
        }
        context.pop(next.lead);
      }
    });

    // Editing is only for leads this member created; an admin-allocated lead cannot be edited here even
    // if the page is reached some other way.
    if (widget.isEditing) {
      final detail = ref.watch(leadDetailControllerProvider(widget.leadId!)).lead;
      final currentMemberId = ref.watch(workspaceControllerProvider.select((w) => w.selected?.memberId));
      if (detail != null && !canEditLead(detail, currentMemberId)) {
        return Scaffold(
          appBar: brandAppBar(title: const Text('Edit lead')),
          body: const EmptyStateView(
            icon: Icons.lock_outline,
            message: 'This lead was allocated to you by an admin, so its details cannot be edited here.',
          ),
        );
      }
    }

    return Scaffold(
      appBar: brandAppBar(title: Text(widget.isEditing ? 'Edit lead' : 'New lead')),
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
                  // Location/Documents/Notes only make sense once — on
                  // create. Editing an existing lead has its own real
                  // homes for these (Lead Detail's own Documents section
                  // and activity-feed notes), so this doesn't duplicate
                  // that UI a second time here (same rule
                  // DocumentsSection's own docstring states).
                  if (!widget.isEditing) ...[
                    const SizedBox(height: AppSpacing.md),
                    CollapsibleSection(title: 'Others', children: [_buildOthersSection(context)]),
                  ],
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

  /// Location capture, staged document upload, and a note — all three
  /// only take effect once the lead is actually created (see `_submit`/
  /// `_uploadStagedExtras`): location rides in the same create request
  /// as everything else; documents/notes need the resulting lead id, so
  /// they upload right after, fire-and-forget.
  Widget _buildOthersSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _location != null ? 'Location added' : 'Location service disabled',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (_location != null)
              const Icon(Icons.check_circle, color: AppColors.success, size: 18)
            else if (_locationBusy)
              const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton(onPressed: _grantLocation, child: const Text('Grant')),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _location != null
              ? '${_location!.latitude.toStringAsFixed(5)}, ${_location!.longitude.toStringAsFixed(5)}'
              : _locationMessage ?? 'Please enable location permission',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Documents', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        DashedBorderBox(
          onTap: _pickDocument,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.file_upload_outlined, color: theme.colorScheme.secondary),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Upload Documents',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'Max file size : 25MB',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        if (_stagedDocuments.isNotEmpty)
          for (var i = 0; i < _stagedDocuments.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(_stagedDocuments[i].fileName, overflow: TextOverflow.ellipsis),
              trailing: IconButton(icon: const Icon(Icons.close), tooltip: 'Remove', onPressed: () => _removeDocument(i)),
            ),
        const SizedBox(height: AppSpacing.lg),
        Text('Notes', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _notesController,
          maxLines: 5,
          maxLength: 800,
          decoration: const InputDecoration(hintText: 'Add any notes…', alignLabelWithHint: true),
        ),
      ],
    );
  }
}
