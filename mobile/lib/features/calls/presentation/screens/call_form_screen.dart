import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/call_draft.dart';
import '../../domain/entities/call_form_state.dart';
import '../providers/call_providers.dart';
import 'call_list_screen.dart' show formatCallDateTime;

const _directions = ['outbound', 'inbound'];

/// Manual call-log creation (Phase 9 §4) — reachable only from a lead's
/// Calls section (route_paths.dart's callCreateForLead: no lead picker
/// this phase, same minimalism as follow-up creation). Outcomes are
/// loaded from `call_outcomes` (§5), never hardcoded. Duration is
/// entered in whole seconds and left null for a call that never
/// connected (e.g. no answer) — the server derives connected_at/
/// ended_at from it, never a direct write to the generated
/// duration_seconds column (see CallDraft's docstring).
class CallFormScreen extends ConsumerStatefulWidget {
  const CallFormScreen({super.key, this.leadId});

  final String? leadId;

  @override
  ConsumerState<CallFormScreen> createState() => _CallFormScreenState();
}

class _CallFormScreenState extends ConsumerState<CallFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _durationController = TextEditingController();
  String _direction = 'outbound';
  String? _outcomeId;
  DateTime? _startedAt;

  @override
  void dispose() {
    _notesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _pickStartedAt() async {
    final now = DateTime.now();
    final initial = _startedAt ?? now;
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year - 1), lastDate: now);
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;
    setState(() => _startedAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final durationText = _durationController.text.trim();
    final draft = CallDraft(
      direction: _direction,
      outcomeId: _outcomeId,
      startedAt: _startedAt,
      durationSeconds: durationText.isEmpty ? null : int.tryParse(durationText),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );
    ref.read(callFormControllerProvider.notifier).create(widget.leadId!, draft);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.leadId == null) {
      // Defensive: the create route requires a leadId query parameter
      // (route_paths.dart's callCreateForLead) — this only shows if
      // something navigated here without one.
      return Scaffold(
        appBar: AppBar(title: const Text('Log a call')),
        body: const Center(child: Text('Open this from a lead\'s Calls section.')),
      );
    }

    final formState = ref.watch(callFormControllerProvider);
    final outcomesAsync = ref.watch(callOutcomesProvider);

    ref.listen<CallFormState>(callFormControllerProvider, (previous, next) {
      if (next.status == CallFormStatus.success && next.call != null) {
        ref.invalidate(callListControllerProvider);
        ref.invalidate(leadCallsProvider(widget.leadId!));
        context.pop(next.call);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Log a call')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (formState.status == CallFormStatus.error && formState.errorMessage != null) ...[
                AppErrorBanner(message: formState.errorMessage!),
                const SizedBox(height: AppSpacing.md),
              ],
              DropdownButtonFormField<String>(
                initialValue: _direction,
                decoration: const InputDecoration(labelText: 'Direction'),
                items: _directions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                onChanged: (value) => setState(() => _direction = value ?? _direction),
              ),
              const SizedBox(height: AppSpacing.md),
              outcomesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => const Text('Could not load call outcomes.'),
                data: (outcomes) => DropdownButtonFormField<String?>(
                  initialValue: _outcomeId,
                  decoration: const InputDecoration(labelText: 'Outcome'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
                    ...outcomes.map((o) => DropdownMenuItem<String?>(value: o.id, child: Text(o.name))),
                  ],
                  onChanged: (value) => setState(() => _outcomeId = value),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Started'),
                subtitle: Text(_startedAt == null ? 'Now' : formatCallDateTime(_startedAt!)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickStartedAt,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration (seconds)',
                  helperText: 'Leave blank if the call never connected',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: formState.status == CallFormStatus.submitting ? null : _submit,
                child: formState.status == CallFormStatus.submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Log call'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
