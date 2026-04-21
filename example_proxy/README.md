# example_proxy

Minimal runnable proxy host for the `arcane_voice_proxy` package.

## Run

```bash
OPENAI_API_KEY=... GEMINI_API_KEY=... XAI_API_KEY=... dart run bin/server.dart
```

Optional:

```bash
PORT=8080
```

## Endpoints

- `GET /`
- `GET /health`
- `GET /ws/realtime`

This project stays intentionally small. The provider logic and websocket
protocol handling live in `arcane_voice_proxy`.
