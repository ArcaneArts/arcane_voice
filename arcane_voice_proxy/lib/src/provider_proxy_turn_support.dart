import 'dart:typed_data';

export 'package:arcane_voice_proxy/src/provider_speech_activity_support.dart';

import 'package:arcane_voice_proxy/src/provider_speech_activity_support.dart';
import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/realtime_audio_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

typedef ProxyTurnAudioSink = Future<void> Function(Uint8List audioBytes);

class ProxyTurnDetector {
  final ProviderSessionRuntime runtime;
  final SpeechActivityTracker activityTracker = SpeechActivityTracker();
  final SpeechLeadInBuffer leadInBuffer = SpeechLeadInBuffer();

  ProxyTurnDetector({required this.runtime});

  Future<void> processAudio({
    required Uint8List audioBytes,
    required ProxyTurnAudioSink onAppendAudio,
    required ProxyTurnStartHandler onSpeechStarted,
    required ProxyTurnStopHandler onSpeechStopped,
  }) async {
    int rms = Pcm16LevelMeter.computeRms(audioBytes);
    int chunkDurationMs = Pcm16ChunkTiming.chunkDurationMs(
      audioBytes: audioBytes,
      sampleRate: runtime.config.inputSampleRate,
    );

    if (activityTracker.speechActive) {
      await onAppendAudio(audioBytes);
      SpeechActivityUpdate activeUpdate = activityTracker.observe(
        rms: rms,
        chunkDurationMs: chunkDurationMs,
        speechThresholdRms: runtime.config.turnDetection.speechThresholdRms,
        speechStartMs: runtime.config.turnDetection.speechStartMs,
        speechEndSilenceMs: runtime.config.turnDetection.speechEndSilenceMs,
        nowMs: runtime.nowMs,
      );
      ProxySpeechStopEvent? stopEvent = activeUpdate.stopEvent;
      if (stopEvent == null) {
        return;
      }

      info(
        "[${runtime.providerLabel}] user turn #${stopEvent.turnNumber} speech stopped at ${stopEvent.stoppedAtMs}ms "
        "speechDuration=${stopEvent.speechDurationMs}ms chunks=${stopEvent.speechChunkCount} "
        "silenceWindow=${stopEvent.silenceWindowMs}ms",
      );
      await runtime.emitSpeechStopped();
      await onSpeechStopped(stopEvent);
      return;
    }

    leadInBuffer.bufferAudio(
      audioBytes: audioBytes,
      chunkDurationMs: chunkDurationMs,
      maxDurationMs: runtime.config.turnDetection.preSpeechMs,
    );
    SpeechActivityUpdate idleUpdate = activityTracker.observe(
      rms: rms,
      chunkDurationMs: chunkDurationMs,
      speechThresholdRms: runtime.config.turnDetection.speechThresholdRms,
      speechStartMs: runtime.config.turnDetection.speechStartMs,
      speechEndSilenceMs: runtime.config.turnDetection.speechEndSilenceMs,
      nowMs: runtime.nowMs,
      leadInDurationMs: leadInBuffer.bufferedDurationMs,
      bufferedChunkCount: leadInBuffer.bufferedChunkCount,
    );
    ProxySpeechStartEvent? startEvent = idleUpdate.startEvent;
    if (startEvent == null) {
      return;
    }
    await onSpeechStarted(startEvent);
    info(
      "[${runtime.providerLabel}] user turn #${startEvent.turnNumber} speech started at ${startEvent.startedAtMs}ms "
      "leadIn=${startEvent.leadInDurationMs}ms bufferedChunks=${startEvent.bufferedChunkCount}",
    );
    await runtime.emitSpeechStarted();

    List<BufferedAudioChunk> speechLeadIn = leadInBuffer.takeChunks();
    for (BufferedAudioChunk chunk in speechLeadIn) {
      await onAppendAudio(chunk.audioBytes);
    }
  }
}
