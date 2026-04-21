# arcane_voice

`arcane_voice` is the Flutter client runtime for Arcane Voice realtime calls.
It owns the proxy-facing websocket transport, microphone capture, streamed audio
playback, call/session orchestration, and transcript state management.

This package is intentionally UI-light. It gives apps the call runtime and
state; the demo UI lives in
[example_client](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/example_client).

## Public surface

- `CallSessionController`
  Coordinates the websocket session, audio services, provider selection, voice
  selection, mute state, and transcript state.
- `RealtimeSocketClient`
  Sends and receives the typed realtime protocol over websocket, with audio kept
  as binary frames.
- `AudioCaptureService`
  Captures microphone PCM audio suitable for proxy streaming.
- `AudioPlaybackService`
  Buffers and plays streamed PCM audio replies.
- `TranscriptTimeline`
  Reduces transcript delta/final events into stable conversation history.
- shared exports from `arcane_voice_models`
  Provider catalog, protocol models, and turn-detection config are re-exported
  so client apps do not need to import both packages directly.

## Getting started

Point the controller at a running Arcane Voice proxy:

```dart
import 'package:arcane_voice/arcane_voice.dart';

CallSessionController controller = CallSessionController(
  serverUrl: 'ws://127.0.0.1:8080/ws/realtime',
);
```

Typical app flow:

```dart
await controller.startCall();

controller.onProviderChanged(RealtimeProviderCatalog.gemini);
controller.onVoiceChanged('Kore');

await controller.stopCall();
controller.dispose();
```

The controller exposes the current:

- session state
- transcript entries
- provider, model, and voice selection
- start, stop, mute, and unmute actions
- latest proxy/provider error

## Permissions

Apps using this package need microphone and network permissions. See
[example_client](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/example_client)
for working Android, iOS, and macOS setup.

## Protocol boundary

Structured control/config traffic uses the typed models from
`arcane_voice_models`. Audio remains raw binary websocket frames so the client
runtime can stay low-latency and provider-agnostic.

## Related packages

- [arcane_voice_models](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/arcane_voice_models)
  Shared protocol models and codec
- [arcane_voice_proxy](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/arcane_voice_proxy)
  Proxy server runtime
- [example_client](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/example_client)
  Minimal demo app using this package
