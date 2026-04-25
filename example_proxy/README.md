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
- `GET|POST /twilio/voice`
- `GET /ws/twilio`

For Twilio inbound calls, configure the phone number voice webhook to:

```text
https://your-public-host.example/twilio/voice
```

Set `TWILIO_STREAM_URL=wss://your-public-host.example/ws/twilio` if the server
is behind a proxy that does not provide forwarded host/proto headers.

This project stays intentionally small. The provider logic and websocket
protocol handling live in `arcane_voice_proxy`.
