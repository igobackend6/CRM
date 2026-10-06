import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/message_template.dart';
import '../../domain/entities/message_template_list_state.dart';
import '../providers/whatsapp_providers.dart';

/// Workspace-level CRUD for WhatsApp/CRM message templates (§7) —
/// reachable from the WhatsApp send sheet's "Manage templates" action.
/// Deliberately a single flat list screen, not a generic CMS (§7 "Do
/// not create a generic CMS/template engine").
class MessageTemplatesScreen extends ConsumerStatefulWidget {
  const MessageTemplatesScreen({super.key});

  @override
  ConsumerState<MessageTemplatesScreen> createState() => _MessageTemplatesScreenState();
}

class _MessageTemplatesScreenState extends ConsumerState<MessageTemplatesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(messageTemplateListControllerProvider.notifier).refresh());
  }

  Future<void> _openEditor({MessageTemplate? template}) async {
    final nameController = TextEditingController(text: template?.name ?? '');
    final bodyController = TextEditingController(text: template?.body ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(template == null ? 'New template' : 'Edit template'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: bodyController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  hintText: 'Hello {{name}}, your status is {{status}}...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Variables: {{name}} {{phone}} {{company}} {{status}} {{assigned_member}}', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final name = nameController.text.trim();
    final body = bodyController.text.trim();
    if (name.isEmpty || body.isEmpty) return;

    final controller = ref.read(messageTemplateListControllerProvider.notifier);
    final ok = template == null ? await controller.createTemplate(name: name, body: body) : await controller.updateTemplate(template.id, name: name, body: body);
    if (!mounted) return;
    if (!ok) {
      final message = ref.read(messageTemplateListControllerProvider).errorMessage ?? 'Could not save this template.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(messageTemplateListControllerProvider);
    return Scaffold(
      appBar: brandAppBar(
        title: const Text('Message templates'),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: 'New template', onPressed: () => _openEditor())],
      ),
      body: _body(state),
    );
  }

  Widget _body(MessageTemplateListState state) {
    switch (state.status) {
      case MessageTemplateListStatus.initial:
      case MessageTemplateListStatus.loading:
        return const Center(child: CircularProgressIndicator());

      case MessageTemplateListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load templates.',
          onRetry: () => ref.read(messageTemplateListControllerProvider.notifier).refresh(),
        );

      case MessageTemplateListStatus.empty:
        return const EmptyStateView(icon: Icons.chat_bubble_outline, message: 'No templates yet. Tap + to create one.');

      case MessageTemplateListStatus.success:
        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final template = state.items[index];
            return Card(
              child: ListTile(
                title: Text(template.name),
                subtitle: Text(template.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () => _openEditor(template: template),
              ),
            );
          },
        );
    }
  }
}
