import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/app_exception.dart';
import '../../../../core/router/route_paths.dart';
import '../../../leads/presentation/controllers/lead_request_context.dart';
import '../providers/messaging_providers.dart';

/// Minimal "Messages" entry point (Phase 16 §"Lead/Customer entry"),
/// reused unchanged by both Lead Detail and Customer 360 — a customer
/// IS a lead (the same id space), so one widget serves both without a
/// second implementation, same convention as the calls feature's
/// `leadCallsProvider`. Resolves/creates the lead's single conversation
/// on tap, then navigates straight to its detail screen — no inline
/// message preview on the host screen, keeping this a simple entry
/// point rather than a redesign of Lead Detail/Customer 360
/// (§"Do NOT redesign those screens").
class MessagesEntryButton extends ConsumerStatefulWidget {
  const MessagesEntryButton({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<MessagesEntryButton> createState() => _MessagesEntryButtonState();
}

class _MessagesEntryButtonState extends ConsumerState<MessagesEntryButton> {
  bool _opening = false;

  Future<void> _open() async {
    final requestContext = resolveLeadContext(ref.read);
    if (requestContext == null) return;

    setState(() => _opening = true);
    try {
      final repository = ref.read(messagingRepositoryProvider);
      final conversation = await repository.getOrCreateConversation(
        accessToken: requestContext.accessToken,
        workspaceId: requestContext.workspaceId,
        leadId: widget.leadId,
      );
      if (!mounted) return;
      context.push(RoutePaths.messageDetail(conversation.id));
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: _opening
          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.chat_bubble_outline, size: 18),
      label: const Text('Messages'),
      onPressed: _opening ? null : _open,
    );
  }
}
