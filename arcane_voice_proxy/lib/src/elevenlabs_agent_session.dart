import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  final ProxyToolRegistry toolRegistry;
  late final ProviderSessionRuntime runtime;
  late final ProviderToolExecutionBridge toolExecutionBridge;
  late final AssistantOutputLifecycle assistantOutput;
  late final PassiveSpeechDetector speechDetector;

  WebSocket? socket;
  StreamSubscription<dynamic>? subscription;
  Timer? responseCompletionTimer;
  Timer? metadataFallbackTimer;
  bool sessionStarted = false;
  bool isClosed = false;
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
    required this.toolRegistry,
    required Future<void> Function(RealtimeServerMessage payload) onJsonEvent,
    required Future<void> Function(Uint8List audioBytes) onAudioChunk,
    required Future<void> Function() onClosed,
  }) {
    runtime = ProviderSessionRuntime(
      providerId: RealtimeProviderCatalog.elevenLabsId,
      providerLabel: "elevenlabs",
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: onJsonEvent,
      onAudioChunk: onAudioChunk,
      onClosed: onClosed,
    );
    toolExecutionBridge = ProviderToolExecutionBridge(runtime: runtime);
    assistantOutput = AssistantOutputLifecycle(runtime: runtime);
    speechDetector = PassiveSpeechDetector(runtime: runtime);
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
    await _ensureAgentConfigured(agentId);

    String signedUrl = await _getSignedUrl(agentId);
    WebSocket providerSocket = await WebSocket.connect(signedUrl);
    providerSocket.pingInterval = const Duration(seconds: 20);
    socket = providerSocket;
    subscription = providerSocket.listen(
      _handleProviderMessage,
      onDone: _handleProviderDone,
      onError: _handleProviderError,
      cancelOnError: true,
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
    if (isClosed) return;

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
    if (isClosed || text.trim().isEmpty) return;
    info("[elevenlabs] sending text input: $text");
    await _sendProviderEvent(<String, Object?>{
      "type": "user_message",
      "text": text,
    });
  }

  @override
  Future<void> interrupt() async {
    if (isClosed) return;
    info("[elevenlabs] interrupt requested");
    await _sendProviderEvent(<String, Object?>{"type": "user_activity"});
  }

  @override
  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    info("[elevenlabs] closing agent session");
    StreamSubscription<dynamic>? currentSubscription = subscription;
    WebSocket? currentSocket = socket;
    Timer? currentResponseCompletionTimer = responseCompletionTimer;
    Timer? currentMetadataFallbackTimer = metadataFallbackTimer;
    subscription = null;
    socket = null;
    responseCompletionTimer = null;
    metadataFallbackTimer = null;
    currentResponseCompletionTimer?.cancel();
    currentMetadataFallbackTimer?.cancel();
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

    Map<String, Object?> metadata = _castObjectMap(
          event["conversation_initiation_metadata_event"],
        ) ??
        <String, Object?>{};
    conversationId = metadata["conversation_id"]?.toString() ?? "";
    announcedInputSampleRate = _parsePcmSampleRate(
      metadata["user_input_audio_format"]?.toString(),
    );
    announcedOutputSampleRate = _parsePcmSampleRate(
      metadata["agent_output_audio_format"]?.toString(),
    );
    await _announceSessionStarted();
  }

  Future<void> _handlePing(Map<String, Object?> event) async {
    Map<String, Object?> pingEvent = _castObjectMap(event["ping_event"]) ??
        <String, Object?>{};
    Object? eventId = pingEvent["event_id"];
    if (eventId == null) return;
    await _sendProviderEvent(<String, Object?>{
      "type": "pong",
      "event_id": eventId,
    });
  }

  Future<void> _handleUserTranscript(Map<String, Object?> event) async {
    Map<String, Object?> transcriptEvent = _castObjectMap(
          event["user_transcription_event"],
        ) ??
        <String, Object?>{};
    String transcript = transcriptEvent["user_transcript"]?.toString() ?? "";
    if (transcript.isEmpty) return;

    info("[elevenlabs] user transcript final");
    await runtime.onJsonEvent(
      RealtimeTranscriptUserFinalEvent(text: transcript),
    );
  }

  Future<void> _handleAgentResponse(Map<String, Object?> event) async {
    Map<String, Object?> responseEvent = _castObjectMap(
          event["agent_response_event"],
        ) ??
        <String, Object?>{};
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
    Map<String, Object?> correctionEvent = _castObjectMap(
          event["agent_response_correction_event"],
        ) ??
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
    String? delta = assistantTranscriptBuffer.applySnapshot(correctedTranscript);
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
    String toolName = toolCall["tool_name"]?.toString() ?? "";
    String callId = toolCall["tool_call_id"]?.toString() ?? "";
    if (toolName.isEmpty || callId.isEmpty) return;

    info("[elevenlabs] executing tool $toolName");
    ToolExecutionInvocation invocation = toolExecutionBridge.createInvocation(
      callId: callId,
      name: toolName,
    );
    Map<String, Object?> arguments =
        _castObjectMap(toolCall["parameters"]) ?? <String, Object?>{};
    ToolExecutionResult output = await invocation.executeObject(
      arguments: arguments,
    );

    await _sendProviderEvent(<String, Object?>{
      "type": "client_tool_result",
      "tool_call_id": callId,
      "result": output.success
          ? _formatToolResultForElevenLabs(output.outputJson)
          : (output.error ?? "Unknown tool execution error."),
      "is_error": !output.success,
    });
    await invocation.emitCompleted(output);
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
    info(
      "[elevenlabs] agent tool response name=$toolName error=$isError",
    );
  }

  Future<void> _handleProviderErrorMessage(Map<String, Object?> event) async {
    warning("[elevenlabs] provider error event: ${jsonEncode(event)}");
    Map<String, Object?> providerError =
        _castObjectMap(event["error"]) ?? event;
    await runtime.emitError(
      message:
          providerError["message"]?.toString() ??
          "ElevenLabs conversation error",
      code: providerError["code"]?.toString(),
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
    if (sessionStarted || isClosed) return;
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
    if (!assistantOutput.isActive || isClosed) return;
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
    WebSocket? providerSocket = socket;
    Object closeCode = providerSocket?.closeCode ?? "n/a";
    String closeReason = providerSocket?.closeReason ?? "";
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
    unawaited(
      runtime.emitError(message: "ElevenLabs websocket error: $error"),
    );
  }

  Future<void> _ensureAgentConfigured(String agentId) async {
    Map<String, Object?> agent = await _fetchAgent(agentId);
    List<String> toolIds = await _ensureWorkspaceTools();
    Map<String, Object?> conversationConfig =
        _castObjectMap(agent["conversation_config"]) ?? <String, Object?>{};
    Map<String, Object?> nextConversationConfig =
        _buildConversationConfigUpdate(
          conversationConfig: conversationConfig,
          toolIds: toolIds,
        );
    if (_jsonEquals(conversationConfig, nextConversationConfig)) {
      return;
    }

    info("[elevenlabs] updating agent tool_ids/client_events");
    await _patchAgentConversationConfig(
      agentId: agentId,
      conversationConfig: nextConversationConfig,
    );
  }

  Future<List<String>> _ensureWorkspaceTools() async {
    if (!toolRegistry.hasTools) {
      return <String>[];
    }

    List<Map<String, Object?>> desiredTools = toolRegistry.elevenLabsClientTools;
    Map<String, Map<String, Object?>> existingToolsByName =
        await _fetchWorkspaceClientToolsByName();
    List<String> resolvedToolIds = <String>[];

    for (Map<String, Object?> desiredTool in desiredTools) {
      String toolName = desiredTool["name"]?.toString() ?? "";
      if (toolName.isEmpty) continue;

      Map<String, Object?>? existing = existingToolsByName[toolName];
      if (existing == null) {
        String createdToolId = await _createTool(desiredTool);
        resolvedToolIds = <String>[...resolvedToolIds, createdToolId];
        continue;
      }

      String toolId = existing["id"]?.toString() ?? "";
      Map<String, Object?> existingToolConfig =
          _castObjectMap(existing["tool_config"]) ?? <String, Object?>{};
      if (!_jsonEquals(existingToolConfig, desiredTool)) {
        await _updateTool(toolId: toolId, toolConfig: desiredTool);
      }
      if (toolId.isNotEmpty) {
        resolvedToolIds = <String>[...resolvedToolIds, toolId];
      }
    }

    return resolvedToolIds;
  }

  Map<String, Object?> _buildConversationConfigUpdate({
    required Map<String, Object?> conversationConfig,
    required List<String> toolIds,
  }) {
    Map<String, Object?> nextConversationConfig = _cloneObjectMap(
      conversationConfig,
    );
    Map<String, Object?> nextConversation = _cloneObjectMap(
      _castObjectMap(nextConversationConfig["conversation"]) ??
          <String, Object?>{},
    );
    List<String> clientEvents = _readStringList(nextConversation["client_events"]);
    List<String> requiredClientEvents = <String>[
      "audio",
      "user_transcript",
      "agent_response",
      "agent_response_correction",
      "client_tool_call",
      "interruption",
    ];
    nextConversation["client_events"] = _mergeUniqueStrings(
      existing: clientEvents,
      additions: requiredClientEvents,
    );
    nextConversationConfig["conversation"] = nextConversation;

    if (toolIds.isNotEmpty) {
      Map<String, Object?> nextAgent = _cloneObjectMap(
        _castObjectMap(nextConversationConfig["agent"]) ?? <String, Object?>{},
      );
      Map<String, Object?> nextPrompt = _cloneObjectMap(
        _castObjectMap(nextAgent["prompt"]) ?? <String, Object?>{},
      );
      List<String> existingToolIds = _readStringList(nextPrompt["tool_ids"]);
      nextPrompt["tool_ids"] = _mergeUniqueStrings(
        existing: existingToolIds,
        additions: toolIds,
      );
      nextAgent["prompt"] = nextPrompt;
      nextConversationConfig["agent"] = nextAgent;
    }

    return nextConversationConfig;
  }

  Future<Map<String, Map<String, Object?>>> _fetchWorkspaceClientToolsByName()
      async {
    Map<String, Object?> response = await _performJsonRequest(
      method: "GET",
      uri: Uri.https("api.elevenlabs.io", "/v1/convai/tools"),
    );
    Object? rawTools = response["tools"];
    if (rawTools is! List) {
      return <String, Map<String, Object?>>{};
    }

    Map<String, Map<String, Object?>> toolsByName =
        <String, Map<String, Object?>>{};
    for (Object? rawTool in rawTools) {
      Map<String, Object?>? tool = _castObjectMap(rawTool);
      if (tool == null) continue;

      Map<String, Object?> toolConfig =
          _castObjectMap(tool["tool_config"]) ?? <String, Object?>{};
      if (toolConfig["type"]?.toString() != "client") {
        continue;
      }
      String toolName = toolConfig["name"]?.toString() ?? "";
      if (toolName.isEmpty) continue;
      toolsByName[toolName] = tool;
    }
    return toolsByName;
  }

  Future<String> _createTool(Map<String, Object?> toolConfig) async {
    info("[elevenlabs] creating client tool ${toolConfig['name']}");
    Map<String, Object?> response = await _performJsonRequest(
      method: "POST",
      uri: Uri.https("api.elevenlabs.io", "/v1/convai/tools"),
      body: <String, Object?>{"tool_config": toolConfig},
    );
    return response["id"]?.toString() ?? "";
  }

  Future<void> _updateTool({
    required String toolId,
    required Map<String, Object?> toolConfig,
  }) async {
    if (toolId.isEmpty) return;
    info("[elevenlabs] updating client tool ${toolConfig['name']}");
    await _performJsonRequest(
      method: "PATCH",
      uri: Uri.https("api.elevenlabs.io", "/v1/convai/tools/$toolId"),
      body: <String, Object?>{"tool_config": toolConfig},
    );
  }

  Future<Map<String, Object?>> _fetchAgent(String agentId) =>
      _performJsonRequest(
        method: "GET",
        uri: Uri.https("api.elevenlabs.io", "/v1/convai/agents/$agentId"),
      );

  Future<void> _patchAgentConversationConfig({
    required String agentId,
    required Map<String, Object?> conversationConfig,
  }) async {
    await _performJsonRequest(
      method: "PATCH",
      uri: Uri.https("api.elevenlabs.io", "/v1/convai/agents/$agentId"),
      body: <String, Object?>{"conversation_config": conversationConfig},
    );
  }

  Future<String> _getSignedUrl(String agentId) async {
    Map<String, Object?> response = await _performJsonRequest(
      method: "GET",
      uri: Uri.https(
        "api.elevenlabs.io",
        "/v1/convai/conversation/get-signed-url",
        <String, String>{"agent_id": agentId},
      ),
    );
    String signedUrl = response["signed_url"]?.toString() ?? "";
    if (signedUrl.isEmpty) {
      throw StateError("ElevenLabs signed URL response did not include a URL.");
    }
    return signedUrl;
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

  Future<Map<String, Object?>> _performJsonRequest({
    required String method,
    required Uri uri,
    Map<String, Object?>? body,
  }) async {
    HttpClient client = HttpClient();
    HttpClientRequest request = await client.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, "application/json");
    request.headers.set("xi-api-key", apiKey);
    if (body != null) {
      request.headers.set(HttpHeaders.contentTypeHeader, "application/json");
      request.write(jsonEncode(body));
    }

    HttpClientResponse response = await request.close();
    String responseBody = await utf8.decoder.bind(response).join();
    client.close(force: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        "ElevenLabs $method ${uri.path} failed (${response.statusCode}): $responseBody",
        uri: uri,
      );
    }
    if (responseBody.trim().isEmpty) {
      return <String, Object?>{};
    }
    return JsonCodecHelper.decodeObject(responseBody);
  }

  Future<void> _sendProviderEvent(Map<String, Object?> event) async {
    if (isClosed) return;
    WebSocket? providerSocket = socket;
    if (providerSocket == null) return;
    providerSocket.add(jsonEncode(event.withoutNullValues));
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

  int _parsePcmSampleRate(String? format) {
    if (format == null || format.isEmpty) {
      return defaultPcmSampleRate;
    }
    RegExp matchPattern = RegExp(r"_(\d+)$");
    RegExpMatch? match = matchPattern.firstMatch(format);
    if (match == null) {
      return defaultPcmSampleRate;
    }
    return int.tryParse(match.group(1) ?? "") ?? defaultPcmSampleRate;
  }

  Map<String, Object?> _cloneObjectMap(Map<String, Object?> source) =>
      <String, Object?>{
        for (MapEntry<String, Object?> entry in source.entries)
          entry.key: _cloneJsonValue(entry.value),
      };

  Object? _cloneJsonValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return _cloneObjectMap(value.cast<String, Object?>());
    }
    if (value is List<dynamic>) {
      return <Object?>[
        for (Object? item in value) _cloneJsonValue(item),
      ];
    }
    return value;
  }

  Map<String, Object?>? _castObjectMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.cast<String, Object?>();
    }
    return null;
  }

  List<String> _readStringList(Object? value) => switch (value) {
    List<dynamic> listValue => <String>[
      for (Object? item in listValue)
        if (item != null && item.toString().isNotEmpty) item.toString(),
    ],
    _ => <String>[],
  };

  List<String> _mergeUniqueStrings({
    required List<String> existing,
    required List<String> additions,
  }) {
    Set<String> values = <String>{...existing};
    for (String value in additions) {
      if (value.isNotEmpty) {
        values = <String>{...values, value};
      }
    }
    return values.toList();
  }

  Object? _decodeJsonValue(String source) {
    if (source.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(source);
    } catch (_) {
      return source;
    }
  }

  Object? _formatToolResultForElevenLabs(String outputJson) {
    Object? decoded = _decodeJsonValue(outputJson);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }
    if (decoded is String) {
      return decoded;
    }
    return jsonEncode(decoded);
  }

  bool _jsonEquals(Object? left, Object? right) => jsonEncode(left) == jsonEncode(right);

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

class PassiveSpeechDetector {
  final ProviderSessionRuntime runtime;

  bool speechActive = false;
  int userTurnCount = 0;
  int loudDurationMs = 0;
  int silentDurationMs = 0;
  int currentSpeechDurationMs = 0;
  int currentSpeechChunkCount = 0;

  PassiveSpeechDetector({required this.runtime});

  Future<void> observeAudio({
    required Uint8List audioBytes,
    required ProxyTurnStartHandler onSpeechStarted,
    required ProxyTurnStopHandler onSpeechStopped,
  }) async {
    int rms = Pcm16LevelMeter.computeRms(audioBytes);
    int chunkDurationMs = Pcm16ChunkTiming.chunkDurationMs(
      audioBytes: audioBytes,
      sampleRate: runtime.config.inputSampleRate,
    );

    if (speechActive) {
      currentSpeechDurationMs += chunkDurationMs;
      currentSpeechChunkCount++;
      if (rms >= runtime.config.turnDetection.speechThresholdRms) {
        silentDurationMs = 0;
        return;
      }

      silentDurationMs += chunkDurationMs;
      if (silentDurationMs < runtime.config.turnDetection.speechEndSilenceMs) {
        return;
      }

      speechActive = false;
      loudDurationMs = 0;
      silentDurationMs = 0;
      ProxySpeechStopEvent stopEvent = ProxySpeechStopEvent(
        turnNumber: userTurnCount,
        stoppedAtMs: runtime.nowMs,
        speechDurationMs: currentSpeechDurationMs,
        speechChunkCount: currentSpeechChunkCount,
        silenceWindowMs: runtime.config.turnDetection.speechEndSilenceMs,
      );
      currentSpeechDurationMs = 0;
      currentSpeechChunkCount = 0;
      await onSpeechStopped(stopEvent);
      return;
    }

    if (rms < runtime.config.turnDetection.speechThresholdRms) {
      loudDurationMs = 0;
      return;
    }

    loudDurationMs += chunkDurationMs;
    if (loudDurationMs < runtime.config.turnDetection.speechStartMs) {
      return;
    }

    speechActive = true;
    userTurnCount++;
    silentDurationMs = 0;
    loudDurationMs = 0;
    currentSpeechDurationMs = 0;
    currentSpeechChunkCount = 0;
    ProxySpeechStartEvent startEvent = ProxySpeechStartEvent(
      turnNumber: userTurnCount,
      startedAtMs: runtime.nowMs,
      leadInDurationMs: 0,
      bufferedChunkCount: 0,
    );
    await onSpeechStarted(startEvent);
  }
}
