import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';

class OpenAiRealtimeSession implements RealtimeProviderSession {
  static const int audioLogInterval = 100;

  final String apiKey;
  final RealtimeSessionConfig config;
  final ProxyToolRegistry toolRegistry;
  late final ProviderSessionRuntime runtime;
  late final ProviderToolExecutionBridge toolExecutionBridge;
  late final AssistantOutputLifecycle assistantOutput;
  late final ProxyTurnDetector turnDetector;
  late final ProviderJsonSocketConnection connection;

  bool sessionStarted = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  bool responseActive = false;
  int lastCommitAtMs = -1;
  bool initialGreetingTriggered = false;

  OpenAiRealtimeSession({
    required this.apiKey,
    required this.config,
    required this.toolRegistry,
    required Future<void> Function(RealtimeServerMessage payload) onJsonEvent,
    required Future<void> Function(Uint8List audioBytes) onAudioChunk,
    required Future<void> Function() onClosed,
    Future<void> Function(ArcaneVoiceProxyUsage usage)? onUsage,
    Future<void> Function(
      ToolExecutionResult result,
      String rawArguments,
      DateTime startedAt,
      DateTime completedAt,
    )?
    onToolExecuted,
  }) {
    runtime = ProviderSessionRuntime(
      providerId: RealtimeProviderCatalog.openAiId,
      providerLabel: "openai",
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: onJsonEvent,
      onAudioChunk: onAudioChunk,
      onClosed: onClosed,
      onUsage: onUsage,
      onToolExecuted: onToolExecuted,
    );
    toolExecutionBridge = ProviderToolExecutionBridge(runtime: runtime);
    assistantOutput = AssistantOutputLifecycle(runtime: runtime);
    turnDetector = ProxyTurnDetector(runtime: runtime);
    connection = ProviderJsonSocketConnection(providerLabel: "openai");
  }

  @override
  Future<void> start() async {
    info("[openai] connecting realtime websocket model=${config.model}");
    runtime.startDebugClock();
    runtime.logTurnDebug();
    await runtime.emitConnecting();

    Uri uri = Uri.parse(
      "wss://api.openai.com/v1/realtime?model=${Uri.encodeQueryComponent(config.model)}",
    );
    await connection.connect(
      url: uri.toString(),
      headers: <String, Object>{
        "Authorization": "Bearer $apiKey",
        "OpenAI-Beta": "realtime=v1",
      },
      onMessage: _handleProviderMessage,
      onDone: _handleProviderDone,
      onError: _handleProviderError,
    );

    info("[openai] websocket connected");
    await _sendProviderEvent(<String, Object?>{
      "type": "session.update",
      "session": _buildSessionUpdate(),
    });
    info("[openai] session.update sent");
  }

  @override
  Future<void> sendAudio(Uint8List audioBytes) async {
    if (connection.isClosed) return;
    upstreamAudioChunkCount++;
    if (upstreamAudioChunkCount <= 5 ||
        upstreamAudioChunkCount % audioLogInterval == 0) {
      info(
        "[openai] upstream audio chunk #$upstreamAudioChunkCount (${audioBytes.length} bytes)",
      );
    }
    await turnDetector.processAudio(
      audioBytes: audioBytes,
      onAppendAudio: _appendAudioChunk,
      onSpeechStarted: _handleSpeechStarted,
      onSpeechStopped: _handleSpeechStopped,
    );
  }

  @override
  Future<void> sendText(String text) async {
    if (connection.isClosed) return;
    info("[openai] sending text input: $text");

    await _sendProviderEvent(<String, Object?>{
      "type": "conversation.item.create",
      "item": <String, Object?>{
        "type": "message",
        "role": "user",
        "content": <Map<String, Object?>>[
          <String, Object?>{"type": "input_text", "text": text},
        ],
      },
    });

    await _sendProviderEvent(<String, Object?>{
      "type": "response.create",
      "response": <String, Object?>{
        "modalities": <String>["audio", "text"],
      },
    });
  }

  @override
  Future<void> interrupt() =>
      _sendProviderEvent(<String, Object?>{"type": "response.cancel"});

  @override
  Future<void> close() async {
    await connection.close(closeMessage: "closing realtime session");
  }

  Future<void> _handleProviderMessage(dynamic message) async {
    Map<String, Object?>? event = decodeProviderJsonMessage(message);
    if (event == null) return;
    String type = event["type"]?.toString() ?? "";
    _logProviderEvent(type, event);

    if (type == "session.created") {
      return;
    }

    if (type == "session.updated") {
      await _announceSessionStarted();
      return;
    }

    if (type == "response.created") {
      responseActive = true;
      assistantOutput.reset();
      info("[openai] response created at ${runtime.nowMs}ms");
      return;
    }

    if (type == "response.done") {
      await _emitUsageFromResponseDone(event);
      responseActive = false;
      if (assistantOutput.isActive) {
        await assistantOutput.completeAndNotify(reason: "response.done");
      } else {
        info("[openai] response done without assistant output");
      }
      return;
    }

    if (type == "input_audio_buffer.speech_started") {
      info("[openai] speech started");
      return;
    }

    if (type == "input_audio_buffer.speech_stopped") {
      info("[openai] speech stopped");
      return;
    }

    if (type == "response.output_audio.delta" ||
        type == "response.audio.delta") {
      String delta = event["delta"]?.toString() ?? "";
      if (delta.isEmpty) return;
      await assistantOutput.ensureStarted(
        trigger: "audio",
        referenceAtMs: lastCommitAtMs,
      );
      downstreamAudioChunkCount++;
      assistantOutput.recordAudioChunk();
      if (downstreamAudioChunkCount == 1 ||
          downstreamAudioChunkCount % audioLogInterval == 0) {
        info("[openai] downstream audio chunk #$downstreamAudioChunkCount");
      }
      await runtime.emitAudio(base64Decode(delta));
      return;
    }

    if (type == "response.output_audio_transcript.delta" ||
        type == "response.audio_transcript.delta") {
      await assistantOutput.ensureStarted(
        trigger: "transcript",
        referenceAtMs: lastCommitAtMs,
      );
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "response.output_audio_transcript.done" ||
        type == "response.audio_transcript.done") {
      await assistantOutput.ensureStarted(
        trigger: "transcript.final",
        referenceAtMs: lastCommitAtMs,
      );
      info("[openai] assistant transcript final");
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantFinalEvent(
          text: event["transcript"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "conversation.item.input_audio_transcription.delta") {
      await runtime.onJsonEvent(
        RealtimeTranscriptUserDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "conversation.item.input_audio_transcription.completed") {
      info("[openai] user transcript final");
      await runtime.onJsonEvent(
        RealtimeTranscriptUserFinalEvent(
          text: event["transcript"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "response.function_call_arguments.done") {
      info("[openai] tool call received");
      await _handleToolCall(event);
      return;
    }

    if (type == "response.output_text.delta") {
      await assistantOutput.ensureStarted(
        trigger: "text",
        referenceAtMs: lastCommitAtMs,
      );
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "response.output_text.done") {
      await assistantOutput.ensureStarted(
        trigger: "text.final",
        referenceAtMs: lastCommitAtMs,
      );
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantFinalEvent(
          text: event["text"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "error") {
      await _handleProviderErrorMessage(event);
    }
  }

  Future<void> _handleToolCall(Map<String, Object?> event) async {
    await toolExecutionBridge.executeJsonToolCall(
      providerLabel: "openai",
      callId: event["call_id"]?.toString(),
      name: event["name"]?.toString(),
      rawArguments: event["arguments"]?.toString() ?? "{}",
      onResult: (ToolExecutionResult output) async {
        await _sendProviderEvent(<String, Object?>{
          "type": "conversation.item.create",
          "item": <String, Object?>{
            "type": "function_call_output",
            "call_id": output.callId,
            "output": output.outputJson,
          },
        });

        await _sendProviderEvent(<String, Object?>{"type": "response.create"});
      },
    );
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    await emitProviderErrorFromEvent(
      runtime: runtime,
      providerLabel: "openai",
      event: event,
      defaultMessage: "OpenAI realtime error",
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    info("[openai] session updated and ready");
    await runtime.emitSessionStarted();
    await _sendInitialGreetingIfNeeded();
  }

  Future<void> _sendInitialGreetingIfNeeded() async {
    if (initialGreetingTriggered || !config.hasInitialGreeting) {
      return;
    }
    initialGreetingTriggered = true;
    info("[openai] sending initial greeting prompt");
    await _sendProviderEvent(<String, Object?>{
      "type": "response.create",
      "response": <String, Object?>{
        "modalities": <String>["audio", "text"],
        "instructions": config.normalizedInitialGreeting,
      },
    });
  }

  Future<void> _handleProviderDone() async {
    responseActive = false;
    assistantOutput.logFinished(reason: "socket.done");
    info(
      "[openai] websocket done code=${connection.closeCode} reason=${connection.closeReason}",
    );
    await close();
    await runtime.notifyClosed();
  }

  Future<void> _handleProviderError(Object error) async {
    responseActive = false;
    assistantOutput.logFinished(reason: "socket.error");
    warning("[openai] websocket error: $error");
    await runtime.emitError(message: error.toString());
    await close();
    await runtime.notifyClosed();
  }

  Future<void> _sendProviderEvent(Map<String, Object?> payload) async {
    await connection.sendJson(payload);
  }

  Future<void> _emitUsageFromResponseDone(Map<String, Object?> event) async {
    ArcaneVoiceProxyUsage? usage = _parseOpenAiUsage(
      provider: RealtimeProviderCatalog.openAiId,
      event: event,
    );
    if (usage == null) {
      return;
    }
    await runtime.emitUsage(usage);
  }

  Map<String, Object?> _buildSessionUpdate() => <String, Object?>{
    "instructions": config.instructions,
    "modalities": <String>["audio", "text"],
    "voice": config.voice,
    "input_audio_format": "pcm16",
    "output_audio_format": "pcm16",
    "input_audio_transcription": <String, Object?>{
      "model": "gpt-4o-mini-transcribe",
    },
    "turn_detection": null,
    if (toolRegistry.hasTools) "tool_choice": "auto",
    if (toolRegistry.hasTools) "tools": toolRegistry.openAiTools,
  };

  void _logProviderEvent(String type, Map<String, Object?> event) {
    if (_isStreamingDeltaEvent(type)) return;

    if (type == "session.created" || type == "session.updated") {
      info("[openai] event $type");
      return;
    }

    verbose("[openai] event $type ${jsonEncode(event)}");
  }

  bool _isStreamingDeltaEvent(String type) => type.endsWith(".delta");

  Future<void> _handleSpeechStarted(ProxySpeechStartEvent event) async {
    if (responseActive && config.turnDetection.bargeInEnabled) {
      info("[openai] cancelling active response for new user speech");
      responseActive = false;
      assistantOutput.logFinished(reason: "barge-in");
      await interrupt();
    }
  }

  Future<void> _handleSpeechStopped(ProxySpeechStopEvent event) async {
    lastCommitAtMs = event.stoppedAtMs;
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.commit",
    });
    info("[openai] user turn #${event.turnNumber} response.create sent");
    await _sendProviderEvent(<String, Object?>{
      "type": "response.create",
      "response": <String, Object?>{
        "modalities": <String>["audio", "text"],
      },
    });
  }

  Future<void> _appendAudioChunk(Uint8List audioBytes) async {
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.append",
      "audio": base64Encode(audioBytes),
    });
  }

  ArcaneVoiceProxyUsage? _parseOpenAiUsage({
    required String provider,
    required Map<String, Object?> event,
  }) {
    Map<String, Object?>? response = _castObjectMap(event["response"]);
    Map<String, Object?>? usage = _castObjectMap(
      response?["usage"] ?? event["usage"],
    );
    if (usage == null) {
      return null;
    }

    Map<String, Object?> inputDetails =
        _castObjectMap(usage["input_token_details"]) ?? <String, Object?>{};
    Map<String, Object?> outputDetails =
        _castObjectMap(usage["output_token_details"]) ?? <String, Object?>{};
    int? inputTokens = _readInt(usage["input_tokens"]);
    int? outputTokens = _readInt(usage["output_tokens"]);
    int? cachedTextTokens = _readInt(inputDetails["cached_tokens"]);
    int? inputAudioTokens = _readInt(inputDetails["audio_tokens"]);
    int? outputAudioTokens = _readInt(outputDetails["audio_tokens"]);
    int? inputTextTokens =
        _readInt(inputDetails["text_tokens"]) ??
        _subtractNullable(inputTokens, inputAudioTokens);
    int? outputTextTokens =
        _readInt(outputDetails["text_tokens"]) ??
        _subtractNullable(outputTokens, outputAudioTokens);
    return ArcaneVoiceProxyUsage(
      provider: provider,
      inputTextTokens: inputTextTokens,
      outputTextTokens: outputTextTokens,
      cachedTextTokens: cachedTextTokens,
      inputAudioTokens: inputAudioTokens,
      outputAudioTokens: outputAudioTokens,
      totalTokens: _readInt(usage["total_tokens"]),
      raw: usage,
    );
  }

  Map<String, Object?>? _castObjectMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.cast<String, Object?>();
    }
    if (value is Map<String, Object?>) {
      return value;
    }
    return null;
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? "");
  }

  int? _subtractNullable(int? total, int? partial) {
    if (total == null && partial == null) {
      return null;
    }
    return (total ?? 0) - (partial ?? 0);
  }
}
