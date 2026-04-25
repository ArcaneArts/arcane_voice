# arcane_voice

`arcane_voice` is the Flutter client runtime for Arcane Voice realtime calls.
It owns the proxy-facing websocket transport, microphone capture, streamed audio
playback, call/session orchestration, client tool execution, and transcript
state management.

This package is intentionally UI-light. It gives apps the call runtime and
observable state; you bring the product UI.

## What's New In 1.3.0

- Coordinated release with `arcane_voice_models` and `arcane_voice_proxy`
  1.3.0.
- Twilio inbound calls are handled server-side by `arcane_voice_proxy`; Flutter
  clients keep using the same realtime websocket protocol.
- `CallSessionController` still supports `instructions` and
  `sessionContextJson` for app-originated sessions.

## Public Surface

- `CallSessionController`
  Coordinates websocket connection, audio services, provider/model/voice
  selection, mute state, transcript state, and client tool execution.
- `RealtimeSocketClient`
  Sends and receives the typed realtime protocol over websocket while leaving
  audio on binary frames.
- `AudioCaptureService`
  Captures microphone PCM audio suitable for proxy streaming.
- `AudioPlaybackService`
  Buffers and plays streamed PCM audio replies.
- `TranscriptTimeline`
  Reduces transcript delta/final events into stable conversation history.
- `ArcaneVoiceClientTool` and `ArcaneVoiceClientToolRegistry`
  Define client-executed tools the proxy can invoke during a call.
- shared exports from `arcane_voice_models`
  Provider catalog, protocol models, and turn-detection config are re-exported
  so apps do not need to import both packages directly.

## Getting Started

Point the controller at a running Arcane Voice proxy:

```dart
import 'package:arcane_voice/arcane_voice.dart';

CallSessionController controller = CallSessionController(
  serverUrl: 'ws://127.0.0.1:8080/ws/realtime',
);
```

Start and stop a call:

```dart
await controller.startCall();
await controller.stopCall();
controller.dispose();
```

## Server-Hosted Session Context

Use `sessionContextJson` when your proxy host needs to authenticate or scope the
call before starting a provider session.

```dart
CallSessionController controller = CallSessionController(
  serverUrl: 'wss://voice.example.com/ws/realtime',
  instructions: '',
  sessionContextJson: '''
  {
    "auth": {"token": "signed-session-token"},
    "scope": {"recordId": "rec_123"}
  }
  ''',
);
```

If the server is authoritative for prompts, pass an empty `instructions` string
and let the proxy resolve the final session config.

## Client Tools

Register client-side tools when the app needs to perform local actions in
response to a proxy/model tool call.

```dart
ArcaneVoiceClientToolRegistry registry = ArcaneVoiceClientToolRegistry(
  tools: <ArcaneVoiceClientTool>[
    ArcaneVoiceClientTool.jsonSchema(
      name: 'show_record',
      description: 'Show a record inside the local app UI.',
      parameters: <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'recordId': <String, Object?>{'type': 'string'},
        },
        'required': <String>['recordId'],
      },
      execute: (arguments) async {
        return <String, Object?>{
          'shown': true,
          'recordId': arguments['recordId'],
        };
      },
    ),
  ],
);
```

Then pass the registry into the controller:

```dart
CallSessionController controller = CallSessionController(
  serverUrl: 'ws://127.0.0.1:8080/ws/realtime',
  clientToolRegistry: registry,
);
```

## Runtime State

`CallSessionController` exposes:

- `sessionState`
- `callActive`
- `connecting`
- `muted`
- `provider`, `model`, and `voice`
- `lastError`
- `transcriptEntries`

It also exposes action methods and handlers such as:

- `startCall()`
- `stopCall()`
- `mute()`
- `unmute()`
- `onProviderChanged(...)`
- `onVoiceChanged(...)`
- `onInstructionsChanged(...)`
- `onSessionContextJsonChanged(...)`

## Permissions

Apps using this package need microphone and network permissions. The repository
example app includes working Android, iOS, and macOS setup.

## Protocol Boundary

Structured control/config traffic uses the typed models from
`arcane_voice_models`. Audio remains raw binary websocket frames so the client
runtime stays low-latency and provider-agnostic.

## Related Packages

- [arcane_voice_models](https://pub.dev/packages/arcane_voice_models)
  Shared protocol models and codec
- [arcane_voice_proxy](https://pub.dev/packages/arcane_voice_proxy)
  Proxy server runtime
