import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../sim/presentation/screens/connected_sim_screen.dart' show formatDetectedAt;
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/call_recording.dart';
import '../providers/call_sync_providers.dart';
import 'recording_player.dart';

/// Lead detail > Call recordings: every recording of this lead's calls, from the first call.
/// Each one is saved to the phone's storage when the section opens, and plays from there.
class LeadRecordingsSection extends ConsumerStatefulWidget {
  const LeadRecordingsSection({super.key, required this.leadId});

  final String leadId;

  @override
  ConsumerState<LeadRecordingsSection> createState() => _LeadRecordingsSectionState();
}

enum _LocalState { saving, saved, failed }

class _LeadRecordingsSectionState extends ConsumerState<LeadRecordingsSection> {
  RecordingPlayer? _player;
  StreamSubscription<bool>? _playingSub;
  String? _playingId;
  final Map<String, _LocalState> _local = {};
  final Map<String, File> _files = {};
  bool _savingAll = false;

  @override
  void dispose() {
    _playingSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  RecordingPlayer _ensurePlayer() {
    final player = _player ??= ref.read(recordingPlayerFactoryProvider)();
    _playingSub ??= player.playing.listen((playing) {
      if (!playing && mounted) setState(() => _playingId = null);
    });
    return player;
  }

  /// Saves every recording to the phone, one at a time (only those not already there).
  Future<void> _saveAll(List<CallRecording> recordings) async {
    if (_savingAll) return;
    _savingAll = true;
    for (final r in recordings) {
      if (!mounted) break;
      // Already saved, saving, or failed (a failed one is retried only when tapped).
      if (_local.containsKey(r.id)) continue;
      await _saveLocal(r);
    }
    _savingAll = false;
  }

  Future<File?> _saveLocal(CallRecording r) async {
    final workspaceId = ref.read(workspaceControllerProvider).selected?.workspace.id;
    if (workspaceId == null) return null;
    setState(() => _local[r.id] = _LocalState.saving);
    try {
      final file = await ref.read(callSyncRepositoryProvider).localRecording(workspaceId, r);
      if (mounted) {
        setState(() {
          _files[r.id] = file;
          _local[r.id] = _LocalState.saved;
        });
      }
      return file;
    } catch (e) {
      AppLogger.warning('Saving a recording to the phone failed: ${e.runtimeType}');
      if (mounted) setState(() => _local[r.id] = _LocalState.failed);
      return null;
    }
  }

  Future<void> _toggle(CallRecording r) async {
    final player = _ensurePlayer();
    if (_playingId == r.id) {
      await player.pause();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    final file = _files[r.id] ?? await _saveLocal(r);
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t load this recording. Check your connection.')));
      }
      return;
    }
    try {
      await player.playFile(file.path);
      if (mounted) setState(() => _playingId = r.id);
    } catch (e) {
      AppLogger.warning('Playing a recording failed: ${e.runtimeType}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This recording can\'t be played on this phone.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final recordings = ref.watch(leadRecordingsProvider(widget.leadId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(icon: Icons.graphic_eq, title: 'Call recordings'),
        recordings.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
          error: (_, _) => ListTile(
            key: const Key('lead-recordings-error'),
            leading: const Icon(Icons.error_outline),
            title: const Text('Couldn\'t load recordings.'),
            trailing: TextButton(onPressed: () => ref.invalidate(leadRecordingsProvider(widget.leadId)), child: const Text('Retry')),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const ListTile(
                key: Key('lead-recordings-empty'),
                leading: Icon(Icons.mic_none),
                title: Text('No call recordings yet.'),
                subtitle: Text('Recordings of synced calls with this lead appear here.'),
              );
            }
            // Save any not yet on the phone (no-op once all are saved/attempted).
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_saveAll(list));
            });
            return Column(
              children: [
                for (var i = 0; i < list.length; i++)
                  _RecordingTile(
                    key: Key('lead-recording-${list[i].id}'),
                    index: i + 1,
                    recording: list[i],
                    playing: _playingId == list[i].id,
                    local: _local[list[i].id],
                    onToggle: () => _toggle(list[i]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    super.key,
    required this.index,
    required this.recording,
    required this.playing,
    required this.local,
    required this.onToggle,
  });

  final int index;
  final CallRecording recording;
  final bool playing;
  final _LocalState? local;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seconds = recording.durationSeconds ?? recording.callDurationSeconds;
    final length = seconds == null ? null : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final inbound = recording.direction == 'inbound';
    final localLabel = switch (local) {
      _LocalState.saving => 'Saving to phone...',
      _LocalState.saved => 'Saved on phone',
      _LocalState.failed => 'Not saved on phone',
      null => null,
    };
    return ListTile(
      leading: IconButton.filledTonal(
        key: Key('lead-recording-play-${recording.id}'),
        onPressed: onToggle,
        icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        tooltip: playing ? 'Pause' : 'Play',
      ),
      title: Text('Call $index · ${formatDetectedAt(context, recording.callStartedAt, DateTime.now())}'),
      subtitle: Text(
        [inbound ? 'Incoming' : 'Outgoing', ?length, ?localLabel].join(' · '),
        style: theme.textTheme.bodySmall?.copyWith(color: local == _LocalState.failed ? AppColors.danger : AppColors.textDim),
      ),
      trailing: Icon(inbound ? Icons.call_received : Icons.call_made, size: 18, color: AppColors.textDim),
    );
  }
}
