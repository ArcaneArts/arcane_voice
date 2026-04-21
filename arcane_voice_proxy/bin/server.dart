import 'dart:io';

import 'package:arcane_voice_proxy/arcane_voice_proxy.dart';

void main(List<String> args) async {
  ArcaneVoiceProxyEnvironment environment =
      ArcaneVoiceProxyEnvironment.fromPlatform();
  ArcaneVoiceProxyServer proxyServer = ArcaneVoiceProxyServer(
    environment: environment,
    proxyTools: ArcaneVoiceProxyToolRegistry.empty(),
  );
  int port = int.parse(Platform.environment["PORT"] ?? "8080");
  HttpServer server = await proxyServer.serve(
    address: InternetAddress.anyIPv4,
    port: port,
  );
  stdout.writeln('Server listening on port ${server.port}');
}
