// Re-export the Core API surface so apps can keep writing a single
// `import LoupeController`. WebRTC-specific types (e.g. the concrete
// libwebrtc PeerConnection impl) are intentionally NOT re-exported:
// those are an implementation detail the app uses only indirectly via
// ControllerFactory.makeViewModel(...).
//
// This file has no executable code. The `@_exported import` propagates
// all of LoupeCore's public types into the LoupeController module
// namespace, so `import LoupeController` in apps is enough to see
// ControllerViewModel, PairingScannerView, PairingPayload, etc.
@_exported import LoupeCore
