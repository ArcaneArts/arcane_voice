import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  WebSocket? socket;
  StreamSubscription<dynamic>? subscription;
  bool sessionStarted = false;
  bool isClosed = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  bool responseActive = false;
  int lastCommitAtMs = -1;

  OpenAiRealtimeSession({
    required this.apiKey,
    required this.config,
    required this.toolRegistry,
    required Future<void> Function(RealtimeServerMessage payload) onJsonEvent,
    required Future<void> Function(Uint8List audioBytes) onAudioChunk,
    required Future<void> Function() onClosed,
  }) {
    runtime = ProviderSessionRuntime(
      providerId: RealtimeProviderCatalog.openAiId,
      providerLabel: "openai",
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: onJsonEvent,
      onAudioChunk: onAudioChunk,
      onClosed: onClosed,
    );
    toolExecutionBridge = ProviderToolExecutionBridge(runtime: runtime);
    assistantOutput = AssistantOutputLifecycle(runtime: runtime);
    turnDetector = ProxyTurnDetector(runtime: runtime);
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
    WebSocket providerSocket = await WebSocket.connect(
      uri.toString(),
      headers: <String, Object>{
        "Authorization": "Bearer $apiKey",
        "OpenAI-Beta": "realtime=v1",
      },
    );

    info("[openai] websocket connected");
    providerSocket.pingInterval = const Duration(seconds: 20);
    socket = providerSocket;
    subscription = providerSocket.listen(
      _handleProviderMessage,
      onDone: _handleProviderDone,
      onError: _handleProviderError,
      cancelOnError: true,
    );

    await _sendProviderEvent(<String, Object?>{
      "type": "session.update",
      "session": _buildSessionUpdate(),
    });
    info("[openai] session.update sent");
  }

  @override
  Future<void> sendAudio(Uint8List audioBytes) async {
    if (isClosed) return;
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
    if (isClosed) return;
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
    if (isClosed) return;
    isClosed = true;
    info("[openai] closing realtime session");
    StreamSubscription<dynamic>? currentSubscription = subscription;
    WebSocket? currentSocket = socket;
    subscription = null;
    socket = null;
    await currentSubscription?.cancel();
    await currentSocket?.close();
  }

  Future<void> _handleProviderMessage(dynamic message) async {
    if (message is! String) return;

    Map<String, Object?> event = JsonCodecHelper.decodeObject(message);
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
    String toolName = event["name"]?.toString() ?? "";
    String callId = event["call_id"]?.toString() ?? "";
    String rawArguments = event["arguments"]?.toString() ?? "{}";
    if (toolName.isEmpty || callId.isEmpty) return;
    info("[openai] executing tool $toolName");
    ToolExecutionInvocation invocation = toolExecutionBridge.createInvocation(
      callId: callId,
      name: toolName,
    );
    ToolExecutionResult output = await invocation.executeJson(
      rawArguments: rawArguments,
    );

    await _sendProviderEvent(<String, Object?>{
      "type": "conversation.item.create",
      "item": <String, Object?>{
        "type": "function_call_output",
        "call_id": callId,
        "output": output.outputJson,
      },
    });

    await _sendProviderEvent(<String, Object?>{"type": "response.create"});

    await invocation.emitCompleted(output);
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    warning("[openai] provider error event: ${jsonEncode(event)}");
    Object? rawError = event["error"];
    if (rawError is Map<String, dynamic>) {
      await runtime.emitError(
        message: rawError["message"]?.toString() ?? "OpenAI realtime error",
        code: rawError["code"]?.toString(),
      );
      return;
    }

    await runtime.emitError(
      message: event["message"]?.toString() ?? "OpenAI realtime error",
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    info("[openai] session updated and ready");
    await runtime.emitSessionStarted();
  }

  Future<void> _handleProviderDone() async {
    responseActive = false;
    assistantOutput.logFinished(reason: "socket.done");
    info("[openai] websocket done");
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
    if (isClosed) return;
    socket?.add(jsonEncode(payload));
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
}
