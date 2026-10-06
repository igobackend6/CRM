import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../workspace/presentation/providers/workspace_providers.dart';
import '../../domain/call_recording.dart';
import '../providers/call_sync_providers.dart';
import 'recording_player.dart';

/// The play button on a call's card (like Callyzer's): plays that call's recording, downloading it
/// to this phone the first time. Tap again to pause.
class CallRecordingPlayButton extends ConsumerStatefulWidget {
  const CallRecordingPlayButton({super.key, required this.recording});

  final CallRecording recording;

  @override
  ConsumerState<CallRecordingPlayButton> createState() => _CallRecordingPlayButtonState();
}

class _CallRecordingPlayButtonState extends ConsumerState<CallRecordingPlayButton> {
  RecordingPlayer? _player;
  StreamSubscription<bool>? _sub;
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    final player = _player ??= ref.read(recordingPlayerFactoryProvider)();
    _sub ??= player.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });
    if (_playing) {
      await player.pause();
      return;
    }
    final workspaceId = ref.read(workspaceControllerProvider).selected?.workspace.id;
    if (workspaceId == null) return;
    setState(() => _loading = true);
    try {
      final file = await ref.read(callSyncRepositoryProvider).localRecording(workspaceId, widget.recording);
      await player.playFile(file.path);
    } catch (e) {
      AppLogger.warning('Playing a call recording failed: ${e.runtimeType}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn\'t play this recording. Check your connection.')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: Key('call-recording-play-${widget.recording.callId}'),
      tooltip: _playing ? 'Pause recording' : 'Play recording',
      onPressed: _toggle,
      icon: _loading
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_playing ? Icons.pause_circle_outline : Icons.play_circle_outline, color: Theme.of(context).colorScheme.primary),
    );
  }
}
