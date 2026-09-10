import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_list_state.dart';
import '../providers/document_providers.dart';

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  final d = '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  final t = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$d $t';
}

String _formatBytes(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

/// Secure Lead Documents (Phase 21A §2/§3/§4) — the ONE document-
/// management UI shared by Lead Detail and Customer 360 (§4 "Do not
/// create a second document-management UI"), each embedding
/// `DocumentsSection(leadId: ...)` as one more section, same as
/// AI's `LeadAiSection`. Fetches lazily on first build, then supports
/// upload / preview-or-download / delete, with its own loading/empty/
/// error/retry states independent of the rest of the screen.
class DocumentsSection extends ConsumerStatefulWidget {
  const DocumentsSection({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends ConsumerState<DocumentsSection> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final state = ref.read(documentListControllerProvider(widget.leadId));
      if (state.status == DocumentListStatus.initial) {
        ref.read(documentListControllerProvider(widget.leadId).notifier).refresh();
      }
    });
  }

  Future<void> _upload() async {
    await ref.read(documentListControllerProvider(widget.leadId).notifier).pickAndUpload();
    if (!mounted) return;
    final state = ref.read(documentListControllerProvider(widget.leadId));
    if (state.uploadError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.uploadError!)));
    }
  }

  Future<void> _open(Document document) async {
    final ok = await ref.read(documentListControllerProvider(widget.leadId).notifier).openDocument(document.id);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this document.')));
  }

  Future<void> _confirmDelete(Document document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this document?'),
        content: Text('"${document.fileName}" will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(documentListControllerProvider(widget.leadId).notifier).deleteDocument(document.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(documentListControllerProvider(widget.leadId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          icon: Icons.folder_outlined,
          title: 'Documents',
          action: state.uploading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(icon: const Icon(Icons.upload_file_outlined), tooltip: 'Upload document', onPressed: _upload),
        ),
        const SizedBox(height: AppSpacing.sm),
        _body(state),
      ],
    );
  }

  Widget _body(DocumentListState state) {
    switch (state.status) {
      case DocumentListStatus.initial:
      case DocumentListStatus.loading:
        return const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.sm), child: LinearProgressIndicator());

      case DocumentListStatus.error:
        return AppRetryView(
          message: state.errorMessage ?? 'Could not load documents.',
          onRetry: () => ref.read(documentListControllerProvider(widget.leadId).notifier).refresh(),
        );

      case DocumentListStatus.empty:
        return const EmptyStateView(icon: Icons.folder_off_outlined, message: 'No documents yet.');

      case DocumentListStatus.refreshing:
      case DocumentListStatus.success:
      case DocumentListStatus.loadingMore:
        return Column(
          children: [
            ...state.items.map((d) => _DocumentTile(
                  document: d,
                  isDeleting: state.deletingId == d.id,
                  onOpen: () => _open(d),
                  onDelete: () => _confirmDelete(d),
                )),
            if (state.hasMore)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: state.status == DocumentListStatus.loadingMore
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton(
                        onPressed: () => ref.read(documentListControllerProvider(widget.leadId).notifier).loadMore(),
                        child: const Text('Load more'),
                      ),
              ),
          ],
        );
    }
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.document, required this.isDeleting, required this.onOpen, required this.onDelete});

  final Document document;
  final bool isDeleting;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final sizeLabel = _formatBytes(document.sizeBytes);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      leading: const CircleAvatar(radius: 16, child: Icon(Icons.insert_drive_file_outlined, size: 16)),
      title: Text(document.fileName),
      subtitle: Text(
        [
          if (document.uploadedByMember != null) document.uploadedByMember!.fullName ?? 'Unknown',
          if (sizeLabel.isNotEmpty) sizeLabel,
          _formatDateTime(document.createdAt),
        ].join(' • '),
      ),
      trailing: isDeleting
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete', onPressed: onDelete),
    );
  }
}
