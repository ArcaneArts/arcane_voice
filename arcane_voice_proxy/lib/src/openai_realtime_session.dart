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
  final Future<void> Function(RealtimeServerMessage payload) onJsonEvent;
  final Future<void> Function(Uint8List audioBytes) onAudioChunk;
  final Future<void> Function() onClosed;
  final Stopwatch debugClock = Stopwatch();

  WebSocket? socket;
  StreamSubscription<dynamic>? subscription;
  bool sessionStarted = false;
  bool isClosed = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  bool speechActive = false;
  bool responseActive = false;
  bool assistantOutputActive = false;
  int silentDurationMs = 0;
  int loudDurationMs = 0;
  int bufferedSpeechLeadInDurationMs = 0;
  int userTurnCount = 0;
  int assistantTurnCount = 0;
  int currentSpeechDurationMs = 0;
  int currentSpeechChunkCount = 0;
  int lastCommitAtMs = -1;
  int responseStartedAtMs = -1;
  int firstAudioAtMs = -1;
  int responseAudioChunkCount = 0;
  List<BufferedAudioChunk> bufferedSpeechLeadIn = <BufferedAudioChunk>[];

  OpenAiRealtimeSession({
    required this.apiKey,
    required this.config,
    required this.toolRegistry,
    required this.onJsonEvent,
    required this.onAudioChunk,
    required this.onClosed,
  });

  @override
  Future<void> start() async {
    info("[openai] connecting realtime websocket model=${config.model}");
    debugClock
      ..reset()
      ..start();
    info(
      "[openai] turn debug threshold=${config.turnDetection.speechThresholdRms} "
      "startMs=${config.turnDetection.speechStartMs} endSilenceMs=${config.turnDetection.speechEndSilenceMs} "
      "preSpeechMs=${config.turnDetection.preSpeechMs} bargeIn=${config.turnDetection.bargeInEnabled}",
    );
    await onJsonEvent(
      const RealtimeSessionStateEvent(
        state: "connecting",
        provider: RealtimeProviderCatalog.openAiId,
      ),
    );

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
    int rms = Pcm16LevelMeter.computeRms(audioBytes);
    int chunkDurationMs = Pcm16ChunkTiming.chunkDurationMs(
      audioBytes: audioBytes,
      sampleRate: config.inputSampleRate,
    );
    if (upstreamAudioChunkCount <= 5 ||
        upstreamAudioChunkCount % audioLogInterval == 0) {
      info(
        "[openai] upstream audio chunk #$upstreamAudioChunkCount (${audioBytes.length} bytes)",
      );
    }
    await _handleTurnDetection(audioBytes, rms, chunkDurationMs);
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
      assistantOutputActive = false;
      info("[openai] response created at ${_debugNowMs()}ms");
      return;
    }

    if (type == "response.done") {
      responseActive = false;
      if (assistantOutputActive) {
        _logResponseFinished();
        await onJsonEvent(
          const RealtimeAssistantOutputCompletedEvent(reason: "response.done"),
        );
        await onJsonEvent(const RealtimeSessionStateEvent(state: "ready"));
      } else {
        info("[openai] response done without assistant output");
      }
      assistantOutputActive = false;
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
      await _ensureAssistantOutputStarted(trigger: "audio");
      downstreamAudioChunkCount++;
      responseAudioChunkCount++;
      if (firstAudioAtMs < 0) {
        firstAudioAtMs = _debugNowMs();
        info(
          "[openai] assistant turn #$assistantTurnCount first audio at ${firstAudioAtMs}ms "
          "latency=${_formatLatency(firstAudioAtMs, responseStartedAtMs)}",
        );
      }
      if (downstreamAudioChunkCount == 1 ||
          downstreamAudioChunkCount % audioLogInterval == 0) {
        info("[openai] downstream audio chunk #$downstreamAudioChunkCount");
      }
      await onAudioChunk(base64Decode(delta));
      return;
    }

    if (type == "response.output_audio_transcript.delta" ||
        type == "response.audio_transcript.delta") {
      await _ensureAssistantOutputStarted(trigger: "transcript");
      await onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "response.output_audio_transcript.done" ||
        type == "response.audio_transcript.done") {
      await _ensureAssistantOutputStarted(trigger: "transcript.final");
      info("[openai] assistant transcript final");
      await onJsonEvent(
        RealtimeTranscriptAssistantFinalEvent(
          text: event["transcript"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "conversation.item.input_audio_transcription.delta") {
      await onJsonEvent(
        RealtimeTranscriptUserDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "conversation.item.input_audio_transcription.completed") {
      info("[openai] user transcript final");
      await onJsonEvent(
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
      await _ensureAssistantOutputStarted(trigger: "text");
      await onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(
          text: event["delta"]?.toString() ?? "",
        ),
      );
      return;
    }

    if (type == "response.output_text.done") {
      await _ensureAssistantOutputStarted(trigger: "text.final");
      await onJsonEvent(
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

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    warning("[openai] provider error event: ${jsonEncode(event)}");
    Object? rawError = event["error"];
    if (rawError is Map<String, dynamic>) {
      await onJsonEvent(
        RealtimeErrorEvent(
          message: rawError["message"]?.toString() ?? "OpenAI realtime error",
          code: rawError["code"]?.toString(),
        ),
      );
      return;
    }

    await onJsonEvent(
      RealtimeErrorEvent(
        message: event["message"]?.toString() ?? "OpenAI realtime error",
      ),
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    info("[openai] session updated and ready");
    await onJsonEvent(
      RealtimeSessionStartedEvent(
        provider: RealtimeProviderCatalog.openAiId,
        model: config.model,
        voice: config.voice,
        inputSampleRate: config.inputSampleRate,
        outputSampleRate: config.outputSampleRate,
      ),
    );
    await onJsonEvent(const RealtimeSessionStateEvent(state: "ready"));
  }

  Future<void> _handleProviderDone() async {
    responseActive = false;
    _logResponseFinished(reason: "socket.done");
    info("[openai] websocket done");
    await close();
    await onClosed();
  }

  Future<void> _handleProviderError(Object error) async {
    responseActive = false;
    _logResponseFinished(reason: "socket.error");
    warning("[openai] websocket error: $error");
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

  Future<void> _handleTurnDetection(
    Uint8List audioBytes,
    int rms,
    int chunkDurationMs,
  ) async {
    if (speechActive) {
      await _appendAudioChunk(audioBytes);
      currentSpeechDurationMs += chunkDurationMs;
      currentSpeechChunkCount++;
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
    userTurnCount++;
    silentDurationMs = 0;
    loudDurationMs = 0;
    currentSpeechDurationMs = bufferedSpeechLeadInDurationMs;
    currentSpeechChunkCount = bufferedSpeechLeadIn.length;
    if (responseActive && config.turnDetection.bargeInEnabled) {
      info("[openai] cancelling active response for new user speech");
      responseActive = false;
      if (assistantOutputActive) {
        _logResponseFinished(reason: "barge-in");
      }
      assistantOutputActive = false;
      await interrupt();
    }
    info(
      "[openai] user turn #$userTurnCount speech started at ${_debugNowMs()}ms "
      "leadIn=${bufferedSpeechLeadInDurationMs}ms bufferedChunks=${bufferedSpeechLeadIn.length}",
    );
    await onJsonEvent(const RealtimeInputSpeechStartedEvent());

    List<BufferedAudioChunk> speechLeadIn = bufferedSpeechLeadIn;
    bufferedSpeechLeadIn = <BufferedAudioChunk>[];
    bufferedSpeechLeadInDurationMs = 0;
    for (BufferedAudioChunk chunk in speechLeadIn) {
      await _appendAudioChunk(chunk.audioBytes);
    }
  }

  Future<void> _commitBufferedAudio() async {
    lastCommitAtMs = _debugNowMs();
    info(
      "[openai] user turn #$userTurnCount speech stopped at ${lastCommitAtMs}ms "
      "speechDuration=${currentSpeechDurationMs}ms chunks=$currentSpeechChunkCount "
      "silenceWindow=${config.turnDetection.speechEndSilenceMs}ms",
    );
    await onJsonEvent(const RealtimeInputSpeechStoppedEvent());
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.commit",
    });
    info("[openai] user turn #$userTurnCount response.create sent");
    await _sendProviderEvent(<String, Object?>{
      "type": "response.create",
      "response": <String, Object?>{
        "modalities": <String>["audio", "text"],
      },
    });
    currentSpeechDurationMs = 0;
    currentSpeechChunkCount = 0;
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
    await _sendProviderEvent(<String, Object?>{
      "type": "input_audio_buffer.append",
      "audio": base64Encode(audioBytes),
    });
  }

  int _debugNowMs() => debugClock.elapsedMilliseconds;

  String _formatLatency(int currentMs, int startedAtMs) {
    if (startedAtMs < 0) {
      return "n/a";
    }
    return "${currentMs - startedAtMs}ms";
  }

  String _formatLatencyFromCommit() {
    if (lastCommitAtMs < 0 || responseStartedAtMs < 0) {
      return "n/a";
    }
    return "${responseStartedAtMs - lastCommitAtMs}ms";
  }

  void _logResponseFinished({String reason = "response.done"}) {
    if (!assistantOutputActive ||
        assistantTurnCount == 0 ||
        responseStartedAtMs < 0) {
      return;
    }
    int finishedAtMs = _debugNowMs();
    String responseDuration = _formatLatency(finishedAtMs, responseStartedAtMs);
    String firstAudioLatency = firstAudioAtMs < 0
        ? "n/a"
        : _formatLatency(firstAudioAtMs, responseStartedAtMs);
    info(
      "[openai] assistant turn #$assistantTurnCount finished via $reason at ${finishedAtMs}ms "
      "duration=$responseDuration firstAudio=$firstAudioLatency audioChunks=$responseAudioChunkCount",
    );
    responseStartedAtMs = -1;
    firstAudioAtMs = -1;
    responseAudioChunkCount = 0;
  }

  Future<void> _ensureAssistantOutputStarted({required String trigger}) async {
    if (assistantOutputActive) {
      return;
    }
    assistantOutputActive = true;
    assistantTurnCount++;
    responseStartedAtMs = _debugNowMs();
    firstAudioAtMs = -1;
    responseAudioChunkCount = 0;
    info(
      "[openai] assistant turn #$assistantTurnCount output started via $trigger at ${responseStartedAtMs}ms "
      "after commit ${_formatLatencyFromCommit()}",
    );
    await onJsonEvent(const RealtimeSessionStateEvent(state: "responding"));
  }
}
