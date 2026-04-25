## 1.3.1

- Fixed Twilio Media Streams barge-in behavior by clearing Twilio's buffered
  assistant audio when caller speech starts during an active response.
- Fixed Grok provider-VAD barge-in so provider-detected caller speech cancels
  the active response before Twilio playback is cleared.

## 1.3.0

- Added Twilio Voice inbound-call support through a built-in voice webhook and
  bidirectional Media Streams websocket bridge.
- Added `ArcaneVoiceTwilioConfig`, `ArcaneVoiceTwilioGateway`,
  `ArcaneVoiceTwilioCallContext`, and Twilio audio/TwiML helpers to the public
  proxy API.
- Attached Twilio `From`, `To`, `CallSid`, `AccountSid`, direction, status, and
  custom parameters to `sessionContextJson` for server-side session resolution.
- Added typed Twilio call-context parsing helpers so hosts can map caller phone
  numbers to per-session prompts, RAG scopes, and proxy tool registries.
- Documented Twilio setup, TLS/WSS requirements, and phone-number scoped
  session resolver patterns.

## 1.1.4

- Added `ArcaneVoiceProxyVadMode` to proxy setup so hosts can choose
  `auto`, `local`, or `provider` turn detection behavior.
- Defaulted proxy VAD mode to `auto`, which prefers provider-native VAD when a
  provider adapter supports it.
- Wired OpenAI, Grok, and Gemini sessions to switch between local/manual turn
  handling and provider-native activity detection from the proxy API.

## 1.1.3

- Fixed ElevenLabs `client_tool_result` payload serialization so structured tool outputs are returned as JSON strings instead of raw objects.
- Prevented ElevenLabs websocket sessions from being closed after successful proxy tool execution due to invalid result message shapes.

## 1.1.2

- Normalized generic JSON Schema into the stricter ElevenLabs client-tool schema subset before tool registration.
- Removed unsupported keys like `additionalProperties` and synthesized valid literal descriptions for array item and leaf parameter schemas so ElevenLabs accepts tools like `query_record`.

## 1.1.1

- Fixed ElevenLabs client tool registration to send schemas under `parameters` instead of `params`, so agents can see and use full tool argument definitions.
- Added a regression test covering ElevenLabs client tool schema generation.

## 1.1.0

- Added session resolution hooks for host-owned auth, config overrides, and per-session tools.
- Added lifecycle callbacks for session start, usage observation, tool execution, and session stop.
- Normalized provider usage reporting across OpenAI, Gemini, Grok, and ElevenLabs flows.
- Removed deprecated `server*` alias API so the public surface uses `proxyTools` and `ArcaneVoice...` names only.
- Updated docs and examples for authenticated server-hosted sessions.

## 1.0.0

- Initial version.
