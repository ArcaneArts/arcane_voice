# arcane_voice_models

Shared models and protocol helpers for the Arcane realtime voice client and
proxy packages.

This package is the source of truth for the client <-> proxy contract. It owns
the typed websocket control protocol, provider catalog metadata, shared
turn-detection config, and the protocol codec used by both the Flutter client
package and the proxy/server package.

## What is in this package

- Artifact-backed realtime client and server message models
- Shared provider definitions and default voice/model metadata
- Shared turn detection config models
- `RealtimeProtocolCodec` for JSON encode/decode of control messages

## What is not in this package

- No audio capture or playback logic
- No websocket client implementation
- No proxy server or provider integrations
- No UI widgets

Those live in
[arcane_voice](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice)
and
[arcane_voice_proxy](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/arcane_voice_proxy).

## Getting Started

Import the package entrypoint:

```dart
import 'package:arcane_voice_models/arcane_voice_models.dart';
```

Use the codec for structured websocket control messages:

```dart
String json = RealtimeProtocolCodec.encodeClientJson(
  const RealtimePingRequest(),
);

RealtimeServerMessage message =
    RealtimeProtocolCodec.decodeServerJson(source);
```

Provider metadata is shared here as well:

```dart
RealtimeProviderDefinition provider = RealtimeProviderCatalog.gemini;
String defaultVoice = provider.defaultVoice;
```

## Wire format notes

- JSON messages cover structured control/config events only
- audio is intentionally not modeled here and stays as raw binary websocket
  frames
- the goal is one stable protocol that multiple client and proxy packages can
  share without duplicating JSON maps

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

- [arcane_voice](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice)
  depends on this package for all typed client <-> proxy models
- [arcane_voice_proxy](/Users/cyberpwn/development/workspace/ArcaneArts/arcane_voice/arcane_voice_proxy)
  depends on this package for the same protocol and provider metadata
- the example apps depend on their runtime packages rather than on this package
  directly
