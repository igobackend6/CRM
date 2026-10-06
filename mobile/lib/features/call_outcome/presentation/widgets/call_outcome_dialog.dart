import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../custom_fields/domain/entities/custom_field.dart';
import '../../../custom_fields/presentation/providers/custom_field_providers.dart';
import '../../../leads/domain/entities/lead.dart';
import '../../../leads/domain/entities/lead_status.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../leads/presentation/providers/leads_providers.dart';
import '../../../customer360/presentation/providers/customer360_providers.dart' show customerDetailControllerProvider;
import '../../../pipeline/presentation/providers/pipeline_providers.dart';
import '../../domain/interested_in_field.dart';
import '../providers/call_outcome_providers.dart';

/// What the "Interested In" and "Status" dropdowns offer and start on: loaded together so the pop-up
/// opens once, with the lead's current values already selected.
class _OutcomeData {
  const _OutcomeData({required this.lead, required this.statuses, required this.interestedIn});

  final Lead lead;
  final List<LeadStatus> statuses;

  /// Null until the admin creates the "Interested In" field.
  final CustomField? interestedIn;
}

/// The pop-up shown after a call: "Interested In" (the admin's project types) and "Status" (the admin's
/// lead statuses), both dropdowns, with a Submit button. Submitting updates that lead only.
///
/// It cannot be dismissed with a tap outside or the back button: the member records the result first.
/// Both dropdowns start on the lead's current values, so when nothing changed it is one tap to submit.
class CallOutcomeDialog extends ConsumerStatefulWidget {
  const CallOutcomeDialog({super.key, required this.leadId, required this.leadName});

  final String leadId;
  final String leadName;

  @override
  ConsumerState<CallOutcomeDialog> createState() => _CallOutcomeDialogState();
}

class _CallOutcomeDialogState extends ConsumerState<CallOutcomeDialog> {
  _OutcomeData? _data;
  String? _loadError;
  String? _submitError;
  bool _submitting = false;

  String? _statusId;
  String? _interestedInCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _data = null;
      _loadError = null;
    });
    final context = resolveLeadContext(ref.read);
    if (context == null) {
      setState(() => _loadError = 'You are signed out. Please sign in again.');
      return;
    }
    try {
      final repository = ref.read(leadRepositoryProvider);
      final results = await Future.wait<Object?>([
        repository.getLead(accessToken: context.accessToken, workspaceId: context.workspaceId, leadId: widget.leadId),
        repository.listStatuses(accessToken: context.accessToken, workspaceId: context.workspaceId),
        // A workspace with no custom fields (or a failure reading them) must not block recording the status.
        ref.read(workspaceCustomFieldsProvider.future).catchError((Object e) {
          AppLogger.warning('Could not load custom fields for the call pop-up: $e');
          return const <CustomField>[];
        }),
      ]);
      if (!mounted) return;
      final lead = results[0]! as Lead;
      final statuses = (results[1]! as List<LeadStatus>).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final field = findInterestedInField(results[2]! as List<CustomField>);
      setState(() {
        _data = _OutcomeData(lead: lead, statuses: statuses, interestedIn: field);
        _statusId = statuses.any((s) => s.id == lead.status?.id) ? lead.status?.id : null;
        _interestedInCode = field == null ? null : optionForStoredValue(field, lead.customFields[field.code])?.code;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (e) {
      AppLogger.error('Could not load the call outcome pop-up', error: e);
      if (mounted) setState(() => _loadError = 'Could not load this lead. Please try again.');
    }
  }

  Future<void> _submit() async {
    final data = _data;
    final context = resolveLeadContext(ref.read);
    if (data == null || context == null || _statusId == null) return;

    final messenger = ScaffoldMessenger.of(this.context);
    final navigator = Navigator.of(this.context);
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final interested = data.interestedIn;
      await ref.read(leadRepositoryProvider).applyCallOutcome(
            accessToken: context.accessToken,
            workspaceId: context.workspaceId,
            leadId: widget.leadId,
            statusId: _statusId,
            customFields: interested != null && _interestedInCode != null ? {interested.code: _interestedInCode} : null,
          );
      // Every place that shows this lead reloads.
      ref.invalidate(leadListControllerProvider);
      ref.invalidate(customerListControllerProvider);
      ref.invalidate(leadDetailControllerProvider(widget.leadId));
      ref.invalidate(customerDetailControllerProvider(widget.leadId));
      ref.invalidate(pipelineControllerProvider);
      ref.read(pendingCallOutcomeProvider.notifier).state = null;
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('${widget.leadName} updated.')));
    } on AppException catch (e) {
      if (mounted) setState(() => _submitError = e.message);
    } catch (e) {
      AppLogger.error('Could not save the call outcome', error: e);
      if (mounted) setState(() => _submitError = 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Closes without saving: only offered when the lead could not be loaded, so the member is never stuck.
  void _closeWithoutSaving() {
    ref.read(pendingCallOutcomeProvider.notifier).state = null;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('call-outcome-dialog'),
        title: const Text('Call summary'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: _content(theme)),
        ),
        actions: _actions(),
      ),
    );
  }

  Widget _content(ThemeData theme) {
    if (_loadError != null) {
      return Text(_loadError!, style: TextStyle(color: theme.colorScheme.error));
    }
    final data = _data;
    if (data == null) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Center(child: CircularProgressIndicator()));
    }

    final interested = data.interestedIn;
    final interestedOptions = interested?.options ?? const <CustomFieldOption>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.leadName, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textBody)),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: const Key('call-outcome-interested-in'),
          initialValue: _interestedInCode,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Interested In'),
          hint: Text(interestedOptions.isEmpty ? 'No project types added yet' : 'Select'),
          items: [for (final o in interestedOptions) DropdownMenuItem(value: o.code, child: Text(o.label, overflow: TextOverflow.ellipsis))],
          // Disabled until the admin adds the project types.
          onChanged: interestedOptions.isEmpty || _submitting ? null : (value) => setState(() => _interestedInCode = value),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: const Key('call-outcome-status'),
          initialValue: _statusId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Status'),
          hint: Text(data.statuses.isEmpty ? 'No statuses added yet' : 'Select'),
          items: [for (final s in data.statuses) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))],
          onChanged: data.statuses.isEmpty || _submitting ? null : (value) => setState(() => _statusId = value),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_submitError!, key: const Key('call-outcome-error'), style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  List<Widget> _actions() {
    if (_loadError != null) {
      return [
        TextButton(key: const Key('call-outcome-close'), onPressed: _closeWithoutSaving, child: const Text('Close')),
        FilledButton(key: const Key('call-outcome-retry'), onPressed: _load, child: const Text('Retry')),
      ];
    }
    final ready = _data != null && _statusId != null && !_submitting;
    return [
      FilledButton(
        key: const Key('call-outcome-submit'),
        onPressed: ready ? _submit : null,
        child: _submitting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Submit'),
      ),
    ];
  }
}
