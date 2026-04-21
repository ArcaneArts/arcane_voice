import 'dart:typed_data';

import 'package:fast_log/fast_log.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class AudioPlaybackService {
  AudioSource? player;
  SoundHandle? handle;
  int? sampleRate;
  bool initialized = false;
  bool playbackArmed = false;

  bool get hasActivePlayback => handle != null;

  Future<void> ensureInitialized({required int sampleRate}) async {
    if (player != null && this.sampleRate == sampleRate) return;

    if (player != null) {
      await dispose();
    }

    await SoLoud.instance.init();
    AudioSource createdPlayer = SoLoud.instance.setBufferStream(
      maxBufferSizeBytes: 1024 * 1024 * 100,
      bufferingType: BufferingType.preserved,
      bufferingTimeNeeds: 0.12,
      sampleRate: sampleRate,
      channels: Channels.mono,
      format: BufferType.s16le,
      onBuffering: (buffering, currentHandle, time) {
        info(
          "[playback] buffering=$buffering handle=$currentHandle time=$time",
        );
      },
    );

    player = createdPlayer;
    handle = null;
    this.sampleRate = sampleRate;
    initialized = true;
    playbackArmed = true;
  }

  Future<void> addAudio(Uint8List audioBytes) async {
    AudioSource? currentPlayer = player;
    if (currentPlayer == null) return;
    SoLoud.instance.addAudioDataStream(currentPlayer, audioBytes);
    await _ensurePlaybackStarted(currentPlayer);
  }

  Future<void> reset() async {
    AudioSource? currentPlayer = player;
    if (currentPlayer == null) return;
    await _stopCurrentHandle();
    SoLoud.instance.resetBufferStream(currentPlayer);
    playbackArmed = true;
  }

  Future<void> dispose() async {
    await _stopCurrentHandle();
    AudioSource? currentPlayer = player;
    player = null;
    handle = null;
    sampleRate = null;
    if (currentPlayer != null) {
      await SoLoud.instance.disposeSource(currentPlayer);
    }

    if (initialized) {
      SoLoud.instance.deinit();
      initialized = false;
    }
  }

  Future<void> _ensurePlaybackStarted(AudioSource currentPlayer) async {
    if (!playbackArmed) return;

    SoundHandle createdHandle = await SoLoud.instance.play(currentPlayer);
    handle = createdHandle;
    playbackArmed = false;
    info("[playback] started handle=$createdHandle");
  }

  Future<void> _stopCurrentHandle() async {
    SoundHandle? currentHandle = handle;
    handle = null;
    if (currentHandle == null) return;
    if (!SoLoud.instance.getIsValidVoiceHandle(currentHandle)) return;
    await SoLoud.instance.stop(currentHandle);
    info("[playback] stopped handle=$currentHandle");
  }
}
