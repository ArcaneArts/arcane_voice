import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/elevenlabs_agent_session.dart';
import 'package:arcane_voice_proxy/src/gemini_live_session.dart';
import 'package:arcane_voice_proxy/src/grok_voice_session.dart';
import 'package:arcane_voice_proxy/src/openai_realtime_session.dart';
import 'package:arcane_voice_proxy/src/realtime_gateway.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';
import 'package:arcane_voice_proxy/src/server_log.dart';

int _twilioSessionCounter = 0;

String _nextTwilioSessionId() =>
    'twilio-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_twilioSessionCounter++).toRadixString(36)}';

class ArcaneVoiceTwilioConfig {
  final String voiceWebhookPath;
  final String streamWebSocketPath;
  final String? streamUrl;
  final String provider;
  final String model;
  final String voice;
  final String instructions;
  final String initialGreeting;
  final String providerOptionsJson;
  final RealtimeTurnDetectionConfig turnDetection;

  const ArcaneVoiceTwilioConfig({
    this.voiceWebhookPath = '/twilio/voice',
    this.streamWebSocketPath = '/ws/twilio',
    this.streamUrl,
    this.provider = RealtimeProviderCatalog.openAiId,
    this.model = 'gpt-realtime-1.5',
    this.voice = 'sage',
    this.instructions = '',
    this.initialGreeting = '',
    this.providerOptionsJson = '{}',
    this.turnDetection = const RealtimeTurnDetectionConfig(),
  });

  factory ArcaneVoiceTwilioConfig.fromPlatform({
    Map<String, String>? platformEnvironment,
  }) {
    Map<String, String> environment =
        platformEnvironment ?? Platform.environment;
    String provider = _firstNonEmpty(
      environment['TWILIO_PROVIDER'],
      fallback: RealtimeProviderCatalog.openAiId,
    );
    return ArcaneVoiceTwilioConfig(
      voiceWebhookPath: _pathFromEnvironment(
        environment['TWILIO_VOICE_WEBHOOK_PATH'],
        fallback: '/twilio/voice',
      ),
      streamWebSocketPath: _pathFromEnvironment(
        environment['TWILIO_STREAM_WEBSOCKET_PATH'],
        fallback: '/ws/twilio',
      ),
      streamUrl: _nullableNonEmpty(environment['TWILIO_STREAM_URL']),
      provider: provider,
      model: _firstNonEmpty(
        environment['TWILIO_MODEL'],
        fallback: RealtimeProviderCatalog.defaultModelFor(provider),
      ),
      voice: _firstNonEmpty(
        environment['TWILIO_VOICE'],
        fallback: RealtimeProviderCatalog.defaultVoiceFor(provider),
      ),
      instructions: environment['TWILIO_INSTRUCTIONS'] ?? '',
      initialGreeting: environment['TWILIO_INITIAL_GREETING'] ?? '',
      providerOptionsJson: _firstNonEmpty(
        environment['TWILIO_PROVIDER_OPTIONS_JSON'],
        fallback: '{}',
      ),
    );
  }

  RealtimeSessionStartRequest buildStartRequest({
    required ArcaneVoiceTwilioStreamMetadata metadata,
  }) => RealtimeSessionStartRequest(
    provider: provider,
    model: model,
    voice: voice,
    instructions: instructions,
    initialGreeting: initialGreeting,
    sessionContextJson: jsonEncode(metadata.toSessionContext()),
    providerOptionsJson: providerOptionsJson,
    inputSampleRate: RealtimeSessionConfig.defaultInputSampleRate,
    outputSampleRate: RealtimeSessionConfig.defaultOutputSampleRate,
    turnDetection: turnDetection,
    clientTools: const <RealtimeToolDefinition>[],
  );

  static String _firstNonEmpty(String? value, {required String fallback}) {
    String? normalizedValue = _nullableNonEmpty(value);
    return normalizedValue ?? fallback;
  }

  static String? _nullableNonEmpty(String? value) {
    if (value == null) {
      return null;
    }
    String normalizedValue = value.trim();
    return normalizedValue.isEmpty ? null : normalizedValue;
  }

  static String _pathFromEnvironment(
    String? value, {
    required String fallback,
  }) {
    String? normalizedValue = _nullableNonEmpty(value);
    if (normalizedValue == null) {
      return fallback;
    }
    return normalizedValue.startsWith('/')
        ? normalizedValue
        : '/$normalizedValue';
  }
}

class ArcaneVoiceTwilioGateway {
  final ArcaneVoiceProxyEnvironment environment;
  final ArcaneVoiceProxyToolRegistry proxyTools;
  final ArcaneVoiceProxySessionResolver? sessionResolver;
  final ArcaneVoiceProxyLifecycleCallbacks lifecycleCallbacks;
  final ArcaneVoiceProxyVadMode vadMode;
  final ArcaneVoiceTwilioConfig config;

  const ArcaneVoiceTwilioGateway({
    required this.environment,
    required this.proxyTools,
    this.sessionResolver,
    this.lifecycleCallbacks = const ArcaneVoiceProxyLifecycleCallbacks(),
    this.vadMode = ArcaneVoiceProxyVadMode.auto,
    this.config = const ArcaneVoiceTwilioConfig(),
  });

  Future<void> handleVoiceWebhook(HttpRequest request) async {
    Map<String, String> parameters = await readTwilioRequestParameters(request);
    String streamUrl = config.streamUrl ?? _deriveStreamUrl(request);
    String twiml = TwilioTwiMl.connectStream(
      streamUrl: streamUrl,
      parameters: _streamParameters(parameters),
    );

    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType(
      'text',
      'xml',
      charset: 'utf-8',
    );
    request.response.write(twiml);
    await request.response.close();
  }

  Future<void> handleMediaSocket(
    WebSocket socket, {
    ArcaneVoiceProxyConnectionInfo connectionInfo =
        const ArcaneVoiceProxyConnectionInfo(),
  }) => ArcaneVoiceTwilioMediaStreamSession(
    socket: socket,
    environment: environment,
    proxyTools: proxyTools,
    sessionResolver: sessionResolver,
    lifecycleCallbacks: lifecycleCallbacks,
    vadMode: vadMode,
    config: config,
    connectionInfo: connectionInfo,
  ).run();

  String _deriveStreamUrl(HttpRequest request) {
    String forwardedHost =
        request.headers.value('x-forwarded-host') ??
        request.headers.value(HttpHeaders.hostHeader) ??
        request.requestedUri.authority;
    String forwardedProto =
        request.headers.value('x-forwarded-proto')?.split(',').first.trim() ??
        request.requestedUri.scheme;
    String scheme = forwardedProto == 'https' ? 'wss' : 'ws';
    return Uri.parse(
      '$scheme://$forwardedHost',
    ).replace(path: config.streamWebSocketPath).toString();
  }

  Map<String, String> _streamParameters(Map<String, String> parameters) {
    const List<String> names = <String>[
      'CallSid',
      'AccountSid',
      'From',
      'To',
      'Caller',
      'Called',
      'CallStatus',
      'Direction',
    ];

    Map<String, String> output = <String, String>{};
    for (String name in names) {
      String? value = parameters[name]?.trim();
      if (value != null && value.isNotEmpty) {
        output[name] = value;
      }
    }
    return output;
  }
}

class ArcaneVoiceTwilioMediaStreamSession {
  final WebSocket socket;
  final ArcaneVoiceProxyEnvironment environment;
  final ArcaneVoiceProxyToolRegistry proxyTools;
  final ArcaneVoiceProxySessionResolver? sessionResolver;
  final ArcaneVoiceProxyLifecycleCallbacks lifecycleCallbacks;
  final ArcaneVoiceProxyVadMode vadMode;
  final ArcaneVoiceTwilioConfig config;
  final ArcaneVoiceProxyConnectionInfo connectionInfo;

  final String sessionId = _nextTwilioSessionId();
  final DateTime connectedAt = DateTime.now();

  RealtimeProviderSession? providerSession;
  RealtimeSessionStartRequest? startRequest;
  RealtimeSessionConfig? activeConfig;
  String? activeProvider;
  Object? activeContext;
  ArcaneVoiceProxyUsage? accumulatedUsage;
  DateTime? sessionStartedAt;
  String? streamSid;
  bool isClosed = false;
  int inboundAudioChunkCount = 0;
  int inboundAudioBytes = 0;
  int outboundAudioBytes = 0;
  int proxyToolCalls = 0;
  bool twilioOutputBufferActive = false;
  String stopReason = 'twilio.disconnected';
  String? stopError;
  bool sessionStopNotified = false;

  ArcaneVoiceTwilioMediaStreamSession({
    required this.socket,
    required this.environment,
    required this.proxyTools,
    this.sessionResolver,
    this.lifecycleCallbacks = const ArcaneVoiceProxyLifecycleCallbacks(),
    this.vadMode = ArcaneVoiceProxyVadMode.auto,
    required this.config,
    required this.connectionInfo,
  });

  Future<void> run() async {
    socket.pingInterval = const Duration(seconds: 20);
    info("[twilio] media stream connected session=$sessionId");

    try {
      await for (dynamic message in socket) {
        await _handleSocketMessage(message);
      }
    } catch (error) {
      if (!isClosed) {
        stopReason = 'twilio.socket.error';
        stopError = error.toString();
      }
    }

    await close();
  }

  Future<void> _handleSocketMessage(dynamic message) async {
    if (message is! String) {
      return;
    }

    Map<String, Object?> payload;
    try {
      Object? decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      payload = decoded.cast<String, Object?>();
    } catch (error) {
      warning("[twilio] invalid websocket json: $error");
      return;
    }

    String event = payload['event']?.toString() ?? '';
    switch (event) {
      case 'connected':
        info("[twilio] connected protocol=${payload['protocol']}");
      case 'start':
        await _handleStart(payload);
      case 'media':
        await _handleMedia(payload);
      case 'dtmf':
        verbose("[twilio] dtmf ${jsonEncode(payload['dtmf'])}");
      case 'mark':
        _handleMark(payload);
        verbose("[twilio] mark ${jsonEncode(payload['mark'])}");
      case 'stop':
        stopReason = 'twilio.stop';
        await close();
      default:
        verbose("[twilio] ignored event=$event");
    }
  }

  Future<void> _handleStart(Map<String, Object?> payload) async {
    if (providerSession != null) {
      return;
    }

    ArcaneVoiceTwilioStreamMetadata metadata =
        ArcaneVoiceTwilioStreamMetadata.fromStartMessage(payload);
    streamSid = metadata.streamSid;
    startRequest = config.buildStartRequest(metadata: metadata);

    ArcaneVoiceProxyResolvedSession resolvedSession;
    try {
      resolvedSession = await _resolveSession(startRequest!);
    } catch (error) {
      stopReason = 'session.resolve.error';
      stopError = error.toString();
      await _closeWithError(stopError!);
      return;
    }

    String provider = resolvedSession.provider.trim();
    if (RealtimeProviderCatalog.maybeById(provider) == null) {
      await _closeWithError('Unsupported provider: $provider');
      return;
    }

    String? apiKey = environment.apiKeyForProvider(provider);
    if (apiKey == null || apiKey.isEmpty) {
      await _closeWithError(_missingApiKeyMessage(provider));
      return;
    }

    RealtimeSessionConfig sessionConfig = resolvedSession.config;
    ArcaneVoiceProxyVadMode effectiveVadMode =
        resolvedSession.vadMode ?? vadMode;
    ProxyToolRegistry toolRegistry =
        ProxyToolRegistry(
          proxyTools: resolvedSession.proxyTools,
        ).bindClientTools(
          clientTools: const <RealtimeToolDefinition>[],
          clientToolInvoker: _invokeUnavailableClientTool,
        );

    activeProvider = provider;
    activeConfig = sessionConfig;
    activeContext = resolvedSession.context;
    info(
      "[twilio] starting session=$sessionId call=${metadata.callSid ?? '-'} provider=$provider model=${sessionConfig.model} voice=${sessionConfig.voice}",
    );

    providerSession = _buildProviderSession(
      provider: provider,
      apiKey: apiKey,
      config: sessionConfig,
      vadMode: effectiveVadMode,
      toolRegistry: toolRegistry,
    );

    try {
      await providerSession?.start();
      sessionStartedAt ??= DateTime.now();
      await _notifySessionStarted();
    } catch (error) {
      stopReason = 'session.start.error';
      stopError = error.toString();
      await _closeWithError(stopError!);
    }
  }

  Future<void> _handleMedia(Map<String, Object?> payload) async {
    RealtimeProviderSession? session = providerSession;
    RealtimeSessionConfig? sessionConfig = activeConfig;
    if (session == null || sessionConfig == null) {
      return;
    }

    Map<String, Object?>? media = _castObjectMap(payload['media']);
    String encodedPayload = media?['payload']?.toString() ?? '';
    if (encodedPayload.isEmpty) {
      return;
    }

    Uint8List mulawBytes;
    try {
      mulawBytes = base64Decode(encodedPayload);
    } catch (error) {
      warning("[twilio] invalid media payload: $error");
      return;
    }

    inboundAudioChunkCount++;
    inboundAudioBytes += mulawBytes.length;
    if (inboundAudioChunkCount == 1 || inboundAudioChunkCount % 100 == 0) {
      info(
        "[twilio] inbound audio chunk #$inboundAudioChunkCount (${mulawBytes.length} bytes)",
      );
    }

    Uint8List pcm16Bytes = TwilioAudioCodec.mulaw8kToPcm16(
      mulawBytes,
      outputSampleRate: sessionConfig.inputSampleRate,
    );
    await session.sendAudio(pcm16Bytes);
  }

  Future<ArcaneVoiceProxyResolvedSession> _resolveSession(
    RealtimeSessionStartRequest request,
  ) async {
    ArcaneVoiceProxySessionResolver? resolver = sessionResolver;
    if (resolver == null) {
      return ArcaneVoiceProxyResolvedSession.passthrough(
        request: request,
        proxyTools: proxyTools,
        context: RealtimeSessionConfig.fromRequest(request).sessionContext,
        vadMode: vadMode,
      );
    }

    return await resolver(
      ArcaneVoiceProxySessionRequest(
        sessionId: sessionId,
        connectionInfo: connectionInfo,
        request: request,
        receivedAt: DateTime.now(),
      ),
    );
  }

  RealtimeProviderSession _buildProviderSession({
    required String provider,
    required String apiKey,
    required RealtimeSessionConfig config,
    required ArcaneVoiceProxyVadMode vadMode,
    required ProxyToolRegistry toolRegistry,
  }) => switch (provider) {
    RealtimeProviderCatalog.geminiId => GeminiLiveSession(
      apiKey: apiKey,
      config: config,
      vadMode: vadMode,
      toolRegistry: toolRegistry,
      onJsonEvent: _handleProviderEvent,
      onAudioChunk: _sendProviderAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
    RealtimeProviderCatalog.grokId => GrokVoiceSession(
      apiKey: apiKey,
      config: config,
      vadMode: vadMode,
      toolRegistry: toolRegistry,
      onJsonEvent: _handleProviderEvent,
      onAudioChunk: _sendProviderAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
    RealtimeProviderCatalog.elevenLabsId => ElevenLabsAgentSession(
      apiKey: apiKey,
      config: config,
      vadMode: vadMode,
      toolRegistry: toolRegistry,
      onJsonEvent: _handleProviderEvent,
      onAudioChunk: _sendProviderAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
    _ => OpenAiRealtimeSession(
      apiKey: apiKey,
      config: config,
      vadMode: vadMode,
      toolRegistry: toolRegistry,
      onJsonEvent: _handleProviderEvent,
      onAudioChunk: _sendProviderAudio,
      onClosed: _handleProviderClosed,
      onUsage: _handleProviderUsage,
      onToolExecuted: _handleToolExecuted,
    ),
  };

  Future<void> _handleProviderEvent(RealtimeServerMessage payload) async {
    if (payload is RealtimeErrorEvent) {
      stopError = payload.message;
      warning("[twilio] provider error: ${payload.message}");
      return;
    }

    if (payload is RealtimeSessionStateEvent) {
      verbose("[twilio] provider state ${payload.state}");
      return;
    }

    if (payload is RealtimeInputSpeechStartedEvent) {
      if (activeConfig?.turnDetection.bargeInEnabled ?? false) {
        await _sendClear();
      }
      return;
    }

    if (payload is RealtimeAssistantOutputCompletedEvent) {
      await _sendMark('assistant-output-completed');
      return;
    }

    if (payload is RealtimeTranscriptUserFinalEvent) {
      info("[twilio] user transcript: ${payload.text}");
      return;
    }

    if (payload is RealtimeTranscriptAssistantFinalEvent) {
      info("[twilio] assistant transcript: ${payload.text}");
    }
  }

  Future<void> _sendProviderAudio(Uint8List audioBytes) async {
    String? sid = streamSid;
    RealtimeSessionConfig? sessionConfig = activeConfig;
    if (sid == null || sessionConfig == null || isClosed) {
      return;
    }

    Uint8List mulawBytes = TwilioAudioCodec.pcm16ToMulaw8k(
      audioBytes,
      inputSampleRate: sessionConfig.outputSampleRate,
    );
    if (mulawBytes.isEmpty) {
      return;
    }

    outboundAudioBytes += mulawBytes.length;
    twilioOutputBufferActive = true;
    socket.add(
      jsonEncode(<String, Object?>{
        'event': 'media',
        'streamSid': sid,
        'media': <String, Object?>{'payload': base64Encode(mulawBytes)},
      }),
    );
  }

  void _handleMark(Map<String, Object?> payload) {
    Map<String, Object?>? mark = _castObjectMap(payload['mark']);
    if (mark?['name']?.toString() == 'assistant-output-completed') {
      twilioOutputBufferActive = false;
    }
  }

  Future<void> _sendMark(String name) async {
    String? sid = streamSid;
    if (sid == null || isClosed) {
      return;
    }
    socket.add(
      jsonEncode(<String, Object?>{
        'event': 'mark',
        'streamSid': sid,
        'mark': <String, Object?>{'name': name},
      }),
    );
  }

  Future<void> _sendClear() async {
    String? sid = streamSid;
    if (sid == null || isClosed || !twilioOutputBufferActive) {
      return;
    }
    info("[twilio] clearing buffered assistant audio for barge-in");
    twilioOutputBufferActive = false;
    socket.add(
      jsonEncode(<String, Object?>{'event': 'clear', 'streamSid': sid}),
    );
  }

  Future<void> _handleProviderClosed() async {
    if (isClosed) {
      return;
    }
    stopReason = stopError == null ? 'provider.closed' : stopReason;
    await close();
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

  Future<void> _notifySessionStarted() async {
    FutureOr<void> Function(ArcaneVoiceProxySessionStartedEvent event)?
    callback = lifecycleCallbacks.onSessionStarted;
    if (callback == null || startRequest == null || activeConfig == null) {
      return;
    }

    await callback(
      ArcaneVoiceProxySessionStartedEvent(
        sessionId: sessionId,
        startedAt: sessionStartedAt ?? DateTime.now(),
        connectionInfo: connectionInfo,
        request: startRequest!,
        provider: activeProvider ?? RealtimeProviderCatalog.openAiId,
        config: activeConfig!,
        context: activeContext,
      ),
    );
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
        usage: _finalizeUsage(),
        proxyToolCalls: proxyToolCalls,
        error: stopError,
        context: activeContext,
      ),
    );
  }

  ArcaneVoiceProxyUsage? _finalizeUsage() {
    if (activeProvider == null || sessionStartedAt == null) {
      return accumulatedUsage;
    }

    ArcaneVoiceProxyUsage durationUsage = ArcaneVoiceProxyUsage(
      provider: activeProvider!,
      inputAudioBytes: inboundAudioBytes,
      outputAudioBytes: outboundAudioBytes,
      sessionDuration: DateTime.now().difference(sessionStartedAt!),
      raw: <String, Object?>{
        'sessionId': sessionId,
        'source': 'twilio',
        if (streamSid != null) 'streamSid': streamSid,
      },
    );
    if (accumulatedUsage == null) {
      return durationUsage;
    }
    return accumulatedUsage!.merge(durationUsage);
  }

  Future<String> _invokeUnavailableClientTool({
    required String requestId,
    required String name,
    required String rawArguments,
  }) {
    throw StateError('Twilio sessions do not support client tools.');
  }

  String _missingApiKeyMessage(String provider) => switch (provider) {
    RealtimeProviderCatalog.geminiId =>
      'GEMINI_API_KEY is missing on the server. Set it before starting a Gemini Twilio call.',
    RealtimeProviderCatalog.grokId =>
      'XAI_API_KEY is missing on the server. Set it before starting a Grok Twilio call.',
    RealtimeProviderCatalog.elevenLabsId =>
      'ELEVENLABS_API_KEY is missing on the server. Set it before starting an ElevenLabs Twilio call.',
    _ =>
      'OPENAI_API_KEY is missing on the server. Set it before starting an OpenAI Twilio call.',
  };

  Future<void> _closeWithError(String message) async {
    stopError = message;
    warning("[twilio] closing session=$sessionId error=$message");
    await close(closeCode: WebSocketStatus.internalServerError);
  }

  Future<void> close({int? closeCode}) async {
    if (isClosed) {
      return;
    }
    isClosed = true;
    info("[twilio] closing media stream session=$sessionId");
    await providerSession?.close();
    providerSession = null;
    await _notifySessionStopped();
    await socket.close(closeCode);
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
}

class ArcaneVoiceTwilioStreamMetadata {
  final String? accountSid;
  final String? callSid;
  final String? streamSid;
  final String? from;
  final String? to;
  final String? caller;
  final String? called;
  final String? callStatus;
  final String? direction;
  final Map<String, String> customParameters;

  const ArcaneVoiceTwilioStreamMetadata({
    this.accountSid,
    this.callSid,
    this.streamSid,
    this.from,
    this.to,
    this.caller,
    this.called,
    this.callStatus,
    this.direction,
    this.customParameters = const <String, String>{},
  });

  factory ArcaneVoiceTwilioStreamMetadata.fromStartMessage(
    Map<String, Object?> payload,
  ) {
    Map<String, Object?> start =
        _castObjectMap(payload['start']) ?? <String, Object?>{};
    Map<String, String> customParameters = _stringMap(
      start['customParameters'],
    );
    return ArcaneVoiceTwilioStreamMetadata(
      accountSid: _readOptionalString(start['accountSid']),
      callSid: _readOptionalString(start['callSid']),
      streamSid: _readOptionalString(
        start['streamSid'] ?? payload['streamSid'],
      ),
      from: _firstString(customParameters, const <String>['From', 'Caller']),
      to: _firstString(customParameters, const <String>['To', 'Called']),
      caller: _firstString(customParameters, const <String>['Caller', 'From']),
      called: _firstString(customParameters, const <String>['Called', 'To']),
      callStatus: _firstString(customParameters, const <String>['CallStatus']),
      direction: _firstString(customParameters, const <String>['Direction']),
      customParameters: customParameters,
    );
  }

  ArcaneVoiceTwilioCallContext toCallContext() => ArcaneVoiceTwilioCallContext(
    accountSid: accountSid,
    callSid: callSid,
    streamSid: streamSid,
    from: from,
    to: to,
    caller: caller,
    called: called,
    callStatus: callStatus,
    direction: direction,
    customParameters: customParameters,
  );

  Map<String, Object?> toSessionContext() => toCallContext().toSessionContext();

  static Map<String, Object?>? _castObjectMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.cast<String, Object?>();
    }
    if (value is Map<String, Object?>) {
      return value;
    }
    return null;
  }

  static Map<String, String> _stringMap(Object? value) {
    Map<String, Object?>? source = _castObjectMap(value);
    if (source == null) {
      return <String, String>{};
    }
    return source.map(
      (String key, Object? value) =>
          MapEntry<String, String>(key, value?.toString() ?? ''),
    );
  }

  static String? _firstString(Map<String, String> source, List<String> keys) {
    for (String key in keys) {
      String? value = _readOptionalString(source[key]);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  static String? _readOptionalString(Object? value) {
    String? text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}

class ArcaneVoiceTwilioCallContext {
  static const String sessionContextSource = 'twilio';

  final String? accountSid;
  final String? callSid;
  final String? streamSid;
  final String? from;
  final String? to;
  final String? caller;
  final String? called;
  final String? callStatus;
  final String? direction;
  final Map<String, String> customParameters;

  const ArcaneVoiceTwilioCallContext({
    this.accountSid,
    this.callSid,
    this.streamSid,
    this.from,
    this.to,
    this.caller,
    this.called,
    this.callStatus,
    this.direction,
    this.customParameters = const <String, String>{},
  });

  String? get callerNumber => from ?? caller;

  String? get dialedNumber => to ?? called;

  bool get hasCallerNumber => callerNumber != null;

  Map<String, Object?> toSessionContext() => <String, Object?>{
    'source': sessionContextSource,
    'twilio': toJson(),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    if (accountSid != null) 'accountSid': accountSid,
    if (callSid != null) 'callSid': callSid,
    if (streamSid != null) 'streamSid': streamSid,
    if (from != null) 'from': from,
    if (to != null) 'to': to,
    if (caller != null) 'caller': caller,
    if (called != null) 'called': called,
    if (callStatus != null) 'callStatus': callStatus,
    if (direction != null) 'direction': direction,
    if (customParameters.isNotEmpty) 'customParameters': customParameters,
  };

  static ArcaneVoiceTwilioCallContext? maybeFromSessionRequest(
    ArcaneVoiceProxySessionRequest request,
  ) => maybeFromSessionContextJson(request.request.sessionContextJson);

  static ArcaneVoiceTwilioCallContext? maybeFromSessionConfig(
    RealtimeSessionConfig config,
  ) => maybeFromSessionContextJson(config.sessionContextJson);

  static ArcaneVoiceTwilioCallContext? maybeFromSessionContextJson(
    String source,
  ) {
    try {
      Object? decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) {
        return maybeFromSessionContext(decoded.cast<String, Object?>());
      }
      if (decoded is Map<String, Object?>) {
        return maybeFromSessionContext(decoded);
      }
    } catch (_) {}
    return null;
  }

  static ArcaneVoiceTwilioCallContext? maybeFromSessionContext(
    Map<String, Object?> context,
  ) {
    if (context['source']?.toString() != sessionContextSource) {
      return null;
    }
    Map<String, Object?>? twilio = _castObjectMap(context['twilio']);
    if (twilio == null) {
      return null;
    }
    return fromJson(twilio);
  }

  static ArcaneVoiceTwilioCallContext fromJson(Map<String, Object?> json) {
    Map<String, String> customParameters = _stringMap(json['customParameters']);
    return ArcaneVoiceTwilioCallContext(
      accountSid: _readOptionalString(json['accountSid']),
      callSid: _readOptionalString(json['callSid']),
      streamSid: _readOptionalString(json['streamSid']),
      from: _readOptionalString(json['from']),
      to: _readOptionalString(json['to']),
      caller: _readOptionalString(json['caller']),
      called: _readOptionalString(json['called']),
      callStatus: _readOptionalString(json['callStatus']),
      direction: _readOptionalString(json['direction']),
      customParameters: customParameters,
    );
  }

  static Map<String, Object?>? _castObjectMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value.cast<String, Object?>();
    }
    if (value is Map<String, Object?>) {
      return value;
    }
    return null;
  }

  static Map<String, String> _stringMap(Object? value) {
    Map<String, Object?>? source = _castObjectMap(value);
    if (source == null) {
      return <String, String>{};
    }
    return source.map(
      (String key, Object? value) =>
          MapEntry<String, String>(key, value?.toString() ?? ''),
    );
  }

  static String? _readOptionalString(Object? value) {
    String? text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }
}

class TwilioTwiMl {
  const TwilioTwiMl._();

  static String connectStream({
    required String streamUrl,
    Map<String, String> parameters = const <String, String>{},
  }) {
    StringBuffer buffer = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8"?>')
      ..write('<Response><Connect><Stream url="')
      ..write(_escapeAttribute(streamUrl))
      ..write('">');

    parameters.forEach((String name, String value) {
      buffer
        ..write('<Parameter name="')
        ..write(_escapeAttribute(name))
        ..write('" value="')
        ..write(_escapeAttribute(value))
        ..write('" />');
    });

    buffer.write('</Stream></Connect></Response>');
    return buffer.toString();
  }

  static String _escapeAttribute(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

class TwilioAudioCodec {
  static const int twilioSampleRate = 8000;

  const TwilioAudioCodec._();

  static Uint8List mulaw8kToPcm16(
    Uint8List mulawBytes, {
    required int outputSampleRate,
  }) {
    if (mulawBytes.isEmpty) {
      return Uint8List(0);
    }

    Int16List pcm8k = Int16List(mulawBytes.length);
    for (int i = 0; i < mulawBytes.length; i++) {
      pcm8k[i] = _mulawToLinearSample(mulawBytes[i]);
    }

    Int16List resampled = _resamplePcm16(
      pcm8k,
      sourceSampleRate: twilioSampleRate,
      targetSampleRate: outputSampleRate,
    );
    return _pcm16SamplesToBytes(resampled);
  }

  static Uint8List pcm16ToMulaw8k(
    Uint8List pcm16Bytes, {
    required int inputSampleRate,
  }) {
    if (pcm16Bytes.length < 2) {
      return Uint8List(0);
    }

    Int16List samples = _pcm16BytesToSamples(pcm16Bytes);
    Int16List resampled = _resamplePcm16(
      samples,
      sourceSampleRate: inputSampleRate,
      targetSampleRate: twilioSampleRate,
    );
    Uint8List output = Uint8List(resampled.length);
    for (int i = 0; i < resampled.length; i++) {
      output[i] = _linearSampleToMulaw(resampled[i]);
    }
    return output;
  }

  static Int16List _resamplePcm16(
    Int16List samples, {
    required int sourceSampleRate,
    required int targetSampleRate,
  }) {
    if (samples.isEmpty) {
      return Int16List(0);
    }
    if (sourceSampleRate <= 0 ||
        targetSampleRate <= 0 ||
        sourceSampleRate == targetSampleRate) {
      return Int16List.fromList(samples);
    }

    int outputLength = math.max(
      1,
      (samples.length * targetSampleRate / sourceSampleRate).round(),
    );
    Int16List output = Int16List(outputLength);
    for (int i = 0; i < outputLength; i++) {
      double sourceIndex = i * sourceSampleRate / targetSampleRate;
      int leftIndex = sourceIndex.floor().clamp(0, samples.length - 1);
      int rightIndex = (leftIndex + 1).clamp(0, samples.length - 1);
      double fraction = sourceIndex - leftIndex;
      double sample =
          samples[leftIndex] +
          (samples[rightIndex] - samples[leftIndex]) * fraction;
      output[i] = sample.round().clamp(-32768, 32767);
    }
    return output;
  }

  static Int16List _pcm16BytesToSamples(Uint8List bytes) {
    int sampleCount = bytes.length ~/ 2;
    ByteData byteData = ByteData.sublistView(bytes);
    Int16List samples = Int16List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      samples[i] = byteData.getInt16(i * 2, Endian.little);
    }
    return samples;
  }

  static Uint8List _pcm16SamplesToBytes(Int16List samples) {
    Uint8List bytes = Uint8List(samples.length * 2);
    ByteData byteData = ByteData.sublistView(bytes);
    for (int i = 0; i < samples.length; i++) {
      byteData.setInt16(i * 2, samples[i], Endian.little);
    }
    return bytes;
  }

  static int _mulawToLinearSample(int value) {
    int muLaw = (~value) & 0xff;
    int sign = muLaw & 0x80;
    int exponent = (muLaw >> 4) & 0x07;
    int mantissa = muLaw & 0x0f;
    int sample = ((mantissa << 3) + 0x84) << exponent;
    sample -= 0x84;
    return sign == 0 ? sample : -sample;
  }

  static int _linearSampleToMulaw(int sample) {
    const int bias = 0x84;
    const int clip = 32635;

    int sign = 0;
    int magnitude = sample;
    if (magnitude < 0) {
      magnitude = -magnitude;
      sign = 0x80;
    }
    magnitude = math.min(magnitude, clip) + bias;

    int exponent = 7;
    for (
      int mask = 0x4000;
      (magnitude & mask) == 0 && exponent > 0;
      mask >>= 1
    ) {
      exponent--;
    }
    int mantissa = (magnitude >> (exponent + 3)) & 0x0f;
    return (~(sign | (exponent << 4) | mantissa)) & 0xff;
  }
}

Future<Map<String, String>> readTwilioRequestParameters(
  HttpRequest request,
) async {
  Map<String, String> parameters = <String, String>{
    ...request.uri.queryParameters,
  };

  if (request.method != 'POST') {
    return parameters;
  }

  String body = await utf8.decoder.bind(request).join();
  if (body.trim().isEmpty) {
    return parameters;
  }

  ContentType? contentType = request.headers.contentType;
  if (contentType?.mimeType == 'application/x-www-form-urlencoded') {
    parameters.addAll(Uri.splitQueryString(body, encoding: utf8));
  }
  return parameters;
}
