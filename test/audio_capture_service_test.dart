import 'package:arcane_voice/src/call/audio_capture_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';

void main() {
  test('voice processing is enabled only for mobile call platforms', () {
    expect(
      AudioCaptureService.supportsVoiceProcessingPlatform(
        TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      AudioCaptureService.supportsVoiceProcessingPlatform(TargetPlatform.iOS),
      isTrue,
    );
    expect(
      AudioCaptureService.supportsVoiceProcessingPlatform(TargetPlatform.macOS),
      isFalse,
    );
    expect(
      AudioCaptureService.supportsVoiceProcessingPlatform(
        TargetPlatform.windows,
      ),
      isFalse,
    );
    expect(
      AudioCaptureService.supportsVoiceProcessingPlatform(TargetPlatform.linux),
      isFalse,
    );
  });

  test('android call config opts into communication capture mode', () {
    RecordConfig config = AudioCaptureService.buildCallRecordConfig(
      sampleRate: 24000,
      platform: TargetPlatform.android,
      useVoiceProcessing: true,
    );

    expect(config.sampleRate, 24000);
    expect(config.numChannels, 1);
    expect(config.echoCancel, isTrue);
    expect(config.autoGain, isTrue);
    expect(
      config.androidConfig.audioSource,
      AndroidAudioSource.voiceCommunication,
    );
    expect(
      config.androidConfig.audioManagerMode,
      AudioManagerMode.modeInCommunication,
    );
  });

  test('ios call config keeps speaker and bluetooth routes available', () {
    RecordConfig config = AudioCaptureService.buildCallRecordConfig(
      sampleRate: 24000,
      platform: TargetPlatform.iOS,
      useVoiceProcessing: true,
    );

    expect(config.echoCancel, isTrue);
    expect(
      config.iosConfig.categoryOptions,
      contains(IosAudioCategoryOption.defaultToSpeaker),
    );
    expect(
      config.iosConfig.categoryOptions,
      contains(IosAudioCategoryOption.allowBluetooth),
    );
    expect(
      config.iosConfig.categoryOptions,
      contains(IosAudioCategoryOption.allowBluetoothA2DP),
    );
  });

  test('fallback call config keeps capture settings minimal', () {
    RecordConfig config = AudioCaptureService.buildFallbackRecordConfig(
      sampleRate: 16000,
    );

    expect(config.sampleRate, 16000);
    expect(config.echoCancel, isFalse);
    expect(config.autoGain, isFalse);
    expect(config.noiseSuppress, isFalse);
    expect(config.androidConfig.audioSource, AndroidAudioSource.defaultSource);
    expect(config.androidConfig.audioManagerMode, AudioManagerMode.modeNormal);
  });
}
