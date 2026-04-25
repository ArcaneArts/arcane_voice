import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

class ElevenLabsAgentSession implements RealtimeProviderSession {
  static const int audioLogInterval = 100;
  static const int defaultPcmSampleRate = 16000;
  static const int responseIdleDebounceMs = 450;
  static const int responseTextFallbackMs = 1200;
  static const int metadataFallbackMs = 900;

  final String apiKey;
  final RealtimeSessionConfig config;
  final ArcaneVoiceProxyVadMode vadMode;
  final ProxyToolRegistry toolRegistry;
  late final ProviderSessionRuntime runtime;
  late final ProviderToolExecutionBridge toolExecutionBridge;
  late final AssistantOutputLifecycle assistantOutput;
  late final PassiveSpeechDetector speechDetector;
  late final ProviderJsonSocketConnection connection;
  late final ElevenLabsAgentApiClient agentApiClient;
  late final ElevenLabsAgentConfigurator agentConfigurator;

  Timer? responseCompletionTimer;
  Timer? metadataFallbackTimer;
  bool sessionStarted = false;
  int upstreamAudioChunkCount = 0;
  int downstreamAudioChunkCount = 0;
  int lastUserSpeechStoppedAtMs = -1;
  int announcedInputSampleRate = defaultPcmSampleRate;
  int announcedOutputSampleRate = defaultPcmSampleRate;
  String conversationId = "";
  final MonotonicTranscriptBuffer assistantTranscriptBuffer =
      MonotonicTranscriptBuffer();

  ElevenLabsAgentSession({
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
      providerId: RealtimeProviderCatalog.elevenLabsId,
      providerLabel: "elevenlabs",
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
    speechDetector = PassiveSpeechDetector(runtime: runtime);
    connection = ProviderJsonSocketConnection(providerLabel: "elevenlabs");
    agentApiClient = ElevenLabsAgentApiClient(apiKey: apiKey);
    agentConfigurator = ElevenLabsAgentConfigurator(
      apiClient: agentApiClient,
      toolRegistry: toolRegistry,
    );
  }

  @override
  Future<void> start() async {
    String agentId = _requireAgentId();
    info(
      "[elevenlabs] preparing agent session model=${config.model} agentId=$agentId",
    );
    runtime.startDebugClock();
    runtime.logTurnDebug();
    await runtime.emitConnecting();
    await agentConfigurator.ensureAgentConfigured(agentId);

    String signedUrl = await agentApiClient.getSignedUrl(agentId);
    await connection.connect(
      url: signedUrl,
      onMessage: _handleProviderMessage,
      onDone: _handleProviderDone,
      onError: _handleProviderError,
    );

    info("[elevenlabs] websocket connected");
    await _sendProviderEvent(_buildConversationInitiationPayload());
    info("[elevenlabs] conversation initiation sent");
    metadataFallbackTimer = Timer(
      const Duration(milliseconds: metadataFallbackMs),
      _handleMetadataFallbackTimeout,
    );
  }

  @override
  Future<void> sendAudio(Uint8List audioBytes) async {
    if (connection.isClosed) return;

    upstreamAudioChunkCount++;
    if (upstreamAudioChunkCount <= 5 ||
        upstreamAudioChunkCount % audioLogInterval == 0) {
      info(
        "[elevenlabs] upstream audio chunk #$upstreamAudioChunkCount (${audioBytes.length} bytes)",
      );
    }

    await _sendProviderEvent(<String, Object?>{
      "user_audio_chunk": base64Encode(audioBytes),
    });
    await speechDetector.observeAudio(
      audioBytes: audioBytes,
      onSpeechStarted: _handleSpeechStarted,
      onSpeechStopped: _handleSpeechStopped,
    );
  }

  @override
  Future<void> sendText(String text) async {
    if (connection.isClosed || text.trim().isEmpty) return;
    info("[elevenlabs] sending text input: $text");
    await _sendProviderEvent(<String, Object?>{
      "type": "user_message",
      "text": text,
    });
  }

  @override
  Future<void> interrupt() async {
    if (connection.isClosed) return;
    info("[elevenlabs] interrupt requested");
    await _sendProviderEvent(<String, Object?>{"type": "user_activity"});
  }

  @override
  Future<void> close() async {
    Timer? currentResponseCompletionTimer = responseCompletionTimer;
    Timer? currentMetadataFallbackTimer = metadataFallbackTimer;
    responseCompletionTimer = null;
    metadataFallbackTimer = null;
    currentResponseCompletionTimer?.cancel();
    currentMetadataFallbackTimer?.cancel();
    await connection.close(closeMessage: "closing agent session");
  }

  Future<void> _handleProviderMessage(dynamic message) async {
    Map<String, Object?>? event = decodeProviderJsonMessage(message);
    if (event == null) return;
    String type = event["type"]?.toString() ?? "";
    _logProviderEvent(type, event);

    if (type == "conversation_initiation_metadata") {
      await _handleConversationMetadata(event);
      return;
    }

    if (type == "ping") {
      await _handlePing(event);
      return;
    }

    if (type == "user_transcript") {
      await _handleUserTranscript(event);
      return;
    }

    if (type == "agent_response") {
      await _handleAgentResponse(event);
      return;
    }

    if (type == "agent_response_correction") {
      await _handleAgentResponseCorrection(event);
      return;
    }

    if (type == "audio") {
      await _handleAudio(event);
      return;
    }

    if (type == "client_tool_call") {
      await _handleToolCall(event);
      return;
    }

    if (type == "interruption") {
      await _handleInterruption();
      return;
    }

    if (type == "agent_tool_response") {
      _logAgentToolResponse(event);
      return;
    }

    if (type == "error") {
      await _handleProviderErrorMessage(event);
    }
  }

  Future<void> _handleConversationMetadata(Map<String, Object?> event) async {
    Timer? currentMetadataFallbackTimer = metadataFallbackTimer;
    metadataFallbackTimer = null;
    currentMetadataFallbackTimer?.cancel();

    Map<String, Object?> metadata =
        _castObjectMap(event["conversation_initiation_metadata_event"]) ??
        <String, Object?>{};
    conversationId = metadata["conversation_id"]?.toString() ?? "";
    announcedInputSampleRate = parseElevenLabsPcmSampleRate(
      metadata["user_input_audio_format"]?.toString(),
      defaultSampleRate: defaultPcmSampleRate,
    );
    announcedOutputSampleRate = parseElevenLabsPcmSampleRate(
      metadata["agent_output_audio_format"]?.toString(),
      defaultSampleRate: defaultPcmSampleRate,
    );
    await runtime.emitUsage(
      ArcaneVoiceProxyUsage(
        provider: RealtimeProviderCatalog.elevenLabsId,
        raw: <String, Object?>{
          "conversationId": conversationId,
          "userInputAudioFormat": metadata["user_input_audio_format"],
          "agentOutputAudioFormat": metadata["agent_output_audio_format"],
        },
      ),
    );
    await _announceSessionStarted();
  }

  Future<void> _handlePing(Map<String, Object?> event) async {
    Map<String, Object?> pingEvent =
        _castObjectMap(event["ping_event"]) ?? <String, Object?>{};
    Object? eventId = pingEvent["event_id"];
    if (eventId == null) return;
    await _sendProviderEvent(<String, Object?>{
      "type": "pong",
      "event_id": eventId,
    });
  }

  Future<void> _handleUserTranscript(Map<String, Object?> event) async {
    Map<String, Object?> transcriptEvent =
        _castObjectMap(event["user_transcription_event"]) ??
        <String, Object?>{};
    String transcript = transcriptEvent["user_transcript"]?.toString() ?? "";
    if (transcript.isEmpty) return;

    info("[elevenlabs] user transcript final");
    await runtime.onJsonEvent(
      RealtimeTranscriptUserFinalEvent(text: transcript),
    );
  }

  Future<void> _handleAgentResponse(Map<String, Object?> event) async {
    Map<String, Object?> responseEvent =
        _castObjectMap(event["agent_response_event"]) ?? <String, Object?>{};
    String transcript = responseEvent["agent_response"]?.toString() ?? "";
    if (transcript.isEmpty) return;

    await assistantOutput.ensureStarted(
      trigger: "transcript",
      referenceAtMs: lastUserSpeechStoppedAtMs,
      referenceLabel: "user stop",
    );
    if (!assistantTranscriptBuffer.hasValue) {
      assistantTranscriptBuffer.startTurn();
    }

    String? delta = assistantTranscriptBuffer.applySnapshot(transcript);
    if (delta != null) {
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(text: delta),
      );
    }
    _scheduleResponseCompletion(
      const Duration(milliseconds: responseTextFallbackMs),
    );
  }

  Future<void> _handleAgentResponseCorrection(
    Map<String, Object?> event,
  ) async {
    Map<String, Object?> correctionEvent =
        _castObjectMap(event["agent_response_correction_event"]) ??
        <String, Object?>{};
    String correctedTranscript =
        correctionEvent["corrected_agent_response"]?.toString() ?? "";
    if (correctedTranscript.isEmpty) return;

    info("[elevenlabs] assistant response corrected");
    await assistantOutput.ensureStarted(
      trigger: "transcript.correction",
      referenceAtMs: lastUserSpeechStoppedAtMs,
      referenceLabel: "user stop",
    );
    if (assistantTranscriptBuffer.hasValue) {
      assistantTranscriptBuffer.discard();
      await runtime.onJsonEvent(
        const RealtimeTranscriptAssistantDiscardEvent(),
      );
    }

    assistantTranscriptBuffer.startTurn();
    String? delta = assistantTranscriptBuffer.applySnapshot(
      correctedTranscript,
    );
    if (delta != null) {
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantDeltaEvent(text: delta),
      );
    }
    _scheduleResponseCompletion(
      const Duration(milliseconds: responseTextFallbackMs),
    );
  }

  Future<void> _handleAudio(Map<String, Object?> event) async {
    Map<String, Object?> audioEvent =
        _castObjectMap(event["audio_event"]) ?? <String, Object?>{};
    String audioBase64 = audioEvent["audio_base_64"]?.toString() ?? "";
    if (audioBase64.isEmpty) return;

    await assistantOutput.ensureStarted(
      trigger: "audio",
      referenceAtMs: lastUserSpeechStoppedAtMs,
      referenceLabel: "user stop",
    );
    assistantOutput.recordAudioChunk();
    downstreamAudioChunkCount++;
    if (downstreamAudioChunkCount == 1 ||
        downstreamAudioChunkCount % audioLogInterval == 0) {
      info("[elevenlabs] downstream audio chunk #$downstreamAudioChunkCount");
    }
    await runtime.emitAudio(base64Decode(audioBase64));
    _scheduleResponseCompletion(
      const Duration(milliseconds: responseIdleDebounceMs),
    );
  }

  Future<void> _handleToolCall(Map<String, Object?> event) async {
    Map<String, Object?> toolCall =
        _castObjectMap(event["client_tool_call"]) ?? <String, Object?>{};
    Map<String, Object?> arguments =
        _castObjectMap(toolCall["parameters"]) ?? <String, Object?>{};
    await toolExecutionBridge.executeObjectToolCall(
      providerLabel: "elevenlabs",
      callId: toolCall["tool_call_id"]?.toString(),
      name: toolCall["tool_name"]?.toString(),
      arguments: arguments,
      onResult: (ToolExecutionResult output) async {
        await _sendProviderEvent(<String, Object?>{
          "type": "client_tool_result",
          "tool_call_id": output.callId,
          "result": output.success
              ? formatElevenLabsToolResult(output.outputJson)
              : (output.error ?? "Unknown tool execution error."),
          "is_error": !output.success,
        });
      },
    );
  }

  Future<void> _handleInterruption() async {
    info("[elevenlabs] interruption received");
    Timer? currentResponseCompletionTimer = responseCompletionTimer;
    responseCompletionTimer = null;
    currentResponseCompletionTimer?.cancel();
    if (!assistantOutput.isActive) return;

    if (assistantTranscriptBuffer.hasValue) {
      assistantTranscriptBuffer.discard();
      await runtime.onJsonEvent(
        const RealtimeTranscriptAssistantDiscardEvent(),
      );
    }
    assistantOutput.logFinished(reason: "interruption");
    assistantOutput.reset();
  }

  void _logAgentToolResponse(Map<String, Object?> event) {
    Map<String, Object?> toolResponse =
        _castObjectMap(event["agent_tool_response"]) ?? <String, Object?>{};
    String toolName = toolResponse["tool_name"]?.toString() ?? "";
    bool isError = toolResponse["is_error"] == true;
    if (toolName.isEmpty) return;
    info("[elevenlabs] agent tool response name=$toolName error=$isError");
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    await emitProviderErrorFromEvent(
      runtime: runtime,
      providerLabel: "elevenlabs",
      event: event,
      defaultMessage: "ElevenLabs conversation error",
    );
  }

  Future<void> _announceSessionStarted() async {
    if (sessionStarted) return;
    sessionStarted = true;
    info(
      "[elevenlabs] session ready conversationId=$conversationId input=$announcedInputSampleRate output=$announcedOutputSampleRate",
    );
    await runtime.emitSessionStarted(
      inputSampleRate: announcedInputSampleRate,
      outputSampleRate: announcedOutputSampleRate,
    );
  }

  void _handleMetadataFallbackTimeout() {
    if (sessionStarted || connection.isClosed) return;
    warning(
      "[elevenlabs] metadata did not arrive in time, assuming pcm_16000 session",
    );
    announcedInputSampleRate = defaultPcmSampleRate;
    announcedOutputSampleRate = defaultPcmSampleRate;
    unawaited(_announceSessionStarted());
  }

  Future<void> _handleSpeechStarted(ProxySpeechStartEvent event) async {
    info(
      "[elevenlabs] user turn #${event.turnNumber} speech started at ${event.startedAtMs}ms",
    );
    await runtime.emitSpeechStarted();
  }

  Future<void> _handleSpeechStopped(ProxySpeechStopEvent event) async {
    lastUserSpeechStoppedAtMs = event.stoppedAtMs;
    info(
      "[elevenlabs] user turn #${event.turnNumber} speech stopped at ${event.stoppedAtMs}ms "
      "speechDuration=${event.speechDurationMs}ms chunks=${event.speechChunkCount} "
      "silenceWindow=${event.silenceWindowMs}ms",
    );
    await runtime.emitSpeechStopped();
  }

  void _scheduleResponseCompletion(Duration delay) {
    Timer? currentTimer = responseCompletionTimer;
    currentTimer?.cancel();
    responseCompletionTimer = Timer(delay, _handleResponseCompletionTimeout);
  }

  void _handleResponseCompletionTimeout() {
    if (!assistantOutput.isActive || connection.isClosed) return;
    unawaited(_finalizeAssistantOutput(reason: "audio.idle"));
  }

  Future<void> _finalizeAssistantOutput({required String reason}) async {
    Timer? currentTimer = responseCompletionTimer;
    responseCompletionTimer = null;
    currentTimer?.cancel();

    String? transcript = assistantTranscriptBuffer.finalizeText();
    if (transcript != null) {
      info("[elevenlabs] assistant transcript final");
      await runtime.onJsonEvent(
        RealtimeTranscriptAssistantFinalEvent(text: transcript),
      );
    }
    await assistantOutput.completeAndNotify(reason: reason);
  }

  Future<void> _handleProviderDone() async {
    Object closeCode = connection.closeCode ?? "n/a";
    String closeReason = connection.closeReason ?? "";
    info(
      "[elevenlabs] websocket done code=$closeCode reason=${closeReason.isEmpty ? 'n/a' : closeReason}",
    );
    Timer? currentResponseCompletionTimer = responseCompletionTimer;
    responseCompletionTimer = null;
    currentResponseCompletionTimer?.cancel();
    if (assistantOutput.isActive) {
      await _finalizeAssistantOutput(reason: "socket.done");
    }
    await close();
    await runtime.notifyClosed();
  }

  void _handleProviderError(Object error) {
    warning("[elevenlabs] websocket error: $error");
    unawaited(runtime.emitError(message: "ElevenLabs websocket error: $error"));
  }

  Map<String, Object?> _buildConversationInitiationPayload() {
    Map<String, Object?> payload = <String, Object?>{
      "type": "conversation_initiation_client_data",
    };
    Map<String, Object?> providerOptions = config.providerOptions;
    Map<String, Object?>? conversationConfigOverride = _castObjectMap(
      providerOptions["conversationConfigOverride"],
    );
    Map<String, Object?>? customLlmExtraBody = _castObjectMap(
      providerOptions["customLlmExtraBody"],
    );
    Map<String, Object?>? dynamicVariables = _castObjectMap(
      providerOptions["dynamicVariables"],
    );

    if (conversationConfigOverride != null &&
        conversationConfigOverride.isNotEmpty) {
      payload["conversation_config_override"] = conversationConfigOverride;
    }
    if (customLlmExtraBody != null && customLlmExtraBody.isNotEmpty) {
      payload["custom_llm_extra_body"] = customLlmExtraBody;
    }
    if (dynamicVariables != null && dynamicVariables.isNotEmpty) {
      payload["dynamic_variables"] = dynamicVariables;
    }

    return payload.withoutNullValues;
  }

  Future<void> _sendProviderEvent(Map<String, Object?> event) async {
    await connection.sendJson(event.withoutNullValues);
  }

  String _requireAgentId() {
    String agentId = config.providerOptions["agentId"]?.toString().trim() ?? "";
    if (agentId.isEmpty) {
      throw StateError(
        "ElevenLabs requires providerOptionsJson to include an agentId.",
      );
    }
    return agentId;
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

  void _logProviderEvent(String type, Map<String, Object?> event) {
    if (type.isEmpty) {
      verbose("[elevenlabs] event ${jsonEncode(event)}");
      return;
    }

    switch (type) {
      case "audio":
      case "vad_score":
      case "user_transcript":
      case "agent_response":
      case "agent_response_correction":
      case "client_tool_call":
      case "interruption":
      case "ping":
      case "conversation_initiation_metadata":
        return;
      default:
        verbose("[elevenlabs] event $type ${jsonEncode(event)}");
    }
  }
}
