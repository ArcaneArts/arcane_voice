# Arcane Voice Package Conversion Plan

## Summary

Move the current working realtime voice stack out of `Arcana` and into the package workspace at `../arcane_voice`, with `arcane_voice_models` as the shared protocol package, `arcane_voice` as the Flutter client API, `arcane_voice_proxy` as the proxy/server API, and `example_client` / `example_proxy` as the minimal runnable demos.

This first package split should preserve current behavior and wire format. The goal is to relocate and organize the existing implementation, not redesign the protocol. Audio stays as binary websocket frames, and all structured control/config traffic stays model-driven through `arcane_voice_models`.

## Package Structure And Public API

### `arcane_voice_models`
- Keep this as the single source of truth for all client <-> proxy protocol models and shared provider metadata.
- Preserve the existing Artifact-based setup and generated API style.
- Public exports should come from `lib/arcane_voice_models.dart` only.
- Keep the current protocol codec in this package so both client and proxy use the same encode/decode logic.
- Include:
  - realtime client/server message models
  - turn detection config models
  - provider catalog / provider definitions / default model and voice metadata
  - protocol codec helpers
- Add `PLAN.md` at the package root and treat it as the migration checklist for the package workspace.
- Update `README.md` to document:
  - what the package contains
  - Artifact generation workflow
  - what is and is not part of the protocol
  - how client and proxy packages depend on it

### `arcane_voice`
- Move all client-side call/session logic out of the app and into the package.
- Public API should expose a small, reusable surface:
  - call/session controller
  - websocket client
  - audio capture service
  - audio playback service
  - transcript timeline / transcript models if needed by UI
  - provider-aware defaults sourced from `arcane_voice_models`
- Keep UI widgets out of the package unless they are intentionally reusable.
- If the current call screen is needed for demo parity, keep it in `example_client`, not in the package.
- Package internals may use `src/` organization, but the public `lib/arcane_voice.dart` export surface should be intentional and compact.
- Update `README.md` to document:
  - how to start a call to a proxy
  - required Flutter dependencies and permissions
  - how to configure the websocket URL
  - what the controller exposes to app UIs

### `arcane_voice_proxy`
- Move all proxy/server logic out of the app and into the package.
- Public API should expose the minimal pieces needed to host the proxy:
  - server app / server bootstrap helpers
  - realtime gateway
  - environment/config objects
  - provider session implementations
  - shared support utilities used by providers
- Keep provider integrations for the currently working set:
  - OpenAI realtime
  - Gemini Live
  - Grok voice
- Preserve current behavior for:
  - typed model-based websocket control messages
  - binary audio passthrough
  - provider-specific realtime event handling
  - shared local turn detection config usage
- Update `README.md` to document:
  - required environment variables
  - how to start the proxy
  - supported providers
  - expected websocket path and protocol behavior

### `example_client`
- Replace the stock Flutter counter app with the current Arcana demo UI.
- Keep the UI behavior and layout essentially the same as the current working app.
- The example app should depend on `arcane_voice` and use its controller/services rather than containing copied business logic.
- The example app may contain only:
  - app bootstrapping
  - theme
  - demo screen/widgets
  - wiring to the package controller
- Add or rewrite `README.md` to document:
  - how to run the example
  - how to point it at a local proxy
  - any desktop/mobile permission notes

### `example_proxy`
- Replace the stock Shelf echo server with a minimal proxy host that uses `arcane_voice_proxy`.
- Keep the example extremely small: env loading, server bootstrap, bind/serve, and nothing else.
- Add or rewrite `README.md` to document:
  - how to run it
  - required env vars by provider
  - how it relates to `arcane_voice_proxy`

## Implementation Changes

### Migration Order
1. Treat `arcane_voice_models` as already seeded and verify it matches the current working protocol from `Arcana`.
2. Copy the current client transport/session/audio/transcript logic into `arcane_voice`, preserving behavior while reorganizing into package-friendly `src/` files.
3. Copy the current proxy/gateway/provider logic into `arcane_voice_proxy`, preserving behavior while organizing into package-friendly `src/` files.
4. Rebuild `example_client` so it uses `arcane_voice` instead of app-local call logic.
5. Rebuild `example_proxy` so it uses `arcane_voice_proxy` instead of app-local server logic.
6. Rewrite package READMEs after code migration so the docs match the actual public surfaces.

### Package Boundaries
- `arcane_voice_models` owns protocol definitions and provider metadata only.
- `arcane_voice` owns Flutter-side runtime logic and app-facing controller APIs.
- `arcane_voice_proxy` owns server runtime logic and provider integrations.
- `example_client` and `example_proxy` must not duplicate core logic from the packages.

### Wire And Behavior Compatibility
- Preserve the current websocket protocol names and message shapes.
- Preserve binary audio frame handling.
- Preserve current default providers, default models, default voices, and shared turn detection behavior.
- Preserve current transcript flow and state sequencing so existing behavior remains testable during the move.

### File Organization Expectations
- Use package entrypoints as thin exports.
- Put implementation in `lib/src/...`.
- Keep provider-specific code separated by provider in `arcane_voice_proxy`.
- Keep transport/audio/transcript concerns separated in `arcane_voice`.
- Keep generated Artifact files in `arcane_voice_models/lib/gen`.

## Test Plan

### `arcane_voice_models`
- Run Artifact generation with `dart run build_runner build --delete-conflicting-outputs`.
- Verify codec round-trips for representative client and server messages.
- Verify provider catalog defaults and turn detection defaults remain unchanged.

### `arcane_voice`
- Run `flutter analyze` and package tests.
- Add or preserve tests for:
  - transcript timeline behavior
  - controller event handling
  - websocket message decoding path
- Manual acceptance:
  - example client can connect to example proxy
  - provider switcher and voice dropdown still work
  - transcript UI still behaves like the current app

### `arcane_voice_proxy`
- Run `dart analyze` and package tests.
- Preserve or move the current websocket protocol test so typed ping/pong and connection-ready behavior remain covered.
- Manual acceptance:
  - example proxy serves root/health/websocket endpoints
  - OpenAI, Gemini, and Grok sessions can still start through the package-hosted proxy
  - server logs remain readable and behavior matches current runtime

### Examples
- `example_client` launches and shows the current demo UI.
- `example_proxy` starts with minimal code and exposes the realtime websocket.
- End-to-end smoke test:
  - start `example_proxy`
  - launch `example_client`
  - connect with each provider
  - verify session start, transcript flow, and streamed audio still work

## Documentation Changes

- `arcane_voice_models/PLAN.md`
  - store this migration plan there as the authoritative split checklist
- `arcane_voice_models/README.md`
  - protocol package overview, Artifact workflow, shared model usage
- `arcane_voice/README.md`
  - client package overview, controller usage, configuration, permissions
- `arcane_voice_proxy/README.md`
  - proxy package overview, server bootstrap, env vars, supported providers
- `example_client/README.md`
  - run instructions and demo usage
- `example_proxy/README.md`
  - run instructions and env setup

## Assumptions And Defaults

- `PLAN.md` should be created in `../arcane_voice/arcane_voice_models`, assuming “arcane_models” meant `arcane_voice_models`.
- The package split should preserve the current working feature set, including OpenAI, Gemini, and Grok support.
- The current protocol from `Arcana` is the baseline and should be migrated as-is unless a packaging change is required to make the code reusable.
- The example apps are intentionally non-publishable and should stay minimal, with most logic living in the packages.
- No protocol redesign, auth redesign, or model/schema redesign is part of this pass; this is a packaging and organization migration first.
