import 'dart:async';

import 'package:fast_log/fast_log.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioCaptureService {
  final AudioRecorder recorder;

  StreamSubscription<Uint8List>? subscription;

  AudioCaptureService({AudioRecorder? recorder})
    : recorder = recorder ?? AudioRecorder();

  Future<bool> hasPermission() => recorder.hasPermission();

  bool get usesVoiceProcessing =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> start({
    required int sampleRate,
    required void Function(Uint8List audioBytes) onAudio,
  }) async {
    bool permissionGranted = await hasPermission();
    if (!permissionGranted) {
      throw StateError("Microphone permission was denied.");
    }

    await _logInputDevices();
    await stop();

    info(
      "[capture] starting microphone stream sampleRate=$sampleRate voiceProcessing=$usesVoiceProcessing",
    );
    Stream<Uint8List> stream = await recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        bitRate: 128000,
        noiseSuppress: usesVoiceProcessing,
        autoGain: usesVoiceProcessing,
        echoCancel: usesVoiceProcessing,
        streamBufferSize: 2048,
      ),
    );
    subscription = stream.listen(onAudio);
  }

  Future<void> pause() => recorder.pause();

  Future<void> resume() => recorder.resume();

  Future<void> stop() async {
    StreamSubscription<Uint8List>? currentSubscription = subscription;
    subscription = null;
    await currentSubscription?.cancel();
    try {
      await recorder.cancel();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await recorder.dispose();
  }

  Future<void> _logInputDevices() async {
    try {
      List<InputDevice> devices = await recorder.listInputDevices();
      if (devices.isEmpty) {
        warn("[capture] no input devices reported by recorder");
        return;
      }

      String labels = devices.map((device) => device.label).join(", ");
      info("[capture] available input devices: $labels");
    } catch (error) {
      warn("[capture] failed to list input devices: $error");
    }
  }
}
