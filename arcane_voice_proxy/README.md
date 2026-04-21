# arcane_voice_proxy

`arcane_voice_proxy` hosts the Arcane Voice realtime proxy server. It accepts a
typed websocket protocol from clients, forwards audio to provider-specific
realtime APIs, executes proxy-side tools, and streams audio back to the client.

This package is the server-side counterpart to
[arcane_voice](https://pub.dev/packages/arcane_voice). It keeps provider auth,
session policy, usage reporting, and tool execution behind one stable
client-facing websocket interface.

## What's New In 1.1.0

- session resolution hooks for host-owned auth and per-session configuration
- lifecycle callbacks for session start, usage observation, tool execution, and
  session stop
- normalized usage reporting across provider runtimes
- cleaned public API that uses `proxyTools` and `ArcaneVoice...` names only

## Supported Providers

- OpenAI realtime
- Gemini Live
- Grok voice
- ElevenLabs voice agents

## Public API

- `ArcaneVoiceProxyServer` for hosting the proxy
- `ArcaneVoiceProxyEnvironment` for provider key configuration
- `RealtimeGateway` for websocket handling
- `ArcaneVoiceProxyToolRegistry` and `ArcaneVoiceProxyCallbackTool` for
  explicit proxy-owned tools
- `ArcaneVoiceProxySessionResolver` and
  `ArcaneVoiceProxyResolvedSession` for host-authenticated session bootstrap
- `ArcaneVoiceProxyLifecycleCallbacks` and `ArcaneVoiceProxyUsage` for
  auditing, metering, and billing hooks

## Responsibilities

- accept the shared typed realtime protocol from clients
- keep provider auth and session details off the client
- execute proxy-owned tools on the server
- normalize provider-specific events into one client protocol
- apply shared local turn-detection config across providers
- let host applications override session config on a per-call basis

## Required Environment Variables

- `OPENAI_API_KEY` for OpenAI
- `GEMINI_API_KEY` for Gemini
- `XAI_API_KEY` for Grok
- `ELEVENLABS_API_KEY` for ElevenLabs
- `PORT` for the HTTP bind port, default `8080`

## Endpoints

- `GET /` basic service metadata
- `GET /health` health check
- `GET /ws/realtime` websocket endpoint used by `arcane_voice`

If your app already has its own HTTP server and routing layer, use
`RealtimeGateway` directly instead of `ArcaneVoiceProxyServer` so you can mount
the websocket handler on a custom path such as `/call/realtime`.

## Bootstrap Example

```dart
import 'dart:io';

import 'package:arcane_voice_proxy/arcane_voice_proxy.dart';

Future<void> main() async {
  ArcaneVoiceProxyEnvironment environment =
      ArcaneVoiceProxyEnvironment.fromPlatform();
  ArcaneVoiceProxyServer proxyServer = ArcaneVoiceProxyServer(
    environment: environment,
    proxyTools: ArcaneVoiceProxyToolRegistry.empty(),
  );
  int port = int.parse(Platform.environment['PORT'] ?? '8080');
  HttpServer server = await proxyServer.serve(
    address: InternetAddress.anyIPv4,
    port: port,
  );
  stdout.writeln('Server listening on port ${server.port}');
}
```

## Session Resolution

Use a session resolver when your host needs to authenticate the caller or
override the final provider/config/tooling at session start time.

```dart
ArcaneVoiceProxyServer proxyServer = ArcaneVoiceProxyServer(
  environment: ArcaneVoiceProxyEnvironment.fromPlatform(),
  sessionResolver: (request) async {
    String sessionContextJson = request.request.sessionContextJson;

    // Authenticate and resolve your own app/session scope here.

    return ArcaneVoiceProxyResolvedSession(
      provider: RealtimeProviderCatalog.openAiId,
      config: RealtimeSessionConfig.fromRequest(request.request).copyWith(
        instructions: 'Use only the authenticated record scope.',
      ),
      proxyTools: ArcaneVoiceProxyToolRegistry.empty(),
      context: <String, Object?>{'sessionContextJson': sessionContextJson},
    );
  },
);
```

If you do not need host-owned auth or overrides, you can return a passthrough
session:

```dart
ArcaneVoiceProxyResolvedSession.passthrough(
  request: request.request,
  proxyTools: ArcaneVoiceProxyToolRegistry.empty(),
);
```

## Lifecycle Callbacks

Lifecycle callbacks make it easy to observe start/stop events, normalized usage,
and tool execution for billing or audit.

```dart
ArcaneVoiceProxyLifecycleCallbacks callbacks =
    ArcaneVoiceProxyLifecycleCallbacks(
  onSessionStarted: (event) async {
    print('started ${event.sessionId} on ${event.provider}');
  },
  onUsage: (event) async {
    print('usage ${event.usage.totalTokens}');
  },
  onToolExecuted: (event) async {
    print('tool ${event.name} -> ${event.result.success}');
  },
  onSessionStopped: (event) async {
    print('stopped ${event.sessionId} after ${event.duration}');
  },
);
```

Pass those callbacks into `ArcaneVoiceProxyServer` or `RealtimeGateway`.

## Proxy Tools

Register proxy-owned tools with `ArcaneVoiceProxyToolRegistry`:

```dart
ArcaneVoiceProxyToolRegistry proxyTools = ArcaneVoiceProxyToolRegistry(
  tools: <ArcaneVoiceProxyTool>[
    ArcaneVoiceProxyCallbackTool.jsonSchema(
      name: 'randomNumber',
      description: 'Generate a random integer for testing.',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'required': <String>[],
      },
      onExecute: (_) async => <String, Object?>{'value': 42},
    ),
  ],
);
```

Client-declared tools are also supported per session. The proxy routes those
back to the connected client through the shared realtime protocol.

## Behavior Notes

- structured control messages are decoded with `arcane_voice_models`
- streamed audio is passed as binary websocket frames
- provider-specific websocket details stay inside this package
- host applications can combine resolver-owned proxy tools with
  client-declared tools on the same call

## Related Packages

- [arcane_voice_models](https://pub.dev/packages/arcane_voice_models)
  Shared protocol and provider metadata
- [arcane_voice](https://pub.dev/packages/arcane_voice)
  Flutter client runtime
