import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../domain/entities/workspace.dart';
import '../../domain/entities/workspace_state.dart';
import '../providers/workspace_providers.dart';

/// Reached only when there's a real decision to show (Phase 4 §7/§10 —
/// a single workspace is auto-selected without ever landing here).
class WorkspaceSelectionScreen extends ConsumerWidget {
  const WorkspaceSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceControllerProvider);

    return Scaffold(
      appBar: brandAppBar(
        title: const Text('Select Workspace'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: switch (state.status) {
        WorkspaceStatus.loading => const Center(child: CircularProgressIndicator()),
        WorkspaceStatus.error => _MessageView(
            message: state.errorMessage ?? 'Something went wrong.',
            icon: Icons.error_outline,
          ),
        WorkspaceStatus.none => const _MessageView(
            message: 'No workspace is available for your account.\nPlease contact your administrator.',
            icon: Icons.domain_disabled_outlined,
          ),
        WorkspaceStatus.needsSelection || WorkspaceStatus.selected => _WorkspaceList(
            memberships: state.memberships,
            selectedId: state.selected?.workspace.id,
          ),
      },
    );
  }
}

class _WorkspaceList extends ConsumerWidget {
  const _WorkspaceList({required this.memberships, required this.selectedId});

  final List<WorkspaceMembership> memberships;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: memberships.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final membership = memberships[index];
        final isSelected = membership.workspace.id == selectedId;
        return Card(
          child: ListTile(
            leading: InitialsAvatar(name: membership.workspace.name),
            title: Text(membership.workspace.name),
            subtitle: Text(membership.roleName),
            trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.secondary) : null,
            onTap: () => ref.read(workspaceControllerProvider.notifier).select(membership),
          ),
        );
      },
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
