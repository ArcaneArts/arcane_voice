## 1.3.0

- Prepared a coordinated 1.3.0 release with the proxy and shared models.
- Updated the shared model dependency to `arcane_voice_models` 1.3.0.
- No client API changes are required for Twilio inbound calls; Twilio sessions
  are resolved server-side by `arcane_voice_proxy`.

## 1.1.0

- Added `sessionContextJson` support to the client session start flow.
- Added configurable `instructions` and `sessionContextJson` fields to `CallSessionController`.
- Removed deprecated client tool aliases so the public API uses the `ArcaneVoice...` names only.
- Updated docs and examples for server-resolved session flows.

## 1.0.0

- Initial version.
