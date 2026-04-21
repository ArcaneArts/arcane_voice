import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:arcane_voice_models/arcane_voice_models.dart';
import 'package:arcane_voice_proxy/src/realtime_gateway.dart';
import 'package:arcane_voice_proxy/src/realtime_support.dart';

class ArcaneVoiceProxyServer {
  final ServerEnvironment environment;
  final ServerToolRegistry serverTools;
  final RealtimeGateway gateway;

  ArcaneVoiceProxyServer({
    required this.environment,
    ServerToolRegistry? serverTools,
  }) : serverTools = serverTools ?? ServerToolRegistry.empty(),
       gateway = RealtimeGateway(
         environment: environment,
         serverTools: serverTools ?? ServerToolRegistry.empty(),
       );

  factory ArcaneVoiceProxyServer.fromPlatform({
    ServerToolRegistry? serverTools,
  }) => ArcaneVoiceProxyServer(
    environment: ServerEnvironment.fromPlatform(),
    serverTools: serverTools,
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

    await request.response.sendJson(
      statusCode: HttpStatus.notFound,
      body: <String, Object?>{"error": "Not found"},
    );
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
    unawaited(gateway.handleSocket(socket));
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
