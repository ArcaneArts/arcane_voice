import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

class GrokVoiceSession implements RealtimeProviderSession {
  static const int audioLogInterval = 25;

  final String apiKey;
  final RealtimeSessionConfig config;
  final ProxyToolRegistry toolRegistry;
  late final ProviderSessionRuntime runtime;
  late final ProviderToolExecutionBridge toolExecutionBridge;
  late final AssistantOutputLifecycle assistantOutput;
  late final ProxyTurnDetector turnDetector;
  final MonotonicTranscriptBuffer userTranscriptBuffer =
      MonotonicTranscriptBuffer();

  WebSocket? socket;
  StreamSubscription<dynamic>? subscription;
  bool sessionStarted = false;
  bool isClosed = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  bool responseActive = false;
  bool audioBufferedForCurrentTurn = false;

  GrokVoiceSession({
    required this.apiKey,
    required this.config,
    required this.toolRegistry,
    required Future<void> Function(RealtimeServerMessage payload) onJsonEvent,
    required Future<void> Function(Uint8List audioBytes) onAudioChunk,
    required Future<void> Function() onClosed,
  }) {
    runtime = ProviderSessionRuntime(
      providerId: RealtimeProviderCatalog.grokId,
      providerLabel: "grok",
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
    info("[grok] connecting realtime websocket model=${config.model}");
    runtime.startDebugClock();
    runtime.logTurnDebug();
    await runtime.emitConnecting();

    Uri uri = Uri.parse("wss://api.x.ai/v1/realtime");
    WebSocket providerSocket = await WebSocket.connect(
      uri.toString(),
      headers: <String, Object>{"Authorization": "Bearer $apiKey"},
    );

    info("[grok] websocket connected");
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
    info("[grok] session.update sent");
  }

  @override
  Future<void> sendAudio(Uint8List audioBytes) async {
    if (isClosed) return;

    upstreamAudioChunkCount++;
    if (upstreamAudioChunkCount <= 5 ||
        upstreamAudioChunkCount % audioLogInterval == 0) {
      info(
        "[grok] upstream audio chunk #$upstreamAudioChunkCount (${audioBytes.length} bytes)",
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
    if (isClosed) return;
    isClosed = true;
    info("[grok] closing realtime session");
    StreamSubscription<dynamic>? currentSubscription = subscription;
    WebSocket? currentSocket = socket;
    subscription = null;
    socket = null;
    await currentSubscription?.cancel();
    await currentSocket?.close();
  }

  Future<void> _handleProviderMessage(dynamic message) async {
    String source = switch (message) {
      String text => text,
      List<int> bytes => utf8.decode(bytes),
      _ => "",
    };
    if (source.isEmpty) return;

    Map<String, Object?> event = JsonCodecHelper.decodeObject(source);
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
      userTranscriptBuffer.startTurn();
      return;
    }

    if (type == "input_audio_buffer.speech_stopped") {
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
    String toolName = event["name"]?.toString() ?? "";
    String callId = event["call_id"]?.toString() ?? "";
    String rawArguments = event["arguments"]?.toString() ?? "{}";
    if (toolName.isEmpty || callId.isEmpty) return;
    info("[grok] executing tool $toolName");
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

  Future<void> _handleUserTranscript(Map<String, Object?> event) async {
    String transcript = event["transcript"]?.toString() ?? "";
    String? delta = userTranscriptBuffer.applySnapshot(transcript);
    if (delta == null) return;
    await runtime.onJsonEvent(RealtimeTranscriptUserDeltaEvent(text: delta));
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    warning("[grok] provider error event: ${jsonEncode(event)}");
    Object? rawError = event["error"];
    if (rawError is Map<String, dynamic>) {
      await runtime.emitError(
        message: rawError["message"]?.toString() ?? "Grok realtime error",
        code: rawError["code"]?.toString(),
      );
      return;
    }

    await runtime.emitError(
      message: event["message"]?.toString() ?? "Grok realtime error",
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    info("[grok] session updated and ready");
    await runtime.emitSessionStarted();
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
    info("[grok] websocket done");
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
    if (isClosed) return;
    socket?.add(jsonEncode(payload));
  }

  Map<String, Object?> _buildSessionUpdate() => <String, Object?>{
    "instructions": config.instructions,
    "voice": config.voice,
    "turn_detection": null,
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

  Future<void> _appendAudioChunk(Uint8List audioBytes) async {
    audioBufferedForCurrentTurn = true;
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.append",
      "audio": base64Encode(audioBytes),
    });
  }
}
