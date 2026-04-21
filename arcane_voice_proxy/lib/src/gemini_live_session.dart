import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

class GeminiLiveSession implements RealtimeProviderSession {
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
  Timer? setupFallbackTimer;
  bool sessionStarted = false;
  bool isClosed = false;
  bool speechActive = false;
  bool responseActive = false;
  bool assistantTurnInterrupted = false;
  bool userTranscriptFinalizedForCurrentTurn = false;
  bool assistantTranscriptFinalizedForCurrentTurn = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  int silentDurationMs = 0;
  int loudDurationMs = 0;
  int bufferedSpeechLeadInDurationMs = 0;
  int userTurnCount = 0;
  int assistantTurnCount = 0;
  int currentSpeechDurationMs = 0;
  int currentSpeechChunkCount = 0;
  int lastActivityEndAtMs = -1;
  int responseStartedAtMs = -1;
  int firstAudioAtMs = -1;
  int responseAudioChunkCount = 0;
  String pendingUserTranscript = "";
  String pendingAssistantTranscript = "";
  List<BufferedAudioChunk> bufferedSpeechLeadIn = <BufferedAudioChunk>[];

  GeminiLiveSession({
    required this.apiKey,
    required this.config,
    required this.toolRegistry,
    required this.onJsonEvent,
    required this.onAudioChunk,
    required this.onClosed,
  });

  @override
  Future<void> start() async {
    info("[gemini] connecting live websocket model=${config.model}");
    debugClock
      ..reset()
      ..start();
    info(
      "[gemini] turn debug threshold=${config.turnDetection.speechThresholdRms} "
      "startMs=${config.turnDetection.speechStartMs} endSilenceMs=${config.turnDetection.speechEndSilenceMs} "
      "preSpeechMs=${config.turnDetection.preSpeechMs} bargeIn=${config.turnDetection.bargeInEnabled}",
    );
    await onJsonEvent(
      RealtimeSessionStateEvent(
        state: "connecting",
        provider: RealtimeProviderCatalog.geminiId,
      ),
    );

    Uri uri = Uri.parse(
      "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=${Uri.encodeQueryComponent(apiKey)}",
    );
    WebSocket providerSocket = await WebSocket.connect(uri.toString());
    providerSocket.pingInterval = const Duration(seconds: 20);
    socket = providerSocket;
    subscription = providerSocket.listen(
      _handleProviderMessage,
      onDone: _handleProviderDone,
      onError: _handleProviderError,
      cancelOnError: true,
    );

    info("[gemini] websocket connected");
    await _sendProviderEvent(<String, Object?>{"setup": _buildSetup()});
    info("[gemini] setup sent");
    setupFallbackTimer = Timer(
      const Duration(milliseconds: 750),
      _handleSetupFallbackTimeout,
    );
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
    if (upstreamAudioChunkCount == 1 ||
        upstreamAudioChunkCount <= 5 ||
        upstreamAudioChunkCount % audioLogInterval == 0) {
      info(
        "[gemini] upstream audio chunk #$upstreamAudioChunkCount (${audioBytes.length} bytes)",
      );
    }
    await _handleTurnDetection(audioBytes, rms, chunkDurationMs);
  }

  @override
  Future<void> sendText(String text) async {
    if (isClosed || text.trim().isEmpty) return;
    info("[gemini] sending text input: $text");
    await _sendProviderEvent(<String, Object?>{
      "realtimeInput": <String, Object?>{"text": text},
    });
  }

  @override
  Future<void> interrupt() async {
    info("[gemini] interrupt requested");
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    info("[gemini] closing live session");
    StreamSubscription<dynamic>? currentSubscription = subscription;
    WebSocket? currentSocket = socket;
    Timer? currentSetupFallbackTimer = setupFallbackTimer;
    subscription = null;
    socket = null;
    setupFallbackTimer = null;
    currentSetupFallbackTimer?.cancel();
    await currentSubscription?.cancel();
    await currentSocket?.close();
  }

  Future<void> _handleProviderMessage(dynamic message) async {
    String rawMessage;
    if (message is String) {
      rawMessage = message;
    } else if (message is List<int>) {
      rawMessage = utf8.decode(message);
    } else {
      warning(
        "[gemini] unsupported provider message type: ${message.runtimeType}",
      );
      return;
    }

    Map<String, Object?> event = JsonCodecHelper.decodeObject(rawMessage);
    _logProviderEvent(event);

    if (event.containsKey("setupComplete")) {
      await _announceSessionStarted();
      return;
    }

    Map<String, Object?>? serverContent = _castObjectMap(
      event["serverContent"],
    );
    if (serverContent != null) {
      await _handleServerContent(serverContent);
      return;
    }

    Map<String, Object?>? toolCall = _castObjectMap(event["toolCall"]);
    if (toolCall != null) {
      await _handleToolCall(toolCall);
      return;
    }

    if (event.containsKey("toolCallCancellation")) {
      info("[gemini] tool call cancellation received");
      return;
    }

    if (event.containsKey("goAway")) {
      warning("[gemini] server requested go away");
      await onJsonEvent(
        const RealtimeErrorEvent(message: "Gemini requested session shutdown."),
      );
      return;
    }

    Map<String, Object?>? error = _castObjectMap(event["error"]);
    if (error != null) {
      await _handleProviderErrorMessage(error);
    }
  }

  Future<void> _handleServerContent(Map<String, Object?> content) async {
    if (content["interrupted"] == true) {
      info(
        "[gemini] assistant turn #$assistantTurnCount interrupted by user activity at ${_debugNowMs()}ms",
      );
      responseActive = false;
      assistantTurnInterrupted = true;
      _logResponseFinished(reason: "interrupted");
      assistantTranscriptFinalizedForCurrentTurn = true;
      pendingAssistantTranscript = "";
      await onJsonEvent(const RealtimeTranscriptAssistantDiscardEvent());
    }

    String inputTranscript = _readTranscriptionText(
      content["inputTranscription"],
    );
    if (inputTranscript.isNotEmpty) {
      await _emitTranscriptUpdate(text: inputTranscript, speaker: "user");
    }

    String outputTranscript = _readTranscriptionText(
      content["outputTranscription"],
    );
    if (outputTranscript.isNotEmpty) {
      await _emitTranscriptUpdate(text: outputTranscript, speaker: "assistant");
    }

    Map<String, Object?>? modelTurn = _castObjectMap(content["modelTurn"]);
    if (modelTurn != null) {
      await _handleModelTurn(modelTurn);
    }

    if (content["generationComplete"] == true) {
      info(
        "[gemini] assistant turn #$assistantTurnCount generation complete at ${_debugNowMs()}ms",
      );
    }

    if (content["turnComplete"] == true) {
      info(
        "[gemini] assistant turn #$assistantTurnCount turn complete at ${_debugNowMs()}ms",
      );
      _logResponseFinished();
      await _flushPendingTranscripts();
      responseActive = false;
      assistantTurnInterrupted = false;
      await onJsonEvent(const RealtimeSessionStateEvent(state: "ready"));
    }
  }

  Future<void> _handleModelTurn(Map<String, Object?> modelTurn) async {
    if (!responseActive) {
      responseActive = true;
      assistantTurnCount++;
      assistantTurnInterrupted = false;
      assistantTranscriptFinalizedForCurrentTurn = false;
      pendingAssistantTranscript = "";
      responseStartedAtMs = _debugNowMs();
      firstAudioAtMs = -1;
      responseAudioChunkCount = 0;
      info(
        "[gemini] assistant turn #$assistantTurnCount started at ${responseStartedAtMs}ms "
        "after activityEnd ${_formatLatency(responseStartedAtMs, lastActivityEndAtMs)}",
      );
      await onJsonEvent(const RealtimeSessionStateEvent(state: "responding"));
    }

    Object? rawParts = modelTurn["parts"];
    if (rawParts is! List) return;

    for (Object? rawPart in rawParts) {
      Map<String, Object?>? part = _castObjectMap(rawPart);
      if (part == null) continue;
      await _handleModelTurnPart(part);
    }
  }

  Future<void> _handleModelTurnPart(Map<String, Object?> part) async {
    Map<String, Object?>? inlineData = _castObjectMap(part["inlineData"]);
    if (inlineData != null) {
      await _handleInlineData(inlineData);
    }
  }

  Future<void> _handleInlineData(Map<String, Object?> inlineData) async {
    String data = inlineData["data"]?.toString() ?? "";
    if (data.isEmpty) return;

    downstreamAudioChunkCount++;
    responseAudioChunkCount++;
    if (firstAudioAtMs < 0) {
      firstAudioAtMs = _debugNowMs();
      info(
        "[gemini] assistant turn #$assistantTurnCount first audio at ${firstAudioAtMs}ms "
        "latency=${_formatLatency(firstAudioAtMs, responseStartedAtMs)}",
      );
    }
    if (downstreamAudioChunkCount == 1 ||
        downstreamAudioChunkCount % audioLogInterval == 0) {
      info("[gemini] downstream audio chunk #$downstreamAudioChunkCount");
    }
    await onAudioChunk(base64Decode(data));
  }

  Future<void> _handleToolCall(Map<String, Object?> toolCall) async {
    Object? rawFunctionCalls = toolCall["functionCalls"];
    if (rawFunctionCalls is! List) return;

    List<Map<String, Object?>> functionResponses = <Map<String, Object?>>[];
    for (Object? rawFunctionCall in rawFunctionCalls) {
      Map<String, Object?>? functionCall = _castObjectMap(rawFunctionCall);
      if (functionCall == null) continue;

      String toolName = functionCall["name"]?.toString() ?? "";
      String callId = functionCall["id"]?.toString() ?? "";
      if (toolName.isEmpty || callId.isEmpty) continue;

      info("[gemini] executing tool $toolName");
      String executionTarget = toolRegistry.executionTarget(toolName);
      await onJsonEvent(
        RealtimeToolStartedEvent(
          callId: callId,
          name: toolName,
          executionTarget: executionTarget,
        ),
      );

      Object? rawArguments = functionCall["args"];
      Map<String, Object?> arguments =
          _castObjectMap(rawArguments) ?? <String, Object?>{};
      ToolExecutionResult output = await toolRegistry.executeObject(
        callId: callId,
        name: toolName,
        arguments: arguments,
      );

      functionResponses.add(<String, Object?>{
        "id": callId,
        "name": toolName,
        "response": output.outputObject,
      });

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

    if (functionResponses.isEmpty) return;
    await _sendProviderEvent(<String, Object?>{
      "toolResponse": <String, Object?>{"functionResponses": functionResponses},
    });
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> error) async {
    warning("[gemini] provider error: ${jsonEncode(error)}");
    await onJsonEvent(
      RealtimeErrorEvent(
        message: error["message"]?.toString() ?? "Gemini Live API error",
      ),
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    Timer? currentSetupFallbackTimer = setupFallbackTimer;
    setupFallbackTimer = null;
    currentSetupFallbackTimer?.cancel();
    info("[gemini] setup complete");
    await onJsonEvent(
      RealtimeSessionStartedEvent(
        provider: RealtimeProviderCatalog.geminiId,
        model: config.model,
        voice: config.voice,
        inputSampleRate: config.inputSampleRate,
        outputSampleRate: 24000,
      ),
    );
    await onJsonEvent(const RealtimeSessionStateEvent(state: "ready"));
  }

  Future<void> _handleProviderDone() async {
    WebSocket? currentSocket = socket;
    int? closeCode = currentSocket?.closeCode;
    String? closeReason = currentSocket?.closeReason;
    info("[gemini] websocket done code=$closeCode reason=$closeReason");
    _logResponseFinished(reason: "socket.done");
    if (!sessionStarted && (closeReason?.isNotEmpty ?? false)) {
      await onJsonEvent(RealtimeErrorEvent(message: closeReason!));
    }
    await close();
    await onClosed();
  }

  void _handleSetupFallbackTimeout() {
    if (sessionStarted || isClosed) return;
    warning("[gemini] setupComplete not received, assuming ready");
    unawaited(_announceSessionStarted());
  }

  Future<void> _handleProviderError(Object error) async {
    warning("[gemini] websocket error: $error");
    _logResponseFinished(reason: "socket.error");
    await onJsonEvent(RealtimeErrorEvent(message: error.toString()));
    await close();
    await onClosed();
  }

  Future<void> _sendProviderEvent(Map<String, Object?> payload) async {
    if (isClosed) return;
    socket?.add(jsonEncode(payload));
  }

  Future<void> _handleTurnDetection(
    Uint8List audioBytes,
    int rms,
    int chunkDurationMs,
  ) async {
    if (speechActive) {
      await _sendAudioChunk(audioBytes);
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
      lastActivityEndAtMs = _debugNowMs();
      info(
        "[gemini] user turn #$userTurnCount speech stopped at ${lastActivityEndAtMs}ms "
        "speechDuration=${currentSpeechDurationMs}ms chunks=$currentSpeechChunkCount "
        "silenceWindow=${config.turnDetection.speechEndSilenceMs}ms",
      );
      await onJsonEvent(const RealtimeInputSpeechStoppedEvent());
      await _sendProviderEvent(<String, Object?>{
        "realtimeInput": <String, Object?>{"activityEnd": <String, Object?>{}},
      });
      currentSpeechDurationMs = 0;
      currentSpeechChunkCount = 0;
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
    userTranscriptFinalizedForCurrentTurn = false;
    pendingUserTranscript = "";
    info(
      "[gemini] user turn #$userTurnCount speech started at ${_debugNowMs()}ms "
      "leadIn=${bufferedSpeechLeadInDurationMs}ms bufferedChunks=${bufferedSpeechLeadIn.length}",
    );
    await onJsonEvent(const RealtimeInputSpeechStartedEvent());
    await _sendProviderEvent(<String, Object?>{
      "realtimeInput": <String, Object?>{"activityStart": <String, Object?>{}},
    });

    List<BufferedAudioChunk> speechLeadIn = bufferedSpeechLeadIn;
    bufferedSpeechLeadIn = <BufferedAudioChunk>[];
    bufferedSpeechLeadInDurationMs = 0;
    for (BufferedAudioChunk chunk in speechLeadIn) {
      await _sendAudioChunk(chunk.audioBytes);
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

  Future<void> _sendAudioChunk(Uint8List audioBytes) async {
    await _sendProviderEvent(<String, Object?>{
      "realtimeInput": <String, Object?>{
        "audio": <String, Object?>{
          "data": base64Encode(audioBytes),
          "mimeType": "audio/pcm;rate=${config.inputSampleRate}",
        },
      },
    });
  }

  Map<String, Object?> _buildSetup() => <String, Object?>{
    "model": "models/${config.model}",
    "generationConfig": <String, Object?>{
      "responseModalities": <String>["AUDIO"],
      "speechConfig": <String, Object?>{
        "voiceConfig": <String, Object?>{
          "prebuiltVoiceConfig": <String, Object?>{
            "voiceName": _resolveVoiceName(config.voice),
          },
        },
      },
    },
    "realtimeInputConfig": <String, Object?>{
      "automaticActivityDetection": <String, Object?>{"disabled": true},
    },
    "systemInstruction": <String, Object?>{
      "parts": <Map<String, Object?>>[
        <String, Object?>{"text": config.instructions},
      ],
    },
    "inputAudioTranscription": <String, Object?>{},
    "outputAudioTranscription": <String, Object?>{},
    if (toolRegistry.hasTools) "tools": toolRegistry.geminiTools,
  };

  void _logProviderEvent(Map<String, Object?> event) {
    if (event.containsKey("usageMetadata")) return;
    if (event.containsKey("serverContent")) return;
    verbose("[gemini] event ${jsonEncode(event)}");
  }

  String _readTranscriptionText(Object? transcription) {
    Map<String, Object?>? value = _castObjectMap(transcription);
    return value?["text"]?.toString() ?? "";
  }

  Future<void> _emitTranscriptUpdate({
    required String text,
    required String speaker,
  }) async {
    if (speaker == "user" && userTranscriptFinalizedForCurrentTurn) return;
    if (speaker == "assistant" && assistantTranscriptFinalizedForCurrentTurn) {
      return;
    }

    String previous = speaker == "assistant"
        ? pendingAssistantTranscript
        : pendingUserTranscript;
    if (text.isEmpty || text == previous) return;

    String delta = text.startsWith(previous)
        ? text.substring(previous.length)
        : text;
    if (speaker == "assistant") {
      pendingAssistantTranscript = text;
    } else {
      pendingUserTranscript = text;
    }

    if (speaker == "assistant") {
      await onJsonEvent(RealtimeTranscriptAssistantDeltaEvent(text: delta));
      return;
    }

    await onJsonEvent(RealtimeTranscriptUserDeltaEvent(text: delta));
  }

  Future<void> _flushPendingTranscripts() async {
    if (pendingUserTranscript.isNotEmpty) {
      await onJsonEvent(
        RealtimeTranscriptUserFinalEvent(text: pendingUserTranscript),
      );
      userTranscriptFinalizedForCurrentTurn = true;
      pendingUserTranscript = "";
    }

    if (pendingAssistantTranscript.isNotEmpty) {
      if (assistantTurnInterrupted) {
        assistantTranscriptFinalizedForCurrentTurn = true;
        pendingAssistantTranscript = "";
        return;
      }
      await onJsonEvent(
        RealtimeTranscriptAssistantFinalEvent(text: pendingAssistantTranscript),
      );
      assistantTranscriptFinalizedForCurrentTurn = true;
      pendingAssistantTranscript = "";
    }
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

  String _resolveVoiceName(String requestedVoice) {
    String normalized = requestedVoice.trim().toLowerCase();
    if (normalized.isEmpty) {
      return RealtimeProviderCatalog.gemini.defaultVoice;
    }

    return switch (normalized) {
      "kore" => "Kore",
      "puck" => "Puck",
      "sage" => "Kore",
      _ => RealtimeProviderCatalog.gemini.defaultVoice,
    };
  }

  int _debugNowMs() => debugClock.elapsedMilliseconds;

  String _formatLatency(int currentMs, int startedAtMs) {
    if (startedAtMs < 0) {
      return "n/a";
    }
    return "${currentMs - startedAtMs}ms";
  }

  void _logResponseFinished({String reason = "turnComplete"}) {
    if (assistantTurnCount == 0 || responseStartedAtMs < 0) {
      return;
    }
    int finishedAtMs = _debugNowMs();
    String responseDuration = _formatLatency(finishedAtMs, responseStartedAtMs);
    String firstAudioLatency = firstAudioAtMs < 0
        ? "n/a"
        : _formatLatency(firstAudioAtMs, responseStartedAtMs);
    info(
      "[gemini] assistant turn #$assistantTurnCount finished via $reason at ${finishedAtMs}ms "
      "duration=$responseDuration firstAudio=$firstAudioLatency audioChunks=$responseAudioChunkCount "
      "assistantTextLength=${pendingAssistantTranscript.length} userTextLength=${pendingUserTranscript.length}",
    );
    responseStartedAtMs = -1;
    firstAudioAtMs = -1;
    responseAudioChunkCount = 0;
  }
}
