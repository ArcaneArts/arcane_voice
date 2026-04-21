import 'package:arcane_voice_proxy/src/provider_runtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

class AssistantOutputLifecycle {
  final ProviderSessionRuntime runtime;

  bool outputActive = false;
  int turnCount = 0;
  int startedAtMs = -1;
  int firstAudioAtMs = -1;
  int audioChunkCount = 0;

  AssistantOutputLifecycle({required this.runtime});

  bool get isActive => outputActive;

  Future<void> ensureStarted({
    required String trigger,
    int referenceAtMs = -1,
    String referenceLabel = "commit",
  }) async {
    if (outputActive) {
      return;
    }

    outputActive = true;
    turnCount++;
    startedAtMs = runtime.nowMs;
    firstAudioAtMs = -1;
    audioChunkCount = 0;

    String relation = referenceAtMs < 0
        ? ""
        : " after $referenceLabel ${ProviderDebugTiming.formatLatency(currentMs: startedAtMs, startedAtMs: referenceAtMs)}";
    info(
      "[${runtime.providerLabel}] assistant turn #$turnCount output started via $trigger at ${startedAtMs}ms$relation",
    );
    await runtime.emitResponding();
  }

  void recordAudioChunk() {
    audioChunkCount++;
    if (firstAudioAtMs >= 0) {
      return;
    }

    firstAudioAtMs = runtime.nowMs;
    info(
      "[${runtime.providerLabel}] assistant turn #$turnCount first audio at ${firstAudioAtMs}ms "
      "latency=${ProviderDebugTiming.formatLatency(currentMs: firstAudioAtMs, startedAtMs: startedAtMs)}",
    );
  }

  Future<void> completeAndNotify({
    required String reason,
    String extraMetrics = "",
  }) async {
    if (!outputActive) {
      return;
    }
    logFinished(reason: reason, extraMetrics: extraMetrics);
    await runtime.emitAssistantOutputCompleted(reason: reason);
    await runtime.emitReady();
  }

  void logFinished({required String reason, String extraMetrics = ""}) {
    if (!outputActive || turnCount == 0 || startedAtMs < 0) {
      return;
    }

    int finishedAtMs = runtime.nowMs;
    String responseDuration = ProviderDebugTiming.formatLatency(
      currentMs: finishedAtMs,
      startedAtMs: startedAtMs,
    );
    String firstAudioLatency = firstAudioAtMs < 0
        ? "n/a"
        : ProviderDebugTiming.formatLatency(
            currentMs: firstAudioAtMs,
            startedAtMs: startedAtMs,
          );
    String metricsSuffix = extraMetrics.isEmpty ? "" : " $extraMetrics";
    info(
      "[${runtime.providerLabel}] assistant turn #$turnCount finished via $reason at ${finishedAtMs}ms "
      "duration=$responseDuration firstAudio=$firstAudioLatency audioChunks=$audioChunkCount$metricsSuffix",
    );
    reset();
  }

  void reset() {
    outputActive = false;
    startedAtMs = -1;
    firstAudioAtMs = -1;
    audioChunkCount = 0;
  }
}
