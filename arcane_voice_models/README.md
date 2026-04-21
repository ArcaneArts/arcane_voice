# arcane_voice_models

Shared models and protocol helpers for the Arcane Voice client and proxy
packages.

This package is the source of truth for the client-to-proxy contract. It owns
the typed websocket control protocol, provider catalog metadata, shared
turn-detection config, and the protocol codec used by both the Flutter client
package and the proxy/server package.

## What's New In 1.1.0

- `RealtimeSessionStartRequest` now includes `sessionContextJson`.
- Tool execution target naming is standardized on
  `RealtimeToolExecutionTarget.arcaneVoiceProxy` and
  `RealtimeToolExecutionTarget.arcaneVoiceClient`.

## What Is In This Package

- artifact-backed realtime client and server message models
- shared provider definitions and default voice/model metadata
- shared turn detection config models
- `RealtimeProtocolCodec` for JSON encode/decode of control messages

## What Is Not In This Package

- no audio capture or playback logic
- no websocket client implementation
- no proxy server or provider integrations
- no UI widgets

Those live in [arcane_voice](https://pub.dev/packages/arcane_voice) and
[arcane_voice_proxy](https://pub.dev/packages/arcane_voice_proxy).

## Getting Started

Import the package entrypoint:

```dart
import 'package:arcane_voice_models/arcane_voice_models.dart';
```

Encode a typed session start request:

```dart
RealtimeSessionStartRequest request = RealtimeSessionStartRequest(
  provider: RealtimeProviderCatalog.openAiId,
  model: RealtimeProviderCatalog.openAi.defaultModel,
  voice: RealtimeProviderCatalog.openAi.defaultVoice,
  instructions: 'Be brief and warm.',
  sessionContextJson: '{"scope":{"recordId":"rec_123"}}',
  clientTools: const <RealtimeToolDefinition>[],
);

String source = RealtimeProtocolCodec.encodeClientJson(request);
```

Decode server events:

```dart
RealtimeServerMessage message =
    RealtimeProtocolCodec.decodeServerJson(sourceFromSocket);
```

## Session Context

`sessionContextJson` is intentionally opaque to this package. It is transported
verbatim so host applications can attach signed auth/session/scope data without
teaching the protocol package about any product-specific user model.

## Wire Format Notes

- JSON messages cover structured control/config events only.
- Audio is intentionally not modeled here and stays as raw binary websocket
  frames.
- The goal is one stable protocol shared by multiple clients and proxies
  without duplicated JSON maps.

## Artifact Workflow

The shared models use [`artifact`](https://pub.dev/packages/artifact).

When any annotated model changes, regenerate code:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Generated files live in `lib/gen/`.

The public entrypoint for consumers is:

```dart
import 'package:arcane_voice_models/arcane_voice_models.dart';
```

## Package Relationships

- [arcane_voice](https://pub.dev/packages/arcane_voice)
  depends on this package for all typed client-to-proxy models
- [arcane_voice_proxy](https://pub.dev/packages/arcane_voice_proxy)
  depends on this package for the same protocol and provider metadata
