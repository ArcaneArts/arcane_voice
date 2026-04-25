import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/realtime_gateway.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';
import 'package:arcane_voice_proxy/src/twilio_support.dart';

class ArcaneVoiceProxyServer {
  final ArcaneVoiceProxyEnvironment environment;
  final ArcaneVoiceProxyToolRegistry proxyTools;
  final ArcaneVoiceProxySessionResolver? sessionResolver;
  final ArcaneVoiceProxyLifecycleCallbacks lifecycleCallbacks;
  final ArcaneVoiceProxyVadMode vadMode;
  final ArcaneVoiceTwilioConfig twilioConfig;
  final RealtimeGateway gateway;
  final ArcaneVoiceTwilioGateway twilioGateway;

  ArcaneVoiceProxyServer({
    required this.environment,
    ArcaneVoiceProxyToolRegistry? proxyTools,
    this.sessionResolver,
    this.lifecycleCallbacks = const ArcaneVoiceProxyLifecycleCallbacks(),
    this.vadMode = ArcaneVoiceProxyVadMode.auto,
    this.twilioConfig = const ArcaneVoiceTwilioConfig(),
  }) : proxyTools = proxyTools ?? ArcaneVoiceProxyToolRegistry.empty(),
       gateway = RealtimeGateway(
         environment: environment,
         proxyTools: proxyTools ?? ArcaneVoiceProxyToolRegistry.empty(),
         sessionResolver: sessionResolver,
         lifecycleCallbacks: lifecycleCallbacks,
         vadMode: vadMode,
       ),
       twilioGateway = ArcaneVoiceTwilioGateway(
         environment: environment,
         proxyTools: proxyTools ?? ArcaneVoiceProxyToolRegistry.empty(),
         sessionResolver: sessionResolver,
         lifecycleCallbacks: lifecycleCallbacks,
         vadMode: vadMode,
         config: twilioConfig,
       );

  factory ArcaneVoiceProxyServer.fromPlatform({
    ArcaneVoiceProxyToolRegistry? proxyTools,
    ArcaneVoiceProxySessionResolver? sessionResolver,
    ArcaneVoiceProxyLifecycleCallbacks lifecycleCallbacks =
        const ArcaneVoiceProxyLifecycleCallbacks(),
    ArcaneVoiceProxyVadMode vadMode = ArcaneVoiceProxyVadMode.auto,
    ArcaneVoiceTwilioConfig? twilioConfig,
  }) => ArcaneVoiceProxyServer(
    environment: ArcaneVoiceProxyEnvironment.fromPlatform(),
    proxyTools: proxyTools,
    sessionResolver: sessionResolver,
    lifecycleCallbacks: lifecycleCallbacks,
    vadMode: vadMode,
    twilioConfig: twilioConfig ?? ArcaneVoiceTwilioConfig.fromPlatform(),
  );

  Future<HttpServer> serve({
    required InternetAddress address,
    required int port,
  }) async {
    HttpServer server = await HttpServer.bind(address, port);
    unawaited(_listen(server));
    return server;
  }

  Future<void> _listen(HttpServer server) async {
    await for (HttpRequest request in server) {
      unawaited(_handleRequestSafely(request));
    }
  }

  Future<void> _handleRequestSafely(HttpRequest request) async {
    try {
      await _handleRequest(request);
    } catch (error) {
      try {
        await request.response.sendJson(
          statusCode: HttpStatus.internalServerError,
          body: <String, Object?>{"error": error.toString()},
        );
      } catch (_) {}
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method == "GET" && request.uri.path == "/") {
      await request.response.sendJson(
        statusCode: HttpStatus.ok,
        body: <String, Object?>{
          "service": "arcana-realtime-proxy",
          "status": "ok",
          "providers": RealtimeProviderCatalog.ids,
          "websocket": "/ws/realtime",
          "twilioVoiceWebhook": twilioConfig.voiceWebhookPath,
          "twilioWebsocket": twilioConfig.streamWebSocketPath,
        },
      );
      return;
    }

    if (request.method == "GET" && request.uri.path == "/health") {
      await request.response.sendJson(
        statusCode: HttpStatus.ok,
        body: <String, Object?>{"status": "ok"},
      );
      return;
    }

    if (request.uri.path == "/ws/realtime") {
      await _handleRealtimeSocket(request);
      return;
    }

    if (_isTwilioVoiceWebhook(request)) {
      await twilioGateway.handleVoiceWebhook(request);
      return;
    }

    if (request.uri.path == twilioConfig.streamWebSocketPath) {
      await _handleTwilioSocket(request);
      return;
    }

    await request.response.sendJson(
      statusCode: HttpStatus.notFound,
      body: <String, Object?>{"error": "Not found"},
    );
  }

  bool _isTwilioVoiceWebhook(HttpRequest request) {
    if (request.uri.path != twilioConfig.voiceWebhookPath) {
      return false;
    }
    return request.method == "GET" || request.method == "POST";
  }

  Future<void> _handleRealtimeSocket(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      await request.response.sendJson(
        statusCode: HttpStatus.upgradeRequired,
        body: <String, Object?>{
          "error": "Expected a websocket upgrade request.",
        },
      );
      return;
    }

    WebSocket socket = await WebSocketTransformer.upgrade(request);
    unawaited(
      gateway.handleSocket(
        socket,
        connectionInfo: ArcaneVoiceProxyConnectionInfo(
          remoteAddress: request.connectionInfo?.remoteAddress.address,
          requestPath: request.uri.path,
          queryParameters: request.uri.queryParameters,
        ),
      ),
    );
  }

  Future<void> _handleTwilioSocket(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      await request.response.sendJson(
        statusCode: HttpStatus.upgradeRequired,
        body: <String, Object?>{
          "error": "Expected a websocket upgrade request.",
        },
      );
      return;
    }

    WebSocket socket = await WebSocketTransformer.upgrade(request);
    unawaited(
      twilioGateway.handleMediaSocket(
        socket,
        connectionInfo: ArcaneVoiceProxyConnectionInfo(
          remoteAddress: request.connectionInfo?.remoteAddress.address,
          requestPath: request.uri.path,
          queryParameters: request.uri.queryParameters,
        ),
      ),
    );
  }
}

extension ServerHttpResponse on HttpResponse {
  Future<void> sendJson({
    required int statusCode,
    required Map<String, Object?> body,
  }) async {
    this.statusCode = statusCode;
    headers.contentType = ContentType("application", "json", charset: "utf-8");
    write(jsonEncode(body));
    await close();
  }
}
