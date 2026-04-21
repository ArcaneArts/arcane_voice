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
  final Future<void> Function(RealtimeServerMessage payload) onJsonEvent;
  final Future<void> Function(Uint8List audioBytes) onAudioChunk;
  final Future<void> Function() onClosed;

  WebSocket? socket;
  StreamSubscription<dynamic>? subscription;
  bool sessionStarted = false;
  bool isClosed = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  bool speechActive = false;
  bool responseActive = false;
  bool assistantOutputActive = false;
  bool audioBufferedForCurrentTurn = false;
  int silentDurationMs = 0;
  int loudDurationMs = 0;
  int bufferedSpeechLeadInDurationMs = 0;
  String pendingUserTranscript = "";
  List<BufferedAudioChunk> bufferedSpeechLeadIn = <BufferedAudioChunk>[];

  GrokVoiceSession({
    required this.apiKey,
    required this.config,
    required this.toolRegistry,
    required this.onJsonEvent,
    required this.onAudioChunk,
    required this.onClosed,
  });

  @override
  Future<void> start() async {
    info("[grok] connecting realtime websocket model=${config.model}");
    await onJsonEvent(
      RealtimeSessionStateEvent(
        state: "connecting",
        provider: RealtimeProviderCatalog.grokId,
      ),
    );

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
    int rms = Pcm16LevelMeter.computeRms(audioBytes);
    int chunkDurationMs = Pcm16ChunkTiming.chunkDurationMs(
      audioBytes: audioBytes,
      sampleRate: config.inputSampleRate,
    );
    if (upstreamAudioChunkCount <= 5 ||
        upstreamAudioChunkCount % audioLogInterval == 0) {
      info(
        "[grok] upstream audio chunk #$upstreamAudioChunkCount (${audioBytes.length} bytes)",
      );
    }
    await _handleTurnDetection(audioBytes, rms, chunkDurationMs);
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
      assistantOutputActive = false;
      await _flushPendingUserTranscript();
      info("[grok] response created");
      return;
    }

    if (type == "response.done") {
      responseActive = false;
      await _flushPendingUserTranscript();
      info("[grok] response done");
      if (assistantOutputActive) {
        await onJsonEvent(
          const RealtimeAssistantOutputCompletedEvent(reason: "response.done"),
        );
        await onJsonEvent(const RealtimeSessionStateEvent(state: "ready"));
      } else {
        info("[grok] response done without assistant output");
      }
      assistantOutputActive = false;
      return;
    }

    if (type == "input_audio_buffer.speech_started") {
      pendingUserTranscript = "";
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
      await _ensureAssistantOutputStarted();

      downstreamAudioChunkCount++;
      if (downstreamAudioChunkCount == 1 ||
          downstreamAudioChunkCount % 50 == 0) {
        info("[grok] downstream audio chunk #$downstreamAudioChunkCount");
      }
      await onAudioChunk(base64Decode(delta));
      return;
    }

    if (type == "response.output_audio_transcript.delta" ||
        type == "response.text.delta") {
      await _ensureAssistantOutputStarted();
      await onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "response.output_audio_transcript.done") {
      await _ensureAssistantOutputStarted();
      info("[grok] assistant transcript final");
      await onJsonEvent(
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

    String executionTarget = toolRegistry.executionTarget(toolName);
    await onJsonEvent(
      RealtimeToolStartedEvent(
        callId: callId,
        name: toolName,
        executionTarget: executionTarget,
      ),
    );

    ToolExecutionResult output = await toolRegistry.executeJsonString(
      callId: callId,
      name: toolName,
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

    await onJsonEvent(
      RealtimeToolCompletedEvent(
        callId: callId,
        name: toolName,
        executionTarget: output.executionTarget,
        success: output.success,
        error: output.error,
      ),
    );
  }

  Future<void> _handleUserTranscript(Map<String, Object?> event) async {
    String transcript = event["transcript"]?.toString() ?? "";
    if (transcript.isEmpty || transcript == pendingUserTranscript) return;

    String delta = transcript.startsWith(pendingUserTranscript)
        ? transcript.substring(pendingUserTranscript.length)
        : transcript;
    pendingUserTranscript = transcript;
    await onJsonEvent(RealtimeTranscriptUserDeltaEvent(text: delta));
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    warning("[grok] provider error event: ${jsonEncode(event)}");
    Object? rawError = event["error"];
    if (rawError is Map<String, dynamic>) {
      await onJsonEvent(
        RealtimeErrorEvent(
          message: rawError["message"]?.toString() ?? "Grok realtime error",
          code: rawError["code"]?.toString(),
        ),
      );
      return;
    }

    await onJsonEvent(
      RealtimeErrorEvent(
        message: event["message"]?.toString() ?? "Grok realtime error",
      ),
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    info("[grok] session updated and ready");
    await onJsonEvent(
      RealtimeSessionStartedEvent(
        provider: RealtimeProviderCatalog.grokId,
        model: config.model,
        voice: config.voice,
        inputSampleRate: config.inputSampleRate,
        outputSampleRate: config.outputSampleRate,
      ),
    );
    await onJsonEvent(const RealtimeSessionStateEvent(state: "ready"));
  }

  Future<void> _flushPendingUserTranscript() async {
    if (pendingUserTranscript.isEmpty) return;

    info("[grok] user transcript final");
    await onJsonEvent(
      RealtimeTranscriptUserFinalEvent(text: pendingUserTranscript),
    );
    pendingUserTranscript = "";
  }

  Future<void> _handleProviderDone() async {
    responseActive = false;
    info("[grok] websocket done");
    await close();
    await onClosed();
  }

  Future<void> _handleProviderError(Object error) async {
    responseActive = false;
    warning("[grok] websocket error: $error");
    await onJsonEvent(RealtimeErrorEvent(message: error.toString()));
    await close();
    await onClosed();
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

  Future<void> _handleTurnDetection(
    Uint8List audioBytes,
    int rms,
    int chunkDurationMs,
  ) async {
    if (speechActive) {
      await _appendAudioChunk(audioBytes);
      if (rms >= config.turnDetection.speechThresholdRms) {
        silentDurationMs = 0;
        return;
      }

      silentDurationMs += chunkDurationMs;
      if (silentDurationMs < config.turnDetection.speechEndSilenceMs) return;

      speechActive = false;
      silentDurationMs = 0;
      loudDurationMs = 0;
      await _commitBufferedAudio();
      return;
    }

    _bufferLeadIn(audioBytes, chunkDurationMs);

    if (rms < config.turnDetection.speechThresholdRms) {
      loudDurationMs = 0;
      return;
    }

    loudDurationMs += chunkDurationMs;
    if (loudDurationMs < config.turnDetection.speechStartMs) return;

    speechActive = true;
    silentDurationMs = 0;
    loudDurationMs = 0;
    pendingUserTranscript = "";
    if (responseActive && config.turnDetection.bargeInEnabled) {
      info("[grok] cancelling active response for new user speech");
      responseActive = false;
      assistantOutputActive = false;
      await interrupt();
    }
    info("[grok] proxy speech started");
    await onJsonEvent(const RealtimeInputSpeechStartedEvent());

    List<BufferedAudioChunk> speechLeadIn = bufferedSpeechLeadIn;
    bufferedSpeechLeadIn = <BufferedAudioChunk>[];
    bufferedSpeechLeadInDurationMs = 0;
    for (BufferedAudioChunk chunk in speechLeadIn) {
      await _appendAudioChunk(chunk.audioBytes);
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
    while (bufferedSpeechLeadInDurationMs > config.turnDetection.preSpeechMs &&
        bufferedSpeechLeadIn.isNotEmpty) {
      BufferedAudioChunk removedChunk = bufferedSpeechLeadIn.first;
      bufferedSpeechLeadIn = bufferedSpeechLeadIn.sublist(1);
      bufferedSpeechLeadInDurationMs -= removedChunk.durationMs;
    }
  }

  Future<void> _appendAudioChunk(Uint8List audioBytes) async {
    audioBufferedForCurrentTurn = true;
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.append",
      "audio": base64Encode(audioBytes),
    });
  }

  Future<void> _commitBufferedAudio() async {
    if (!audioBufferedForCurrentTurn) return;
    audioBufferedForCurrentTurn = false;
    info("[grok] proxy speech stopped, committing audio buffer");
    await onJsonEvent(const RealtimeInputSpeechStoppedEvent());
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.commit",
    });
    info("[grok] response.create sent");
    await _sendProviderEvent(<String, Object?>{"type": "response.create"});
  }

  Future<void> _ensureAssistantOutputStarted() async {
    if (assistantOutputActive) {
      return;
    }
    assistantOutputActive = true;
    await onJsonEvent(const RealtimeSessionStateEvent(state: "responding"));
  }
}
