import 'dart:typed_data';

import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/realtime_audio_support.dart';

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

class SpeechActivityUpdate {
  final ProxySpeechStartEvent? startEvent;
  final ProxySpeechStopEvent? stopEvent;

  const SpeechActivityUpdate({this.startEvent, this.stopEvent});

  static const SpeechActivityUpdate idle = SpeechActivityUpdate();
}

class SpeechActivityTracker {
  bool speechActive = false;
  int userTurnCount = 0;
  int loudDurationMs = 0;
  int silentDurationMs = 0;
  int currentSpeechDurationMs = 0;
  int currentSpeechChunkCount = 0;

  SpeechActivityUpdate observe({
    required int rms,
    required int chunkDurationMs,
    required int speechThresholdRms,
    required int speechStartMs,
    required int speechEndSilenceMs,
    required int nowMs,
    int leadInDurationMs = 0,
    int bufferedChunkCount = 0,
  }) {
    if (speechActive) {
      currentSpeechDurationMs += chunkDurationMs;
      currentSpeechChunkCount++;
      if (rms >= speechThresholdRms) {
        silentDurationMs = 0;
        return SpeechActivityUpdate.idle;
      }

      silentDurationMs += chunkDurationMs;
      if (silentDurationMs < speechEndSilenceMs) {
        return SpeechActivityUpdate.idle;
      }

      speechActive = false;
      loudDurationMs = 0;
      silentDurationMs = 0;
      ProxySpeechStopEvent stopEvent = ProxySpeechStopEvent(
        turnNumber: userTurnCount,
        stoppedAtMs: nowMs,
        speechDurationMs: currentSpeechDurationMs,
        speechChunkCount: currentSpeechChunkCount,
        silenceWindowMs: speechEndSilenceMs,
      );
      currentSpeechDurationMs = 0;
      currentSpeechChunkCount = 0;
      return SpeechActivityUpdate(stopEvent: stopEvent);
    }

    if (rms < speechThresholdRms) {
      loudDurationMs = 0;
      return SpeechActivityUpdate.idle;
    }

    loudDurationMs += chunkDurationMs;
    if (loudDurationMs < speechStartMs) {
      return SpeechActivityUpdate.idle;
    }

    speechActive = true;
    userTurnCount++;
    silentDurationMs = 0;
    loudDurationMs = 0;
    currentSpeechDurationMs = leadInDurationMs;
    currentSpeechChunkCount = bufferedChunkCount;
    ProxySpeechStartEvent startEvent = ProxySpeechStartEvent(
      turnNumber: userTurnCount,
      startedAtMs: nowMs,
      leadInDurationMs: leadInDurationMs,
      bufferedChunkCount: bufferedChunkCount,
    );
    return SpeechActivityUpdate(startEvent: startEvent);
  }
}

class SpeechLeadInBuffer {
  int bufferedDurationMs = 0;
  List<BufferedAudioChunk> bufferedChunks = <BufferedAudioChunk>[];

  void bufferAudio({
    required Uint8List audioBytes,
    required int chunkDurationMs,
    required int maxDurationMs,
  }) {
    bufferedChunks = <BufferedAudioChunk>[
      ...bufferedChunks,
      BufferedAudioChunk(
        audioBytes: Uint8List.fromList(audioBytes),
        durationMs: chunkDurationMs,
      ),
    ];
    bufferedDurationMs += chunkDurationMs;
    while (bufferedDurationMs > maxDurationMs && bufferedChunks.isNotEmpty) {
      BufferedAudioChunk removedChunk = bufferedChunks.first;
      bufferedChunks = bufferedChunks.sublist(1);
      bufferedDurationMs -= removedChunk.durationMs;
    }
  }

  List<BufferedAudioChunk> takeChunks() {
    List<BufferedAudioChunk> currentChunks = bufferedChunks;
    bufferedChunks = <BufferedAudioChunk>[];
    bufferedDurationMs = 0;
    return currentChunks;
  }

  int get bufferedChunkCount => bufferedChunks.length;
}

class PassiveSpeechDetector {
  final ProviderSessionRuntime runtime;
  final SpeechActivityTracker activityTracker = SpeechActivityTracker();

  PassiveSpeechDetector({required this.runtime});

  Future<void> observeAudio({
    required Uint8List audioBytes,
    required ProxyTurnStartHandler onSpeechStarted,
    required ProxyTurnStopHandler onSpeechStopped,
  }) async {
    int rms = Pcm16LevelMeter.computeRms(audioBytes);
    int chunkDurationMs = Pcm16ChunkTiming.chunkDurationMs(
      audioBytes: audioBytes,
      sampleRate: runtime.config.inputSampleRate,
    );
    SpeechActivityUpdate update = activityTracker.observe(
      rms: rms,
      chunkDurationMs: chunkDurationMs,
      speechThresholdRms: runtime.config.turnDetection.speechThresholdRms,
      speechStartMs: runtime.config.turnDetection.speechStartMs,
      speechEndSilenceMs: runtime.config.turnDetection.speechEndSilenceMs,
      nowMs: runtime.nowMs,
    );

    ProxySpeechStartEvent? startEvent = update.startEvent;
    if (startEvent != null) {
      await onSpeechStarted(startEvent);
    }

    ProxySpeechStopEvent? stopEvent = update.stopEvent;
    if (stopEvent != null) {
      await onSpeechStopped(stopEvent);
    }
  }
}
