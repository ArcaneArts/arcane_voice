# arcane_voice_proxy

`arcane_voice_proxy` hosts the Arcane Voice realtime proxy server. It accepts a
typed websocket protocol from clients, forwards audio to provider-specific
realtime APIs, executes proxy-side tools, and streams audio back to the client.

This package is the server-side counterpart to
[arcane_voice](https://pub.dev/packages/arcane_voice). It keeps provider auth,
session policy, usage reporting, and tool execution behind one stable
client-facing websocket interface.

## What's New In 1.3.0

- Twilio inbound calls can connect directly to the proxy through
  `/twilio/voice` and `/ws/twilio`.
- Twilio caller metadata is attached to session context and exposed through
  `ArcaneVoiceTwilioCallContext`.
- Hosts can use `sessionResolver` to map caller phone numbers to scoped
  prompts, RAG data, provider config, and per-session proxy tools.
- Proxy-configurable VAD mode supports `auto`, `local`, and `provider`.

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
- `ArcaneVoiceTwilioConfig`, `ArcaneVoiceTwilioGateway`, and
  `ArcaneVoiceTwilioCallContext` for Twilio inbound call hosting and routing

## Responsibilities

- accept the shared typed realtime protocol from clients
- keep provider auth and session details off the client
- execute proxy-owned tools on the server
- normalize provider-specific events into one client protocol
- support either local turn detection or provider-native VAD from one proxy API
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
- `GET|POST /twilio/voice` Twilio Voice webhook that returns
  `<Connect><Stream>` TwiML
- `GET /ws/twilio` Twilio Media Streams websocket endpoint

If your app already has its own HTTP server and routing layer, use
`RealtimeGateway` directly instead of `ArcaneVoiceProxyServer` so you can mount
the websocket handler on a custom path such as `/call/realtime`.

## Twilio Voice

Point a Twilio phone number's incoming-call webhook at your public proxy URL:

```text
https://voice.example.com/twilio/voice
```

The proxy responds with TwiML that connects the call to:

```text
wss://voice.example.com/ws/twilio
```

Twilio call metadata such as `From`, `To`, `CallSid`, and `AccountSid` is
passed into the stream as custom parameters and then attached to
`sessionContextJson`:

```json
{
  "source": "twilio",
  "twilio": {
    "callSid": "CA...",
    "from": "+15551230000",
    "to": "+15557654321"
  }
}
```

Use `sessionResolver` to authorize by caller/called number and return the final
provider config, prompt, tools, and context for that call.

```dart
ArcaneVoiceProxyToolRegistry toolsForCaller(String callerNumber) {
  return ArcaneVoiceProxyToolRegistry(
    tools: <ArcaneVoiceProxyTool>[
      ArcaneVoiceProxyCallbackTool.jsonSchema(
        name: 'query_authorized_records',
        description: 'Search records permitted for this caller.',
        parameters: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'query': <String, Object?>{'type': 'string'},
          },
          'required': <String>['query'],
        },
        onExecute: (arguments) async {
          return queryRagForCaller(callerNumber, arguments['query']);
        },
      ),
    ],
  );
}

ArcaneVoiceProxyServer proxyServer = ArcaneVoiceProxyServer(
  environment: ArcaneVoiceProxyEnvironment.fromPlatform(),
  sessionResolver: (request) async {
    ArcaneVoiceTwilioCallContext? twilio =
        ArcaneVoiceTwilioCallContext.maybeFromSessionRequest(request);
    String? callerNumber = twilio?.callerNumber;

    if (callerNumber == null || !isAuthorizedCaller(callerNumber)) {
      throw StateError('Caller is not authorized.');
    }

    return ArcaneVoiceProxyResolvedSession(
      provider: RealtimeProviderCatalog.openAiId,
      config: RealtimeSessionConfig.fromRequest(request.request).copyWith(
        instructions:
            'Use only records authorized for caller $callerNumber.',
      ),
      proxyTools: toolsForCaller(callerNumber),
      context: <String, Object?>{
        'callerNumber': callerNumber,
        'twilio': twilio?.toJson(),
      },
    );
  },
);
```

Optional environment variables for the built-in server:

- `TWILIO_STREAM_URL` absolute websocket URL when the proxy cannot derive the
  public `wss://` URL from forwarded headers
- `TWILIO_PROVIDER`, `TWILIO_MODEL`, `TWILIO_VOICE`
- `TWILIO_INSTRUCTIONS`, `TWILIO_INITIAL_GREETING`
- `TWILIO_VOICE_WEBHOOK_PATH`, `TWILIO_STREAM_WEBSOCKET_PATH`

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
    vadMode: ArcaneVoiceProxyVadMode.auto,
  );
  int port = int.parse(Platform.environment['PORT'] ?? '8080');
  HttpServer server = await proxyServer.serve(
    address: InternetAddress.anyIPv4,
    port: port,
  );
  stdout.writeln('Server listening on port ${server.port}');
}
```

## VAD Mode

Configure turn detection once at proxy setup time:

```dart
ArcaneVoiceProxyServer proxyServer = ArcaneVoiceProxyServer(
  environment: ArcaneVoiceProxyEnvironment.fromPlatform(),
  vadMode: ArcaneVoiceProxyVadMode.auto,
);
```

Modes:

- `ArcaneVoiceProxyVadMode.auto`
  Uses provider-native VAD where the provider adapter supports it well. This is
  the default.
- `ArcaneVoiceProxyVadMode.local`
  Uses Arcane Voice's proxy-side turn detector for providers that support manual
  turn handling.
- `ArcaneVoiceProxyVadMode.provider`
  Prefers each provider's own server-side VAD / activity detection behavior.

You can also override the mode per resolved session:

```dart
return ArcaneVoiceProxyResolvedSession(
  provider: RealtimeProviderCatalog.openAiId,
  config: RealtimeSessionConfig.fromRequest(request.request),
  proxyTools: ArcaneVoiceProxyToolRegistry.empty(),
  vadMode: ArcaneVoiceProxyVadMode.provider,
);
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
