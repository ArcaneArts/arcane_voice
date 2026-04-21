# arcane_voice_proxy

`arcane_voice_proxy` hosts the Arcane Voice realtime proxy server. It accepts a
typed websocket protocol from clients, forwards audio to provider-specific
realtime APIs, executes tools on the server, and streams audio back to the
client.

This package is the server-side counterpart to
[arcane_voice](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice).
It keeps provider APIs, server-side tool execution, and turn-detection logic
behind one stable client-facing websocket interface.

## Supported providers

- OpenAI realtime
- Gemini Live
- Grok voice

## Public API

- `ArcaneVoiceProxyServer` for hosting the proxy
- `ServerEnvironment` for provider key configuration
- `RealtimeGateway` for websocket handling
- `ServerToolRegistry` and `CallbackServerTool` for explicit proxy-owned tools

## Responsibilities

- accept the shared typed realtime protocol from clients
- keep provider auth and session details off the client
- execute tools on the server
- normalize provider-specific events into one client protocol
- apply the shared local turn-detection config across providers

## Required environment variables

- `OPENAI_API_KEY` for OpenAI
- `GEMINI_API_KEY` for Gemini
- `XAI_API_KEY` for Grok
- `PORT` for the HTTP bind port, default `8080`

## Endpoints

- `GET /` basic service metadata
- `GET /health` health check
- `GET /ws/realtime` websocket endpoint used by `arcane_voice`

## Bootstrap example

```dart
import 'dart:io';

import 'package:arcane_voice_proxy/arcane_voice_proxy.dart';

Future<void> main() async {
  ServerEnvironment environment = ServerEnvironment.fromPlatform();
  ArcaneVoiceProxyServer proxyServer = ArcaneVoiceProxyServer(
    environment: environment,
    serverTools: ServerToolRegistry.empty(),
  );
  int port = int.parse(Platform.environment["PORT"] ?? "8080");
  HttpServer server = await proxyServer.serve(
    address: InternetAddress.anyIPv4,
    port: port,
  );
  stdout.writeln("Server listening on port ${server.port}");
}
```

## Behavior notes

- structured control messages are decoded with `arcane_voice_models`
- streamed audio is passed as binary websocket frames
- provider-specific websocket details stay inside this package
- proxy hosts can register server tools and also receive client-declared tools per session

## Related packages

- [arcane_voice_models](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/arcane_voice_models)
  Shared protocol and provider metadata
- [example_proxy](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/example_proxy)
  Minimal runnable host for this package
