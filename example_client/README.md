# example_client

Minimal Flutter demo app for the `arcane_voice` package.

## Run

```bash
flutter run
```

To point at a different local proxy:

```bash
flutter run --dart-define=REALTIME_SERVER_URL=ws://127.0.0.1:8080/ws/realtime
```

Android emulator note:

```bash
flutter run --dart-define=REALTIME_SERVER_URL=ws://10.0.2.2:8080/ws/realtime
```

## What it demonstrates

- provider switching
- voice selection
- realtime transcript rendering
- microphone capture and streamed audio playback through `arcane_voice`

## Permissions

This example includes the microphone and network permissions needed for Android,
iOS, and macOS voice calls.
