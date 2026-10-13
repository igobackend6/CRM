import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../custom_fields/domain/entities/custom_field.dart';
import '../../../custom_fields/presentation/providers/custom_field_providers.dart';
import '../../../leads/domain/entities/lead.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../../../leads/presentation/providers/leads_providers.dart';
import '../../../customer360/presentation/providers/customer360_providers.dart' show customerDetailControllerProvider;
import '../../../pipeline/presentation/providers/pipeline_providers.dart';
import '../../../call_sync/presentation/widgets/call_sync_trigger.dart' show refreshHomeData;
import '../../domain/outcome_fields.dart';
import '../providers/call_outcome_providers.dart';

/// What the pop-up shows: the lead (for its current values) and every field the admin defined under
/// CRM Fields. Loaded together so the pop-up opens once, with the current values already filled in.
class _OutcomeData {
  const _OutcomeData({required this.lead, required this.fields});

  final Lead lead;

  /// The admin's CRM fields, in the admin's order. Nothing about them is built into the app, so a field
  /// the admin adds later simply appears here.
  final List<CustomField> fields;
}

/// The pop-up shown after a call. It lists whatever the admin set up under CRM Fields ("Interested In",
/// "Status", and any field added later), each as the right kind of input, and Submit saves them on that
/// lead only.
///
/// It cannot be dismissed with a tap outside or the back button: the member records the result first.
/// Every field starts on the lead's current value, so when nothing changed it is one tap to submit.
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

  /// The value of each field by its code (a String, or a List of option codes for multi-select).
  final Map<String, Object?> _values = {};
  final Map<String, TextEditingController> _texts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
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
      // Always the admin's current fields, never a copy kept from an earlier call.
      final results = await Future.wait<Object?>([
        repository.getLead(accessToken: context.accessToken, workspaceId: context.workspaceId, leadId: widget.leadId),
        ref.refresh(workspaceCustomFieldsProvider.future),
      ]);
      if (!mounted) return;
      final lead = results[0]! as Lead;
      final fields = outcomeFields(results[1]! as List<CustomField>);
      for (final c in _texts.values) {
        c.dispose();
      }
      _texts.clear();
      _values.clear();
      for (final field in fields) {
        final initial = initialOutcomeValue(field, lead.customFields[field.code]);
        _values[field.code] = initial;
        if (field.fieldType != 'options' && field.fieldType != 'multi_options' && field.fieldType != 'date') {
          _texts[field.code] = TextEditingController(text: initial is String ? initial : '');
        }
      }
      setState(() => _data = _OutcomeData(lead: lead, fields: fields));
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
    if (data == null || context == null) return;

    final messenger = ScaffoldMessenger.of(this.context);
    final navigator = Navigator.of(this.context);
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(leadRepositoryProvider).applyCallOutcome(
            accessToken: context.accessToken,
            workspaceId: context.workspaceId,
            leadId: widget.leadId,
            customFields: outcomePayload(data.fields, _values),
          );
      // Every place that shows this lead reloads.
      ref.invalidate(leadListControllerProvider);
      ref.invalidate(customerListControllerProvider);
      ref.invalidate(leadDetailControllerProvider(widget.leadId));
      ref.invalidate(customerDetailControllerProvider(widget.leadId));
      ref.invalidate(pipelineControllerProvider);
      refreshHomeData(ref.invalidate);
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

  /// Closes without saving: only offered when the lead could not be loaded (or there is nothing to
  /// record), so the member is never stuck.
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.leadName, style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textBody)),
        const SizedBox(height: AppSpacing.md),
        if (data.fields.isEmpty)
          Text(
            'No fields have been set up yet. Your admin adds them under CRM Fields.',
            key: const Key('call-outcome-no-fields'),
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textDim),
          ),
        for (final field in data.fields) ...[
          _fieldInput(field),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_submitError != null)
          Text(_submitError!, key: const Key('call-outcome-error'), style: TextStyle(color: theme.colorScheme.error)),
      ],
    );
  }

  String _label(CustomField field) => field.isMandatory ? '${field.name} *' : field.name;

  Widget _fieldInput(CustomField field) {
    final key = Key('call-outcome-field-${field.code}');
    switch (field.fieldType) {
      case 'options':
        final value = _values[field.code] as String?;
        return DropdownButtonFormField<String>(
          key: key,
          initialValue: field.options.any((o) => o.code == value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: _label(field)),
          hint: Text(field.options.isEmpty ? 'No options added yet' : 'Select'),
          items: [for (final o in field.options) DropdownMenuItem(value: o.code, child: Text(o.label, overflow: TextOverflow.ellipsis))],
          onChanged: field.options.isEmpty || _submitting ? null : (v) => setState(() => _values[field.code] = v),
        );
      case 'multi_options':
        final picked = (_values[field.code] as List?)?.cast<String>() ?? const <String>[];
        return Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_label(field), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final o in field.options)
                  FilterChip(
                    label: Text(o.label),
                    selected: picked.contains(o.code),
                    onSelected: _submitting
                        ? null
                        : (on) => setState(
                              () => _values[field.code] = [
                                for (final p in picked)
                                  if (p != o.code) p,
                                if (on) o.code,
                              ],
                            ),
                  ),
              ],
            ),
          ],
        );
      case 'date':
        final value = _values[field.code] as String?;
        return InkWell(
          key: key,
          onTap: _submitting
              ? null
              : () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(value ?? '') ?? now,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (picked != null && mounted) setState(() => _values[field.code] = outcomeDateText(picked));
                },
          child: InputDecorator(
            decoration: InputDecoration(labelText: _label(field), suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
            child: Text(value == null || value.isEmpty ? 'Select a date' : value),
          ),
        );
      default: // text, number
        return TextField(
          key: key,
          controller: _texts[field.code],
          enabled: !_submitting,
          keyboardType: field.fieldType == 'number' ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          decoration: InputDecoration(labelText: _label(field)),
          onChanged: (v) => setState(() => _values[field.code] = v),
        );
    }
  }

  List<Widget> _actions() {
    if (_loadError != null) {
      return [
        TextButton(key: const Key('call-outcome-close'), onPressed: _closeWithoutSaving, child: const Text('Close')),
        FilledButton(key: const Key('call-outcome-retry'), onPressed: _load, child: const Text('Retry')),
      ];
    }
    final data = _data;
    // With no admin fields there is nothing to record: the member can close.
    if (data != null && data.fields.isEmpty) {
      return [TextButton(key: const Key('call-outcome-close'), onPressed: _closeWithoutSaving, child: const Text('Close'))];
    }
    final ready = data != null && outcomeMissingMandatory(data.fields, _values).isEmpty && !_submitting;
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
