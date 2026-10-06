import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Plays local recording files. Behind an interface so widget tests don't touch the audio plugin.
abstract class RecordingPlayer {
  /// True while audio is playing.
  Stream<bool> get playing;

  Future<void> playFile(String path);

  Future<void> pause();

  Future<void> dispose();
}

class AudioplayersRecordingPlayer implements RecordingPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<bool> get playing => _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  @override
  Future<void> playFile(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() => _player.dispose();
}
