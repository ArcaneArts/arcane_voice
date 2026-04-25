import 'dart:io';
import 'dart:math';

import 'package:arcane_voice_proxy/arcane_voice_proxy.dart';

void main(List<String> args) async {
  ArcaneVoiceProxyEnvironment environment =
      ArcaneVoiceProxyEnvironment.fromPlatform();
  ArcaneVoiceProxyToolRegistry proxyTools = ArcaneVoiceProxyToolRegistry(
    tools: <ArcaneVoiceProxyTool>[
      ArcaneVoiceProxyCallbackTool.jsonSchema(
        name: "randomNumber",
        description:
            "Generate a random integer between 5 and 99 for smoke testing tool calling.",
        parameters: <String, Object?>{
          "type": "object",
          "properties": <String, Object?>{},
          "required": <String>[],
        },
        onExecute: (_) async => execRandomNumberTool(),
      ),
    ],
  );
  ArcaneVoiceProxyServer proxyServer = ArcaneVoiceProxyServer(
    environment: environment,
    proxyTools: proxyTools,
    vadMode: ArcaneVoiceProxyVadMode.auto,
    lifecycleCallbacks: ArcaneVoiceProxyLifecycleCallbacks(
      onSessionStarted: (event) async {
        stdout.writeln(
          'session ${event.sessionId} started provider=${event.provider}',
        );
      },
      onSessionStopped: (event) async {
        stdout.writeln(
          'session ${event.sessionId} stopped reason=${event.reason} duration=${event.duration.inSeconds}s',
        );
      },
    ),
  );
  int port = int.parse(Platform.environment["PORT"] ?? "8080");
  HttpServer server = await proxyServer.serve(
    address: InternetAddress.anyIPv4,
    port: port,
  );
  stdout.writeln('Server listening on port ${server.port}');
}

Future<int> execRandomNumberTool() async => Random().nextInt(95) + 5;
