import 'dart:typed_data';

import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/realtime_audio_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

typedef ProxyTurnAudioSink = Future<void> Function(Uint8List audioBytes);
typedef ProxyTurnStartHandler =
    Future<void> Function(ProxySpeechStartEvent event);
typedef ProxyTurnStopHandler =
    Future<void> Function(ProxySpeechStopEvent event);

class ProxySpeechStartEvent {
  final int turnNumber;
  final int startedAtMs;
  final int leadInDurationMs;
  final int bufferedChunkCount;

  const ProxySpeechStartEvent({
    required this.turnNumber,
    required this.startedAtMs,
    required this.leadInDurationMs,
    required this.bufferedChunkCount,
  });
}

class ProxySpeechStopEvent {
  final int turnNumber;
  final int stoppedAtMs;
  final int speechDurationMs;
  final int speechChunkCount;
  final int silenceWindowMs;

  const ProxySpeechStopEvent({
    required this.turnNumber,
    required this.stoppedAtMs,
    required this.speechDurationMs,
    required this.speechChunkCount,
    required this.silenceWindowMs,
  });
}

class ProxyTurnDetector {
  final ProviderSessionRuntime runtime;

  bool speechActive = false;
  int silentDurationMs = 0;
  int loudDurationMs = 0;
  int bufferedSpeechLeadInDurationMs = 0;
  int userTurnCount = 0;
  int currentSpeechDurationMs = 0;
  int currentSpeechChunkCount = 0;
  List<BufferedAudioChunk> bufferedSpeechLeadIn = <BufferedAudioChunk>[];

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

    if (speechActive) {
      await onAppendAudio(audioBytes);
      currentSpeechDurationMs += chunkDurationMs;
      currentSpeechChunkCount++;
      if (rms >= runtime.config.turnDetection.speechThresholdRms) {
        silentDurationMs = 0;
        return;
      }

      silentDurationMs += chunkDurationMs;
      if (silentDurationMs < runtime.config.turnDetection.speechEndSilenceMs) {
        return;
      }

      speechActive = false;
      silentDurationMs = 0;
      loudDurationMs = 0;
      ProxySpeechStopEvent stopEvent = ProxySpeechStopEvent(
        turnNumber: userTurnCount,
        stoppedAtMs: runtime.nowMs,
        speechDurationMs: currentSpeechDurationMs,
        speechChunkCount: currentSpeechChunkCount,
        silenceWindowMs: runtime.config.turnDetection.speechEndSilenceMs,
      );
      info(
        "[${runtime.providerLabel}] user turn #${stopEvent.turnNumber} speech stopped at ${stopEvent.stoppedAtMs}ms "
        "speechDuration=${stopEvent.speechDurationMs}ms chunks=${stopEvent.speechChunkCount} "
        "silenceWindow=${stopEvent.silenceWindowMs}ms",
      );
      await runtime.emitSpeechStopped();
      await onSpeechStopped(stopEvent);
      currentSpeechDurationMs = 0;
      currentSpeechChunkCount = 0;
      return;
    }

    _bufferLeadIn(audioBytes, chunkDurationMs);
    if (rms < runtime.config.turnDetection.speechThresholdRms) {
      loudDurationMs = 0;
      return;
    }

    loudDurationMs += chunkDurationMs;
    if (loudDurationMs < runtime.config.turnDetection.speechStartMs) {
      return;
    }

    speechActive = true;
    userTurnCount++;
    silentDurationMs = 0;
    loudDurationMs = 0;
    currentSpeechDurationMs = bufferedSpeechLeadInDurationMs;
    currentSpeechChunkCount = bufferedSpeechLeadIn.length;
    ProxySpeechStartEvent startEvent = ProxySpeechStartEvent(
      turnNumber: userTurnCount,
      startedAtMs: runtime.nowMs,
      leadInDurationMs: bufferedSpeechLeadInDurationMs,
      bufferedChunkCount: bufferedSpeechLeadIn.length,
    );
    await onSpeechStarted(startEvent);
    info(
      "[${runtime.providerLabel}] user turn #${startEvent.turnNumber} speech started at ${startEvent.startedAtMs}ms "
      "leadIn=${startEvent.leadInDurationMs}ms bufferedChunks=${startEvent.bufferedChunkCount}",
    );
    await runtime.emitSpeechStarted();

    List<BufferedAudioChunk> speechLeadIn = bufferedSpeechLeadIn;
    bufferedSpeechLeadIn = <BufferedAudioChunk>[];
    bufferedSpeechLeadInDurationMs = 0;
    for (BufferedAudioChunk chunk in speechLeadIn) {
      await onAppendAudio(chunk.audioBytes);
    }
  }

  void _bufferLeadIn(Uint8List audioBytes, int chunkDurationMs) {
    bufferedSpeechLeadIn = <BufferedAudioChunk>[
      ...bufferedSpeechLeadIn,
      BufferedAudioChunk(
        audioBytes: Uint8List.fromList(audioBytes),
        durationMs: chunkDurationMs,
      ),
    ];
    bufferedSpeechLeadInDurationMs += chunkDurationMs;
    while (bufferedSpeechLeadInDurationMs >
            runtime.config.turnDetection.preSpeechMs &&
        bufferedSpeechLeadIn.isNotEmpty) {
      BufferedAudioChunk removedChunk = bufferedSpeechLeadIn.first;
      bufferedSpeechLeadIn = bufferedSpeechLeadIn.sublist(1);
      bufferedSpeechLeadInDurationMs -= removedChunk.durationMs;
    }
  }
}
