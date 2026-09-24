# Loupe v3.11 UI polish direction

Loupe is now technically strong enough that the visual language must stop feeling like a diagnostic prototype. The controller UI should feel like a focused Apple-native remote-control surface: calm, dark, fast, and explicit about connection state.

## Goals

- Make the first screen feel like a product, not a debug tool.
- Keep the remote screen visually dominant after connection.
- Keep diagnostics available, but do not let them compete with the session.
- Make touch targets large enough for iPhone and iPad.
- Use one consistent accent color across iPhone, iPad, and Mac controller surfaces.
- Avoid adding risk to the WebRTC, SDP, ICE, TURN, and reconnect core.

## Current UI problems

- The repository has several historical UI states documented in different files.
- The controller still exposes too much implementation detail in the main flow.
- Diagnostics are useful, but the hierarchy makes the app feel unfinished.
- Visual contrast and accent usage are inconsistent across onboarding, toolbar, and diagnostics.
- Mac controller support exists, but it should be presented as a companion surface, not as the primary controller.

## Product UI rules

### 1. Remote screen first

After pairing, the remote screen is the product. Toolbars should float above it and collapse where possible. A connected user should see:

1. Screen.
2. Connection state.
3. Current input mode.
4. Disconnect/reconnect controls.
5. Diagnostics only on demand.

### 2. One primary action per screen

Pairing screens should have exactly one dominant action:

- Scan QR code on iPhone/iPad.
- Paste/open token on Mac.
- Reconnect on recoverable connection failure.

Secondary actions must be quieter.

### 3. Dark remote-control surface

Remote-control sessions should default to dark chrome, even when the system theme is light. The video content may be bright; app chrome should not fight it.

### 4. Diagnostics are a sheet, not the app

Diagnostics must remain copyable and precise, but the normal user should not read ICE state before using the product.

### 5. Platform-specific pairing

- iPhone/iPad: QR scan first, token fallback.
- Mac controller: token/file import first, no camera-first flow.

## Brand tokens

Canonical tokens are in [`brand/ui-tokens.json`](../brand/ui-tokens.json).

Primary accent:

- Light: `#6C68F6`
- Dark: `#859EFF`

The accent color asset now follows these values so existing `Color.accentColor` usage automatically improves the app without destabilizing the UI code.

## Implementation phases

### v3.11.1 — low-risk visual cleanup

- Use the new accent asset.
- Reduce README/docs drift.
- Keep all transport code unchanged.
- Add clear design rules.

### v3.11.2 — controller screen refactor

- Split the large `LoupeControllerApp.swift` into feature files:
  - `Pairing/PairingEntryView.swift`
  - `Pairing/WelcomeFlow.swift`
  - `Remote/ConnectedSessionView.swift`
  - `Remote/RemoteToolbar.swift`
  - `Diagnostics/DiagnosticsViews.swift`
  - `Design/LoupeTheme.swift`
- Replace ad-hoc cards/buttons with a small theme layer.
- Preserve public view model behavior.

### v3.11.3 — iPad layout pass

- Add split-layout for iPad landscape.
- Keep remote screen central.
- Move diagnostics and keyboard into side panels.

### v3.11.4 — Mac controller polish

- Token-first pairing.
- Native macOS window sizing.
- Menu commands for reconnect, diagnostics, and token import.

## Non-goals

- No SDP, ICE, TURN, WebRTC, or reconnect refactoring.
- No server redeploy.
- No new permissions.
- No visual rewrite that risks v3.7.2/v3.8 stability.

## Acceptance checklist

- iPhone build passes.
- iPad generic build passes.
- Native Mac controller build passes.
- iPhone regression still shows live video, input, scroll, keyboard, and reconnect.
- Onboarding looks coherent in light and dark mode.
- Remote session looks less like a debug prototype.
- Diagnostics copy remains complete.
