import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/provider_vad_mode_support.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

class GrokVoiceSession implements RealtimeProviderSession {
  static const int audioLogInterval = 25;

  final String apiKey;
  final RealtimeSessionConfig config;
  final ArcaneVoiceProxyVadMode vadMode;
  final ProxyToolRegistry toolRegistry;
  late final ProviderSessionRuntime runtime;
  late final ProviderToolExecutionBridge toolExecutionBridge;
  late final AssistantOutputLifecycle assistantOutput;
  late final ProxyTurnDetector turnDetector;
  late final ProviderJsonSocketConnection connection;
  final MonotonicTranscriptBuffer userTranscriptBuffer =
      MonotonicTranscriptBuffer();

  bool sessionStarted = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  bool responseActive = false;
  bool audioBufferedForCurrentTurn = false;
  bool initialGreetingTriggered = false;
  bool providerSpeechActive = false;

  GrokVoiceSession({
    required this.apiKey,
    required this.config,
    required this.vadMode,
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
      providerId: RealtimeProviderCatalog.grokId,
      providerLabel: "grok",
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
    connection = ProviderJsonSocketConnection(providerLabel: "grok");
  }

  @override
  Future<void> start() async {
    info("[grok] connecting realtime websocket model=${config.model}");
    runtime.startDebugClock();
    runtime.logTurnDebug();
    await runtime.emitConnecting();

    Uri uri = Uri.parse("wss://api.x.ai/v1/realtime");
    await connection.connect(
      url: uri.toString(),
      headers: <String, Object>{"Authorization": "Bearer $apiKey"},
      onMessage: _handleProviderMessage,
      onDone: _handleProviderDone,
      onError: _handleProviderError,
    );

    info("[grok] websocket connected");
    await _sendProviderEvent(<String, Object?>{
      "type": "session.update",
      "session": _buildSessionUpdate(),
    });
    info("[grok] session.update sent");
  }

  @override
  Future<void> sendAudio(Uint8List audioBytes) async {
    if (connection.isClosed) return;

    upstreamAudioChunkCount++;
    if (upstreamAudioChunkCount <= 5 ||
        upstreamAudioChunkCount % audioLogInterval == 0) {
      info(
        "[grok] upstream audio chunk #$upstreamAudioChunkCount (${audioBytes.length} bytes)",
      );
    }
    if (_usesProviderVad) {
      await _appendAudioChunk(audioBytes);
      return;
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
    info("[grok] sending text input: $text");

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

    await _sendProviderEvent(<String, Object?>{"type": "response.create"});
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

    if (type == "session.created" || type == "conversation.created") {
      return;
    }

    if (type == "session.updated") {
      await _announceSessionStarted();
      return;
    }

    if (type == "response.created") {
      responseActive = true;
      await _flushPendingUserTranscript();
      assistantOutput.reset();
      info("[grok] response created");
      return;
    }

    if (type == "response.done") {
      await _emitUsageFromResponseDone(event);
      responseActive = false;
      await _flushPendingUserTranscript();
      info("[grok] response done");
      if (assistantOutput.isActive) {
        await assistantOutput.completeAndNotify(reason: "response.done");
      } else {
        info("[grok] response done without assistant output");
      }
      return;
    }

    if (type == "input_audio_buffer.speech_started") {
      if (_usesProviderVad) {
        await _handleProviderSpeechStarted();
        return;
      }
      userTranscriptBuffer.startTurn();
      return;
    }

    if (type == "input_audio_buffer.speech_stopped") {
      if (_usesProviderVad) {
        await _handleProviderSpeechStopped();
      }
      return;
    }

    if (type == "input_audio_buffer.committed") {
      info("[grok] input audio committed");
      return;
    }

    if (type == "response.output_audio.delta") {
      String delta = event["delta"]?.toString() ?? "";
      if (delta.isEmpty) return;
      await assistantOutput.ensureStarted(trigger: "audio");

      downstreamAudioChunkCount++;
      assistantOutput.recordAudioChunk();
      if (downstreamAudioChunkCount == 1 ||
          downstreamAudioChunkCount % 50 == 0) {
        info("[grok] downstream audio chunk #$downstreamAudioChunkCount");
      }
      await runtime.emitAudio(base64Decode(delta));
      return;
    }

    if (type == "response.output_audio_transcript.delta" ||
        type == "response.text.delta") {
      await assistantOutput.ensureStarted(trigger: "transcript");
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "response.output_audio_transcript.done") {
      await assistantOutput.ensureStarted(trigger: "transcript.final");
      info("[grok] assistant transcript final");
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantFinalEvent(
          text: event["transcript"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "conversation.item.input_audio_transcription.completed") {
      await _handleUserTranscript(event);
      return;
    }

    if (type == "response.function_call_arguments.done") {
      info("[grok] tool call received");
      await _handleToolCall(event);
      return;
    }

    if (type == "error") {
      await _handleProviderErrorMessage(event);
    }
  }

  Future<void> _handleToolCall(Map<String, Object?> event) async {
    await toolExecutionBridge.executeJsonToolCall(
      providerLabel: "grok",
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

  Future<void> _handleUserTranscript(Map<String, Object?> event) async {
    String transcript = event["transcript"]?.toString() ?? "";
    String? delta = userTranscriptBuffer.applySnapshot(transcript);
    if (delta == null) return;
    await runtime.onJsonEvent(RealtimeTranscriptUserDeltaEvent(text: delta));
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    await emitProviderErrorFromEvent(
      runtime: runtime,
      providerLabel: "grok",
      event: event,
      defaultMessage: "Grok realtime error",
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    info("[grok] session updated and ready");
    await runtime.emitSessionStarted();
    await _sendInitialGreetingIfNeeded();
  }

  Future<void> _sendInitialGreetingIfNeeded() async {
    if (initialGreetingTriggered || !config.hasInitialGreeting) {
      return;
    }
    initialGreetingTriggered = true;
    info("[grok] sending initial greeting prompt");
    await _sendProviderEvent(<String, Object?>{
      "type": "response.create",
      "response": <String, Object?>{
        "instructions": config.normalizedInitialGreeting,
      },
    });
  }

  Future<void> _flushPendingUserTranscript() async {
    String? transcript = userTranscriptBuffer.finalizeText();
    if (transcript == null) return;

    info("[grok] user transcript final");
    await runtime.onJsonEvent(
      RealtimeTranscriptUserFinalEvent(text: transcript),
    );
  }

  Future<void> _handleProviderDone() async {
    responseActive = false;
    assistantOutput.logFinished(reason: "socket.done");
    info(
      "[grok] websocket done code=${connection.closeCode} reason=${connection.closeReason}",
    );
    await close();
    await runtime.notifyClosed();
  }

  Future<void> _handleProviderError(Object error) async {
    responseActive = false;
    assistantOutput.logFinished(reason: "socket.error");
    warning("[grok] websocket error: $error");
    await runtime.emitError(message: error.toString());
    await close();
    await runtime.notifyClosed();
  }

  Future<void> _sendProviderEvent(Map<String, Object?> payload) async {
    await connection.sendJson(payload);
  }

  Future<void> _emitUsageFromResponseDone(Map<String, Object?> event) async {
    ArcaneVoiceProxyUsage? usage = _parseOpenAiLikeUsage(
      provider: RealtimeProviderCatalog.grokId,
      event: event,
    );
    if (usage == null) {
      return;
    }
    await runtime.emitUsage(usage);
  }

  Map<String, Object?> _buildSessionUpdate() => <String, Object?>{
    "instructions": config.instructions,
    "voice": config.voice,
    "turn_detection": ProxyVadModeSupport.buildOpenAiCompatibleTurnDetection(
      vadMode: vadMode,
      config: config.turnDetection,
      supportsResponseControls: false,
    ),
    "audio": <String, Object?>{
      "input": <String, Object?>{
        "format": <String, Object?>{
          "type": "audio/pcm",
          "rate": config.inputSampleRate,
        },
      },
      "output": <String, Object?>{
        "format": <String, Object?>{
          "type": "audio/pcm",
          "rate": config.outputSampleRate,
        },
      },
    },
    if (toolRegistry.hasTools) "tools": toolRegistry.openAiTools,
  };

  void _logProviderEvent(String type, Map<String, Object?> event) {
    if (_isStreamingDeltaEvent(type) ||
        type == "conversation.item.input_audio_transcription.completed" ||
        type == "input_audio_buffer.speech_started" ||
        type == "input_audio_buffer.speech_stopped") {
      return;
    }

    if (type == "session.created" ||
        type == "session.updated" ||
        type == "conversation.created") {
      info("[grok] event $type");
      return;
    }

    verbose("[grok] event $type ${jsonEncode(event)}");
  }

  bool _isStreamingDeltaEvent(String type) => type.endsWith(".delta");

  bool get _usesProviderVad => ProxyVadModeSupport.usesProviderVad(vadMode);

  Future<void> _handleSpeechStarted(ProxySpeechStartEvent event) async {
    userTranscriptBuffer.startTurn();
    if (responseActive && config.turnDetection.bargeInEnabled) {
      info("[grok] cancelling active response for new user speech");
      responseActive = false;
      assistantOutput.reset();
      await interrupt();
    }
  }

  Future<void> _handleSpeechStopped(ProxySpeechStopEvent event) async {
    if (!audioBufferedForCurrentTurn) return;
    audioBufferedForCurrentTurn = false;
    info("[grok] response.create sent");
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.commit",
    });
    await _sendProviderEvent(<String, Object?>{"type": "response.create"});
  }

  Future<void> _handleProviderSpeechStarted() async {
    if (providerSpeechActive) {
      return;
    }
    providerSpeechActive = true;
    userTranscriptBuffer.startTurn();
    if (responseActive && config.turnDetection.bargeInEnabled) {
      info("[grok] cancelling active response for provider-detected speech");
      responseActive = false;
      assistantOutput.reset();
      await interrupt();
    }
    await runtime.emitSpeechStarted();
  }

  Future<void> _handleProviderSpeechStopped() async {
    if (!providerSpeechActive) {
      return;
    }
    providerSpeechActive = false;
    await runtime.emitSpeechStopped();
  }

  Future<void> _appendAudioChunk(Uint8List audioBytes) async {
    audioBufferedForCurrentTurn = true;
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.append",
      "audio": base64Encode(audioBytes),
    });
  }

  ArcaneVoiceProxyUsage? _parseOpenAiLikeUsage({
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
