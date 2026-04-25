import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:fast_log/fast_log.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

class AudioCaptureService {
  final AudioRecorder recorder;

  StreamSubscription<Uint8List>? subscription;
  AudioSession? audioSession;
  bool callPrepared = false;
  bool audioSessionActive = false;
  bool usingExternalIosAudioSession = false;

  AudioCaptureService({AudioRecorder? recorder})
    : recorder = recorder ?? AudioRecorder();

  Future<bool> hasPermission() => recorder.hasPermission();

  bool get usesVoiceProcessing =>
      !kIsWeb && supportsVoiceProcessingPlatform(defaultTargetPlatform);

  @visibleForTesting
  static bool supportsVoiceProcessingPlatform(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  @visibleForTesting
  static RecordConfig buildCallRecordConfig({
    required int sampleRate,
    required TargetPlatform platform,
    required bool useVoiceProcessing,
  }) => RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: 1,
    bitRate: 128000,
    noiseSuppress: useVoiceProcessing,
    autoGain: useVoiceProcessing,
    echoCancel: useVoiceProcessing,
    androidConfig: platform == TargetPlatform.android
        ? const AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
          )
        : const AndroidRecordConfig(),
    iosConfig: platform == TargetPlatform.iOS
        ? const IosRecordConfig(
            categoryOptions: <IosAudioCategoryOption>[
              IosAudioCategoryOption.defaultToSpeaker,
              IosAudioCategoryOption.allowBluetooth,
              IosAudioCategoryOption.allowBluetoothA2DP,
            ],
          )
        : const IosRecordConfig(),
    streamBufferSize: 2048,
  );

  @visibleForTesting
  static RecordConfig buildFallbackRecordConfig({required int sampleRate}) =>
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        bitRate: 128000,
        streamBufferSize: 2048,
      );

  Future<void> prepareForCall({required int sampleRate}) async {
    if (callPrepared) return;

    if (kIsWeb) {
      callPrepared = true;
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _prepareIosAudioSession();
    }

    callPrepared = true;
    info(
      "[capture] prepared call audio sampleRate=$sampleRate platform=${defaultTargetPlatform.name} voiceProcessing=$usesVoiceProcessing",
    );
  }

  Future<void> start({
    required int sampleRate,
    required void Function(Uint8List audioBytes) onAudio,
  }) async {
    bool permissionGranted = await hasPermission();
    if (!permissionGranted) {
      throw StateError("Microphone permission was denied.");
    }

    await prepareForCall(sampleRate: sampleRate);
    await _logInputDevices();
    await stop();

    RecordConfig config = buildCallRecordConfig(
      sampleRate: sampleRate,
      platform: defaultTargetPlatform,
      useVoiceProcessing: usesVoiceProcessing,
    );
    info(
      "[capture] starting microphone stream sampleRate=$sampleRate voiceProcessing=$usesVoiceProcessing",
    );
    Stream<Uint8List> stream = await _startStreamWithFallback(
      preferredConfig: config,
      sampleRate: sampleRate,
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

  Future<void> teardownCall() async {
    callPrepared = false;
    if (audioSessionActive) {
      try {
        await audioSession?.setActive(false);
      } catch (error) {
        warn("[capture] failed to deactivate iOS audio session: $error");
      }
    }

    audioSessionActive = false;
    audioSession = null;
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        usingExternalIosAudioSession) {
      try {
        await recorder.ios?.manageAudioSession(true);
      } catch (error) {
        warn(
          "[capture] failed to restore recorder-managed iOS session: $error",
        );
      }
    }
    usingExternalIosAudioSession = false;
  }

  Future<void> dispose() async {
    await stop();
    await teardownCall();
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

  Future<void> _prepareIosAudioSession() async {
    try {
      AudioSession session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker |
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.allowBluetoothA2dp,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        ),
      );

      bool activated = await session.setActive(true);
      if (!activated) {
        warn("[capture] iOS audio session activation was declined");
        await recorder.ios?.manageAudioSession(true);
        usingExternalIosAudioSession = false;
        audioSession = null;
        audioSessionActive = false;
        return;
      }

      await recorder.ios?.manageAudioSession(false);
      info("[capture] iOS audio session active in voiceChat mode");
      audioSession = session;
      audioSessionActive = true;
      usingExternalIosAudioSession = true;
    } catch (error) {
      warn(
        "[capture] custom iOS audio session setup failed, falling back to recorder-managed session: $error",
      );
      await recorder.ios?.manageAudioSession(true);
      audioSession = null;
      audioSessionActive = false;
      usingExternalIosAudioSession = false;
    }
  }

  Future<Stream<Uint8List>> _startStreamWithFallback({
    required RecordConfig preferredConfig,
    required int sampleRate,
  }) async {
    try {
      return await recorder.startStream(preferredConfig);
    } catch (error) {
      if (!_shouldRetryWithFallback(preferredConfig)) {
        rethrow;
      }

      warn(
        "[capture] preferred call capture config failed, retrying with fallback config: $error",
      );
      return recorder.startStream(
        buildFallbackRecordConfig(sampleRate: sampleRate),
      );
    }
  }

  bool _shouldRetryWithFallback(RecordConfig preferredConfig) =>
      preferredConfig.echoCancel ||
      preferredConfig.autoGain ||
      preferredConfig.noiseSuppress ||
      preferredConfig.androidConfig.audioSource !=
          AndroidAudioSource.defaultSource ||
      preferredConfig.androidConfig.audioManagerMode !=
          AudioManagerMode.modeNormal;
}
