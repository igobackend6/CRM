import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../leads/presentation/providers/leads_providers.dart';
import '../../domain/entities/follow_up_draft.dart';
import '../../domain/entities/follow_up_form_state.dart';
import '../providers/followup_providers.dart';
import 'follow_up_list_screen.dart' show formatFollowUpDateTime;

const _types = ['call', 'meeting', 'task'];
const _statuses = ['pending', 'completed', 'cancelled'];

/// Create Follow-Up (Phase 7 §2C) and Edit/Reschedule (§2D) — same form,
/// mode decided by whether [followUpId] is set. Creation needs [leadId]
/// (there's no lead picker this phase — see route_paths.dart); edit
/// reads the lead from the follow-up already loaded in
/// [followUpDetailControllerProvider] the same way LeadFormScreen
/// prefills from [leadDetailControllerProvider].
class FollowUpFormScreen extends ConsumerStatefulWidget {
  const FollowUpFormScreen({super.key, this.followUpId, this.leadId});

  final String? followUpId;
  final String? leadId;

  bool get isEditing => followUpId != null;

  @override
  ConsumerState<FollowUpFormScreen> createState() => _FollowUpFormScreenState();
}

class _FollowUpFormScreenState extends ConsumerState<FollowUpFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  DateTime? _dueAt;
  String _type = 'task';
  String? _assignedMemberId;
  String _status = 'pending';
  bool _prefilled = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _prefillIfEditing() {
    if (_prefilled || !widget.isEditing) return;
    final detail = ref.read(followUpDetailControllerProvider(widget.followUpId!));
    final followUp = detail.followUp;
    if (followUp == null) return;
    _dueAt = followUp.dueAt;
    _type = followUp.type;
    _notesController.text = followUp.notes ?? '';
    _assignedMemberId = followUp.assignedMember?.id;
    _status = followUp.status;
    _prefilled = true;
  }

  Future<void> _pickDueAt() async {
    final now = DateTime.now();
    final initial = _dueAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;
    setState(() => _dueAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_dueAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a due date and time.')));
      return;
    }
    final draft = FollowUpDraft(
      dueAt: _dueAt!,
      type: _type,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      assignedMemberId: _assignedMemberId,
      status: widget.isEditing ? _status : null,
    );
    final controller = ref.read(followUpFormControllerProvider.notifier);
    if (widget.isEditing) {
      controller.update(widget.followUpId!, draft);
    } else {
      controller.create(widget.leadId!, draft);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditing) {
      _prefillIfEditing();
    } else if (widget.leadId == null) {
      // Defensive: the create route requires a leadId query parameter
      // (route_paths.dart's followUpCreateForLead) — this only shows if
      // something navigated here without one.
      return Scaffold(
        appBar: brandAppBar(title: const Text('New follow-up')),
        body: const Center(child: Text('Open this from a lead\'s follow-ups section.')),
      );
    }

    final formState = ref.watch(followUpFormControllerProvider);
    final membersAsync = ref.watch(workspaceMembersProvider);

    ref.listen<FollowUpFormState>(followUpFormControllerProvider, (previous, next) {
      if (next.status == FollowUpFormStatus.success && next.followUp != null) {
        if (widget.isEditing) {
          ref.invalidate(followUpDetailControllerProvider(widget.followUpId!));
        } else {
          ref.invalidate(followUpListControllerProvider);
          ref.invalidate(leadFollowUpsProvider(widget.leadId!));
        }
        context.pop(next.followUp);
      }
    });

    return Scaffold(
      appBar: brandAppBar(title: Text(widget.isEditing ? 'Edit follow-up' : 'New follow-up')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (formState.status == FollowUpFormStatus.error && formState.errorMessage != null) ...[
                AppErrorBanner(message: formState.errorMessage!),
                const SizedBox(height: AppSpacing.md),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Due'),
                subtitle: Text(_dueAt == null ? 'Not set' : formatFollowUpDateTime(_dueAt!)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickDueAt,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (value) => setState(() => _type = value ?? _type),
              ),
              const SizedBox(height: AppSpacing.md),
              membersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => const Text('Could not load workspace members.'),
                data: (members) => DropdownButtonFormField<String?>(
                  initialValue: _assignedMemberId,
                  decoration: const InputDecoration(labelText: 'Assigned to'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Me (default)')),
                    ...members.map((m) => DropdownMenuItem<String?>(value: m.id, child: Text(m.fullName ?? 'Unknown'))),
                  ],
                  onChanged: (value) => setState(() => _assignedMemberId = value),
                ),
              ),
              if (widget.isEditing) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (value) => setState(() => _status = value ?? _status),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: formState.status == FollowUpFormStatus.submitting ? null : _submit,
                child: formState.status == FollowUpFormStatus.submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.isEditing ? 'Save changes' : 'Create follow-up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
