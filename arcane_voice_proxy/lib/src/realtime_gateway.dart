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

class ServerEnvironment {
  final String? openAiApiKey;
  final String? geminiApiKey;
  final String? xAiApiKey;
  final String? elevenLabsApiKey;

  const ServerEnvironment({
    required this.openAiApiKey,
    required this.geminiApiKey,
    required this.xAiApiKey,
    required this.elevenLabsApiKey,
  });

  factory ServerEnvironment.fromPlatform() => ServerEnvironment(
    openAiApiKey: Platform.environment["OPENAI_API_KEY"],
    geminiApiKey: Platform.environment["GEMINI_API_KEY"],
    xAiApiKey: Platform.environment["XAI_API_KEY"],
    elevenLabsApiKey: Platform.environment["ELEVENLABS_API_KEY"],
  );
}

class RealtimeGateway {
  final ServerEnvironment environment;
  final ServerToolRegistry serverTools;

  const RealtimeGateway({
    required this.environment,
    required this.serverTools,
  });

  Future<void> handleSocket(WebSocket socket) =>
      RealtimeGatewaySession(
        socket: socket,
        environment: environment,
        serverTools: serverTools,
      ).run();
}

class RealtimeGatewaySession {
  final WebSocket socket;
  final ServerEnvironment environment;
  final ServerToolRegistry serverTools;

  RealtimeProviderSession? providerSession;
  bool isClosed = false;
  int clientAudioChunkCount = 0;
  Map<String, Completer<String>> pendingClientToolCalls =
      <String, Completer<String>>{};

  RealtimeGatewaySession({
    required this.socket,
    required this.environment,
    required this.serverTools,
  });

  Future<void> run() async {
    info("[gateway] client connected");
    socket.pingInterval = const Duration(seconds: 20);
    await sendMessage(
      RealtimeConnectionReadyEvent(
        providers: RealtimeProviderCatalog.ids,
        defaultModel: RealtimeProviderCatalog.openAi.defaultModel,
        defaultVoice: RealtimeProviderCatalog.openAi.defaultVoice,
      ),
    );

    try {
      await for (dynamic message in socket) {
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
      await sendMessage(const RealtimeSessionStoppedEvent());
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
      await sendError("A realtime session is already active.");
      return;
    }

    String provider = payload.provider;
    if (RealtimeProviderCatalog.maybeById(provider) == null) {
      await sendError("Unsupported provider: $provider");
      return;
    }

    String? apiKey = _resolveApiKey(provider);
    if (apiKey == null || apiKey.isEmpty) {
      await sendError(_missingApiKeyMessage(provider));
      return;
    }

    RealtimeSessionConfig config = RealtimeSessionConfig.fromRequest(payload);
    ProxyToolRegistry toolRegistry = ProxyToolRegistry(
      serverTools: serverTools,
    ).bindClientTools(
      clientTools: payload.clientTools,
      clientToolInvoker: _invokeClientTool,
    );
    info(
      "[gateway] starting provider=$provider model=${config.model} voice=${config.voice}",
    );
    providerSession = _buildProviderSession(
      provider: provider,
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
    );

    await providerSession?.start();
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
    ),
    RealtimeProviderCatalog.grokId => GrokVoiceSession(
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: sendMessage,
      onAudioChunk: sendAudio,
      onClosed: _handleProviderClosed,
    ),
    RealtimeProviderCatalog.elevenLabsId => ElevenLabsAgentSession(
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: sendMessage,
      onAudioChunk: sendAudio,
      onClosed: _handleProviderClosed,
    ),
    _ => OpenAiRealtimeSession(
      apiKey: apiKey,
      config: config,
      toolRegistry: toolRegistry,
      onJsonEvent: sendMessage,
      onAudioChunk: sendAudio,
      onClosed: _handleProviderClosed,
    ),
  };

  String? _resolveApiKey(String provider) => switch (provider) {
    RealtimeProviderCatalog.geminiId => environment.geminiApiKey,
    RealtimeProviderCatalog.grokId => environment.xAiApiKey,
    RealtimeProviderCatalog.elevenLabsId => environment.elevenLabsApiKey,
    _ => environment.openAiApiKey,
  };

  String _missingApiKeyMessage(String provider) => switch (provider) {
    RealtimeProviderCatalog.geminiId =>
      "GEMINI_API_KEY is missing on the server. Set it before starting a Gemini call.",
    RealtimeProviderCatalog.grokId =>
      "XAI_API_KEY is missing on the server. Set it before starting a Grok call.",
    RealtimeProviderCatalog.elevenLabsId =>
      "ELEVENLABS_API_KEY is missing on the server. Set it before starting an ElevenLabs call.",
    _ =>
      "OPENAI_API_KEY is missing on the server. Set it before starting an OpenAI call.",
  };

  Future<void> _handleProviderClosed() async {
    info("[gateway] provider session closed");
    await sendMessage(const RealtimeSessionStoppedEvent());
  }

  Future<void> sendMessage(RealtimeServerMessage payload) async {
    if (isClosed) return;
    socket.add(RealtimeProtocolCodec.encodeServerJson(payload));
  }

  Future<void> sendAudio(Uint8List audioBytes) async {
    if (isClosed) return;
    socket.add(audioBytes);
  }

  Future<void> sendError(String message) =>
      sendMessage(RealtimeErrorEvent(message: message));

  Future<void> close() async {
    if (isClosed) return;
    isClosed = true;
    info("[gateway] closing client session");
    for (Completer<String> completer in pendingClientToolCalls.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError("Client session closed."));
      }
    }
    pendingClientToolCalls = <String, Completer<String>>{};
    await providerSession?.close();
    providerSession = null;
    await socket.close();
  }

  void _logClientAudioChunk(int size) {
    clientAudioChunkCount++;
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
      throw StateError("Client session is closed.");
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
