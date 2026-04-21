import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/proxy_session_support.dart';
import 'package:arcane_voice_proxy/src/realtime_provider_session_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';
import 'package:arcane_voice_proxy/src/server_tool_support.dart';

class ProviderSessionRuntime {
  final String providerId;
  final String providerLabel;
  final RealtimeSessionConfig config;
  final ProxyToolRegistry toolRegistry;
  final Future<void> Function(RealtimeServerMessage payload) onJsonEvent;
  final Future<void> Function(Uint8List audioBytes) onAudioChunk;
  final Future<void> Function() onClosed;
  final Future<void> Function(ArcaneVoiceProxyUsage usage)? onUsage;
  final Future<void> Function(
    ToolExecutionResult result,
    String rawArguments,
    DateTime startedAt,
    DateTime completedAt,
  )?
  onToolExecuted;
  final Stopwatch debugClock = Stopwatch();

  ProviderSessionRuntime({
    required this.providerId,
    required this.providerLabel,
    required this.config,
    required this.toolRegistry,
    required this.onJsonEvent,
    required this.onAudioChunk,
    required this.onClosed,
    this.onUsage,
    this.onToolExecuted,
  });

  int get nowMs => debugClock.elapsedMilliseconds;

  void startDebugClock() {
    debugClock
      ..reset()
      ..start();
  }

  void logTurnDebug() {
    info(
      "[$providerLabel] turn debug threshold=${config.turnDetection.speechThresholdRms} "
      "startMs=${config.turnDetection.speechStartMs} endSilenceMs=${config.turnDetection.speechEndSilenceMs} "
      "preSpeechMs=${config.turnDetection.preSpeechMs} bargeIn=${config.turnDetection.bargeInEnabled}",
    );
  }

  Future<void> emitConnecting() => onJsonEvent(
    RealtimeSessionStateEvent(state: "connecting", provider: providerId),
  );

  Future<void> emitSessionStarted({
    int? inputSampleRate,
    int? outputSampleRate,
  }) async {
    await onJsonEvent(
      RealtimeSessionStartedEvent(
        provider: providerId,
        model: config.model,
        voice: config.voice,
        inputSampleRate: inputSampleRate ?? config.inputSampleRate,
        outputSampleRate: outputSampleRate ?? config.outputSampleRate,
      ),
    );
    await emitReady();
  }

  Future<void> emitReady() =>
      onJsonEvent(const RealtimeSessionStateEvent(state: "ready"));

  Future<void> emitResponding() =>
      onJsonEvent(const RealtimeSessionStateEvent(state: "responding"));

  Future<void> emitSpeechStarted() =>
      onJsonEvent(const RealtimeInputSpeechStartedEvent());

  Future<void> emitSpeechStopped() =>
      onJsonEvent(const RealtimeInputSpeechStoppedEvent());

  Future<void> emitAssistantOutputCompleted({required String reason}) =>
      onJsonEvent(RealtimeAssistantOutputCompletedEvent(reason: reason));

  Future<void> emitError({required String message, String? code}) =>
      onJsonEvent(RealtimeErrorEvent(message: message, code: code));

  Future<void> emitAudio(Uint8List audioBytes) => onAudioChunk(audioBytes);

  Future<void> emitUsage(ArcaneVoiceProxyUsage usage) async {
    if (onUsage == null) {
      return;
    }
    await onUsage!(usage);
  }

  Future<void> notifyToolExecuted({
    required ToolExecutionResult result,
    required String rawArguments,
    required DateTime startedAt,
    required DateTime completedAt,
  }) async {
    if (onToolExecuted == null) {
      return;
    }
    await onToolExecuted!(result, rawArguments, startedAt, completedAt);
  }

  Future<void> notifyClosed() => onClosed();
}

class ProviderDebugTiming {
  const ProviderDebugTiming._();

  static String formatLatency({
    required int currentMs,
    required int startedAtMs,
  }) {
    if (startedAtMs < 0) {
      return "n/a";
    }
    return "${currentMs - startedAtMs}ms";
  }
}
