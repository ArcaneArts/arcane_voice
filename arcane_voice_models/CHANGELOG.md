## 1.3.0

- Prepared a coordinated 1.3.0 release for Twilio-enabled proxy sessions.
- Kept the wire protocol stable while preserving `sessionContextJson` as the
  opaque transport for host-owned routing, auth, and RAG scope metadata.

## 1.1.0

- Added `sessionContextJson` to `RealtimeSessionStartRequest`.
- Standardized tool execution target naming on `arcaneVoiceProxy` and `arcaneVoiceClient`.
- Updated protocol documentation and tests for session context round-tripping.

## 1.0.0

- Initial version.
