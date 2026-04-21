import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/elevenlabs_agent_session.dart';
import 'package:arcane_voice_proxy/src/gemini_live_session.dart';
import 'package:arcane_voice_proxy/src/grok_voice_session.dart';
import 'package:arcane_voice_proxy/src/openai_realtime_session.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

int _gatewaySessionCounter = 0;

String _nextGatewaySessionId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_gatewaySessionCounter++).toRadixString(36)}';

class ArcaneVoiceProxyEnvironment {
  final String? definedOpenAiApiKey;
  final String? definedGeminiApiKey;
  final String? definedXAiApiKey;
  final String? definedElevenLabsApiKey;
  final bool usePlatformFallbacks;
  final Map<String, String>? platformEnvironment;

  const ArcaneVoiceProxyEnvironment({
    String? openAiApiKey,
    String? geminiApiKey,
    String? xAiApiKey,
    String? elevenLabsApiKey,
    this.usePlatformFallbacks = false,
    this.platformEnvironment,
  }) : definedOpenAiApiKey = openAiApiKey,
       definedGeminiApiKey = geminiApiKey,
       definedXAiApiKey = xAiApiKey,
       definedElevenLabsApiKey = elevenLabsApiKey;

  const ArcaneVoiceProxyEnvironment.withPlatformFallbacks({
    String? openAiApiKey,
    String? geminiApiKey,
    String? xAiApiKey,
    String? elevenLabsApiKey,
    Map<String, String>? platformEnvironment,
  }) : this(
         openAiApiKey: openAiApiKey,
         geminiApiKey: geminiApiKey,
         xAiApiKey: xAiApiKey,
         elevenLabsApiKey: elevenLabsApiKey,
         usePlatformFallbacks: true,
         platformEnvironment: platformEnvironment,
       );

  factory ArcaneVoiceProxyEnvironment.fromPlatform() =>
      const ArcaneVoiceProxyEnvironment.withPlatformFallbacks();

  String? get openAiApiKey => _resolveApiKey(
    explicitValue: definedOpenAiApiKey,
    environmentName: 'OPENAI_API_KEY',
  );

  String? get geminiApiKey => _resolveApiKey(
    explicitValue: definedGeminiApiKey,
    environmentName: 'GEMINI_API_KEY',
  );

  String? get xAiApiKey => _resolveApiKey(
    explicitValue: definedXAiApiKey,
    environmentName: 'XAI_API_KEY',
  );

  String? get elevenLabsApiKey => _resolveApiKey(
    explicitValue: definedElevenLabsApiKey,
    environmentName: 'ELEVENLABS_API_KEY',
  );

  String? apiKeyForProvider(String provider) => switch (provider) {
    RealtimeProviderCatalog.geminiId => geminiApiKey,
    RealtimeProviderCatalog.grokId => xAiApiKey,
    RealtimeProviderCatalog.elevenLabsId => elevenLabsApiKey,
    _ => openAiApiKey,
  };

  String? _resolveApiKey({
    required String? explicitValue,
    required String environmentName,
  }) {
    String? normalizedExplicitValue = _normalizeApiKey(explicitValue);
    if (normalizedExplicitValue != null) {
      return normalizedExplicitValue;
    }
    if (!usePlatformFallbacks) {
      return null;
    }
    return _normalizeApiKey(_environment[environmentName]);
  }

  Map<String, String> get _environment =>
      platformEnvironment ?? Platform.environment;

  static String? _normalizeApiKey(String? value) {
    if (value == null) {
      return null;
    }
    String normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      return null;
    }
    return normalizedValue;
  }
}

class RealtimeGateway {
  final ArcaneVoiceProxyEnvironment environment;
  final ArcaneVoiceProxyToolRegistry proxyTools;
  final ArcaneVoiceProxySessionResolver? sessionResolver;
  final ArcaneVoiceProxyLifecycleCallbacks lifecycleCallbacks;

  RealtimeGateway({
    required this.environment,
    ArcaneVoiceProxyToolRegistry? proxyTools,
    this.sessionResolver,
    this.lifecycleCallbacks = const ArcaneVoiceProxyLifecycleCallbacks(),
  }) : proxyTools = proxyTools ?? ArcaneVoiceProxyToolRegistry.empty();

  Future<void> handleSocket(
    WebSocket socket, {
    ArcaneVoiceProxyConnectionInfo connectionInfo =
        const ArcaneVoiceProxyConnectionInfo(),
  }) {
    socket.pingInterval = const Duration(seconds: 20);
    return handleChannel(
      IOWebSocketChannel(socket),
      connectionInfo: connectionInfo,
    );
  }

  Future<void> handleChannel(
    WebSocketChannel channel, {
    ArcaneVoiceProxyConnectionInfo connectionInfo =
        const ArcaneVoiceProxyConnectionInfo(),
  }) => RealtimeGatewaySession(
    channel: channel,
    environment: environment,
    proxyTools: proxyTools,
    sessionResolver: sessionResolver,
    lifecycleCallbacks: lifecycleCallbacks,
    connectionInfo: connectionInfo,
  ).run();
}

class RealtimeGatewaySession {
  final WebSocketChannel channel;
  final ArcaneVoiceProxyEnvironment environment;
  final ArcaneVoiceProxyToolRegistry proxyTools;
  final ArcaneVoiceProxySessionResolver? sessionResolver;
  final ArcaneVoiceProxyLifecycleCallbacks lifecycleCallbacks;
  final ArcaneVoiceProxyConnectionInfo connectionInfo;

  final String sessionId = _nextGatewaySessionId();
  final DateTime connectedAt = DateTime.now();

  RealtimeProviderSession? providerSession;
  bool isClosed = false;
  bool sessionStopEventSent = false;
  bool sessionStopNotified = false;
  int clientAudioChunkCount = 0;
  int clientAudioBytes = 0;
  int assistantAudioBytes = 0;
  int proxyToolCalls = 0;
  int clientToolCalls = 0;
  String stopReason = 'client.disconnected';
  String? stopError;
  DateTime? sessionStartedAt;
  RealtimeSessionStartRequest? startRequest;
  RealtimeSessionConfig? activeConfig;
  String? activeProvider;
  Object? activeContext;
  ArcaneVoiceProxyUsage? accumulatedUsage;
  Map<String, Completer<String>> pendingClientToolCalls =
      <String, Completer<String>>{};

  RealtimeGatewaySession({
    required this.channel,
    required this.environment,
    required this.proxyTools,
    required this.sessionResolver,
    required this.lifecycleCallbacks,
    required this.connectionInfo,
  });

  Future<void> run() async {
    info("[gateway] client connected session=$sessionId");
    await sendMessage(
      RealtimeConnectionReadyEvent(
        providers: RealtimeProviderCatalog.ids,
        defaultModel: RealtimeProviderCatalog.openAi.defaultModel,
        defaultVoice: RealtimeProviderCatalog.openAi.defaultVoice,
      ),
    );

    try {
      await for (dynamic message in channel.stream) {
        await _handleSocketMessage(message);
      }
    } catch (_) {}

    await close();
  }

  Future<void> _handleSocketMessage(dynamic message) async {
    if (message is String) {
      try {
        RealtimeClientMessage payload = RealtimeProtocolCodec.decodeClientJson(
          message,
        );
        verbose("[gateway] client json ${payload.type}");
        await _handleJsonMessage(payload);
      } catch (error) {
        await sendError(error.toString());
      }
      return;
    }

    if (message is Uint8List) {
      _logClientAudioChunk(message.length);
      await providerSession?.sendAudio(message);
      return;
    }

    if (message is List<int>) {
      Uint8List audioBytes = Uint8List.fromList(message);
      _logClientAudioChunk(audioBytes.length);
      await providerSession?.sendAudio(audioBytes);
    }
  }

  Future<void> _handleJsonMessage(RealtimeClientMessage payload) async {
    if (payload is RealtimeSessionStartRequest) {
      await _startProvider(payload);
      return;
    }

    if (payload is RealtimeSessionStopRequest) {
      stopReason = 'client.stop';
      await _emitSessionStoppedToClient();
      await close();
      return;
    }

    if (payload is RealtimeSessionInterruptRequest) {
      await providerSession?.interrupt();
      return;
    }

    if (payload is RealtimeTextInputRequest) {
      if (payload.text.isEmpty) return;
      await providerSession?.sendText(payload.text);
      return;
    }

    if (payload is RealtimePingRequest) {
      await sendMessage(const RealtimePongEvent());
      return;
    }

    if (payload is RealtimeToolResultRequest) {
      _completeClientTool(payload);
    }
  }

  Future<void> _startProvider(RealtimeSessionStartRequest payload) async {
    if (providerSession != null) {
      await sendError('A realtime session is already active.');
      return;
    }

    startRequest = payload;

    ArcaneVoiceProxyResolvedSession resolvedSession;
    try {
      resolvedSession = await _resolveSession(payload);
    } catch (error) {
      stopReason = 'session.resolve.error';
      stopError = error.toString();
      await sendError(stopError!);
      await close();
      return;
    }

    String provider = resolvedSession.provider.trim();
    if (RealtimeProviderCatalog.maybeById(provider) == null) {
      await sendError('Unsupported provider: $provider');
      return;
    }

    String? apiKey = environment.apiKeyForProvider(provider);
    if (apiKey == null || apiKey.isEmpty) {
      await sendError(_missingApiKeyMessage(provider));
      return;
    }

    RealtimeSessionConfig config = resolvedSession.config;
    ProxyToolRegistry toolRegistry =
        ProxyToolRegistry(
          proxyTools: resolvedSession.proxyTools,
        ).bindClientTools(
          clientTools: payload.clientTools,
          clientToolInvoker: _invokeClientTool,
        );

    activeProvider = provider;
    activeConfig = config;
    activeContext = resolvedSession.context;
    info(
      "[gateway] starting session=$sessionId provider=$provider model=${config.model} voice=${config.voice}",
    );

    providerSession = _buildProviderSession(
      provider: provider,
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
    );

    try {
      await providerSession?.start();
      sessionStartedAt ??= DateTime.now();
      await _notifySessionStarted(payload, provider, config);
    } catch (error) {
      stopReason = 'session.start.error';
      stopError = error.toString();
      await sendError(stopError!);
      await close();
    }
  }

  Future<ArcaneVoiceProxyResolvedSession> _resolveSession(
    RealtimeSessionStartRequest payload,
  ) async {
    ArcaneVoiceProxySessionResolver? resolver = sessionResolver;
    if (resolver == null) {
      return ArcaneVoiceProxyResolvedSession.passthrough(
        request: payload,
        proxyTools: proxyTools,
      );
    }

    return await resolver(
      ArcaneVoiceProxySessionRequest(
        sessionId: sessionId,
        connectionInfo: connectionInfo,
        request: payload,
        receivedAt: DateTime.now(),
      ),
    );
  }

  RealtimeProviderSession _buildProviderSession({
    required String provider,
    required String apiKey,
    required RealtimeSessionConfig config,
    required ProxyToolRegistry toolRegistry,
  }) => switch (provider) {
    RealtimeProviderCatalog.geminiId => GeminiLiveSession(
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: sendMessage,
      onAudioChunk: sendAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
    RealtimeProviderCatalog.grokId => GrokVoiceSession(
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: sendMessage,
      onAudioChunk: sendAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
    RealtimeProviderCatalog.elevenLabsId => ElevenLabsAgentSession(
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: sendMessage,
      onAudioChunk: sendAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
    _ => OpenAiRealtimeSession(
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: sendMessage,
      onAudioChunk: sendAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
  };

  String _missingApiKeyMessage(String provider) => switch (provider) {
    RealtimeProviderCatalog.geminiId =>
      'GEMINI_API_KEY is missing on the server. Set it before starting a Gemini call.',
    RealtimeProviderCatalog.grokId =>
      'XAI_API_KEY is missing on the server. Set it before starting a Grok call.',
    RealtimeProviderCatalog.elevenLabsId =>
      'ELEVENLABS_API_KEY is missing on the server. Set it before starting an ElevenLabs call.',
    _ =>
      'OPENAI_API_KEY is missing on the server. Set it before starting an OpenAI call.',
  };

  Future<void> _handleProviderClosed() async {
    if (isClosed) {
      return;
    }
    info("[gateway] provider session closed session=$sessionId");
    stopReason = stopError == null ? 'provider.closed' : stopReason;
    await _emitSessionStoppedToClient();
    await close();
  }

  Future<void> _notifySessionStarted(
    RealtimeSessionStartRequest payload,
    String provider,
    RealtimeSessionConfig config,
  ) async {
    FutureOr<void> Function(ArcaneVoiceProxySessionStartedEvent event)?
    callback = lifecycleCallbacks.onSessionStarted;
    if (callback == null) {
      return;
    }

    await callback(
      ArcaneVoiceProxySessionStartedEvent(
        sessionId: sessionId,
        startedAt: sessionStartedAt ?? DateTime.now(),
        connectionInfo: connectionInfo,
        request: payload,
        provider: provider,
        config: config,
        context: activeContext,
      ),
    );
  }

  Future<void> _handleProviderUsage(ArcaneVoiceProxyUsage usage) async {
    accumulatedUsage = accumulatedUsage == null
        ? usage
        : accumulatedUsage!.merge(usage);
    FutureOr<void> Function(ArcaneVoiceProxyUsageEvent event)? callback =
        lifecycleCallbacks.onUsage;
    if (callback == null) {
      return;
    }

    await callback(
      ArcaneVoiceProxyUsageEvent(
        sessionId: sessionId,
        observedAt: DateTime.now(),
        connectionInfo: connectionInfo,
        provider: usage.provider,
        usage: usage,
        context: activeContext,
      ),
    );
  }

  Future<void> _handleToolExecuted(
    ToolExecutionResult result,
    String rawArguments,
    DateTime startedAt,
    DateTime completedAt,
  ) async {
    if (result.executionTarget ==
        RealtimeToolExecutionTarget.arcaneVoiceProxy) {
      proxyToolCalls++;
    } else if (result.executionTarget ==
        RealtimeToolExecutionTarget.arcaneVoiceClient) {
      clientToolCalls++;
    }

    FutureOr<void> Function(ArcaneVoiceProxyToolExecutionEvent event)?
    callback = lifecycleCallbacks.onToolExecuted;
    if (callback == null) {
      return;
    }

    await callback(
      ArcaneVoiceProxyToolExecutionEvent(
        sessionId: sessionId,
        startedAt: startedAt,
        completedAt: completedAt,
        connectionInfo: connectionInfo,
        provider: activeProvider ?? RealtimeProviderCatalog.openAiId,
        name: result.name,
        executionTarget: result.executionTarget,
        rawArguments: rawArguments,
        result: result,
        context: activeContext,
      ),
    );
  }

  Future<void> _emitSessionStoppedToClient() async {
    if (sessionStopEventSent || isClosed) {
      return;
    }
    sessionStopEventSent = true;
    await sendMessage(const RealtimeSessionStoppedEvent());
  }

  Future<void> _notifySessionStopped() async {
    if (sessionStopNotified) {
      return;
    }
    sessionStopNotified = true;
    if (sessionStartedAt == null ||
        activeProvider == null ||
        activeConfig == null) {
      return;
    }

    ArcaneVoiceProxyUsage? usage = _finalizeUsage();
    FutureOr<void> Function(ArcaneVoiceProxySessionStoppedEvent event)?
    callback = lifecycleCallbacks.onSessionStopped;
    if (callback == null) {
      return;
    }

    await callback(
      ArcaneVoiceProxySessionStoppedEvent(
        sessionId: sessionId,
        startedAt: sessionStartedAt!,
        stoppedAt: DateTime.now(),
        connectionInfo: connectionInfo,
        provider: activeProvider!,
        model: activeConfig!.model,
        voice: activeConfig!.voice,
        reason: stopReason,
        usage: usage,
        proxyToolCalls: proxyToolCalls,
        clientToolCalls: clientToolCalls,
        error: stopError,
        context: activeContext,
      ),
    );
  }

  ArcaneVoiceProxyUsage? _finalizeUsage() {
    if (activeProvider == null ||
        activeConfig == null ||
        sessionStartedAt == null) {
      return accumulatedUsage;
    }

    ArcaneVoiceProxyUsage durationUsage = ArcaneVoiceProxyUsage(
      provider: activeProvider!,
      inputAudioBytes: clientAudioBytes,
      outputAudioBytes: assistantAudioBytes,
      sessionDuration: DateTime.now().difference(sessionStartedAt!),
      raw: <String, Object?>{
        'sessionId': sessionId,
        'provider': activeProvider!,
      },
    );
    if (accumulatedUsage == null) {
      return durationUsage;
    }
    return accumulatedUsage!.merge(durationUsage);
  }

  Future<void> sendMessage(RealtimeServerMessage payload) async {
    if (isClosed) return;
    channel.sink.add(RealtimeProtocolCodec.encodeServerJson(payload));
  }

  Future<void> sendAudio(Uint8List audioBytes) async {
    if (isClosed) return;
    assistantAudioBytes += audioBytes.length;
    channel.sink.add(audioBytes);
  }

  Future<void> sendError(String message) =>
      sendMessage(RealtimeErrorEvent(message: message));

  Future<void> close() async {
    if (isClosed) {
      return;
    }
    isClosed = true;
    info("[gateway] closing client session session=$sessionId");
    for (Completer<String> completer in pendingClientToolCalls.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Client session closed.'));
      }
    }
    pendingClientToolCalls = <String, Completer<String>>{};
    await providerSession?.close();
    providerSession = null;
    await _notifySessionStopped();
    await channel.sink.close();
  }

  void _logClientAudioChunk(int size) {
    clientAudioChunkCount++;
    clientAudioBytes += size;
    if (clientAudioChunkCount == 1 || clientAudioChunkCount % 50 == 0) {
      info(
        "[gateway] forwarded client audio chunk #$clientAudioChunkCount ($size bytes)",
      );
    }
  }

  Future<String> _invokeClientTool({
    required String requestId,
    required String name,
    required String rawArguments,
  }) async {
    if (isClosed) {
      throw StateError('Client session is closed.');
    }

    Completer<String> completer = Completer<String>();
    pendingClientToolCalls[requestId] = completer;
    await sendMessage(
      RealtimeToolCallEvent(
        requestId: requestId,
        name: name,
        argumentsJson: rawArguments,
      ),
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      pendingClientToolCalls.remove(requestId);
    }
  }

  void _completeClientTool(RealtimeToolResultRequest payload) {
    Completer<String>? completer = pendingClientToolCalls[payload.requestId];
    if (completer == null || completer.isCompleted) return;

    String? error = payload.error;
    if (error != null && error.isNotEmpty) {
      completer.completeError(StateError(error));
      return;
    }

    completer.complete(payload.outputJson);
  }
}
