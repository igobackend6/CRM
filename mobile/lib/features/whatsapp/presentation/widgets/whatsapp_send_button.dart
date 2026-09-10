import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/message_template.dart';
import '../../domain/entities/message_template_list_state.dart';
import '../../domain/entities/template_variables.dart';
import '../../domain/message_template_renderer.dart';
import '../../domain/phone_number_normalizer.dart';
import '../../domain/whatsapp_message_service.dart';
import '../providers/whatsapp_providers.dart';

/// §6's entry point — "Lead Detail -> WhatsApp button -> Template/
/// message selection -> Preview/edit -> User confirms -> Open
/// WhatsApp". Embedded next to the existing MessagesEntryButton on
/// Lead Detail/Customer 360, not a new screen of its own.
class WhatsAppSendButton extends StatelessWidget {
  const WhatsAppSendButton({super.key, required this.leadName, this.leadPhone, this.leadStatus, this.assignedMemberName});

  final String leadName;
  final String? leadPhone;
  final String? leadStatus;
  final String? assignedMemberName;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.chat_outlined),
      label: const Text('WhatsApp'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => WhatsAppSendSheet(leadName: leadName, leadPhone: leadPhone, leadStatus: leadStatus, assignedMemberName: assignedMemberName),
      ),
    );
  }
}

MessageTemplate? _templateById(List<MessageTemplate> templates, String? id) {
  for (final template in templates) {
    if (template.id == id) return template;
  }
  return null;
}

class WhatsAppSendSheet extends ConsumerStatefulWidget {
  const WhatsAppSendSheet({super.key, required this.leadName, this.leadPhone, this.leadStatus, this.assignedMemberName});

  final String leadName;
  final String? leadPhone;
  final String? leadStatus;
  final String? assignedMemberName;

  @override
  ConsumerState<WhatsAppSendSheet> createState() => _WhatsAppSendSheetState();
}

class _WhatsAppSendSheetState extends ConsumerState<WhatsAppSendSheet> {
  final _messageController = TextEditingController();
  String? _selectedTemplateId;
  bool _sending = false;

  TemplateVariables get _variables => TemplateVariables(
        name: widget.leadName,
        phone: widget.leadPhone,
        status: widget.leadStatus,
        assignedMember: widget.assignedMemberName,
        // "company" isn't a field this CRM's lead model has
        // (leads/domain/entities/lead.dart) — left unset rather than
        // mismapped onto an unrelated field; a template using
        // {{company}} renders it as an empty string, same as any other
        // variable with no value for this lead (see TemplateVariables).
      );

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final state = ref.read(messageTemplateListControllerProvider);
      if (state.status == MessageTemplateListStatus.initial) {
        ref.read(messageTemplateListControllerProvider.notifier).refresh();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _applyTemplate(MessageTemplate? template) {
    setState(() {
      _selectedTemplateId = template?.id;
      _messageController.text = template == null ? '' : renderMessageTemplate(template.body, _variables);
    });
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final service = ref.read(whatsAppMessageServiceProvider);
    final result = await service.send(rawPhone: widget.leadPhone, message: _messageController.text.trim());
    if (!mounted) return;
    setState(() => _sending = false);

    switch (result.outcome) {
      case WhatsAppSendOutcome.launched:
        Navigator.of(context).pop();
        break;
      case WhatsAppSendOutcome.invalidPhone:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This lead has no valid phone number for WhatsApp.')));
        break;
      case WhatsAppSendOutcome.unavailable:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open WhatsApp on this device.')));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final phoneIsValid = normalizePhoneForWhatsApp(widget.leadPhone).isValid;
    final templatesState = ref.watch(messageTemplateListControllerProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Send WhatsApp message', style: Theme.of(context).textTheme.titleMedium)),
              TextButton(
                onPressed: () => context.push(RoutePaths.messageTemplates),
                child: const Text('Manage templates'),
              ),
            ],
          ),
          if (!phoneIsValid) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'This lead has no valid phone number for WhatsApp.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (templatesState.items.isNotEmpty)
            DropdownButtonFormField<String?>(
              initialValue: _selectedTemplateId,
              decoration: const InputDecoration(labelText: 'Template', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Custom message')),
                ...templatesState.items.map((t) => DropdownMenuItem<String?>(value: t.id, child: Text(t.name))),
              ],
              onChanged: (id) => _applyTemplate(_templateById(templatesState.items, id)),
            ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _messageController,
            maxLines: 5,
            minLines: 3,
            decoration: const InputDecoration(labelText: 'Message', hintText: 'Type or pick a template above', border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _messageController,
              builder: (context, value, _) => FilledButton.icon(
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined),
                label: const Text('Open WhatsApp'),
                onPressed: (!phoneIsValid || _sending || value.text.trim().isEmpty) ? null : _send,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
