// Loupe macOS host — entry-point shim.
//
// There are two entry points:
//   1. LoupeHostApp (SwiftUI @main, in LoupeHostApp.swift) — used when
//      launched as a `.app` bundle.
//   2. LoupeHostCLI.run() (in LoupeHostCLI.swift) — used when launched
//      from the command line, e.g. via `swift run LoupeHost`.
//
// SwiftPM does not let one executable have both an `@main` attribute
// and a top-level script body in different files, so we keep a single
// `main.swift`-style file that picks between the two at runtime based
// on how the process was launched:
//
//   - If the parent process is launchd (the user double-clicked the
//     `.app`), NSApplication.shared is initialised by LoupeHostApp's
//     `@main` attribute — but only if `@main` is in scope. Because
//     we cannot have both `@main` here and in LoupeHostApp.swift, we
//     pick a different signal: the executable name. When the bundle
//     runs, the executable is `LoupeHost.app/Contents/MacOS/LoupeHost`;
//     when launched from CLI it's also `LoupeHost`. So we look at
//     argv[0] instead.
//
// The SwiftUI `@main` is in `LoupeHostApp.swift` and that is the
// default entry point. To run the CLI mode, pass `--cli` as the
// first argument, or run from `swift run LoupeHost` (which appends
// the executable path).

import Foundation
import CoreGraphics
import LoupeHostCore

private enum HostDefaults {
    static let sessionId = "loupe-beta-session"
    static let signalingURL = "wss://signaling.theloupe.team/ws"
    static let hostKeychainAccount = "macos-host"
}

func parseArguments() -> (sessionId: String, signalingURL: URL, cli: Bool) {
    let args = CommandLine.arguments
    // Drop the first "--cli" flag if present so the rest of the
    // argument parsing is identical to the old main.swift logic.
    var argv = args
    var cli = false
    if argv.count > 1, argv[1] == "--cli" {
        cli = true
        argv.removeFirst()
    }
    let sessionId = argv.count > 1 ? argv[1] : HostDefaults.sessionId
    let urlString = argv.count > 2 ? argv[2] : HostDefaults.signalingURL
    guard let url = URL(string: urlString) else {
        FileHandle.standardError.write(Data("Invalid signaling URL: \(urlString)\n".utf8))
        exit(2)
    }
    return (sessionId, url, cli)
}

// When the binary is launched as a `.app` bundle (e.g. via Finder or
// `open`), the parent process is launchd, the binary lives inside
// `LoupeHost.app/Contents/MacOS/`, and the user expects a GUI window.
// When launched from the command line, there is no `.app` bundle, so
// we run the legacy CLI entry point instead.
func isLikelyBundledLaunch() -> Bool {
    // Bundle.main.bundleIdentifier is set only when the executable lives
    // inside a `.app` bundle with a proper Info.plist.
    return Bundle.main.bundleIdentifier != nil
}

let (sessionId, signalingURL, cliRequested) = parseArguments()

if cliRequested || !isLikelyBundledLaunch() {
    // CLI mode. Print diagnostics to stderr and wait for SIGINT.
    LoupeHostCLI.run(
        sessionId: sessionId,
        signalingURL: signalingURL,
        hostKeychainAccount: HostDefaults.hostKeychainAccount
    )
} else {
    // Bundled launch. Hand control to SwiftUI.
    LoupeHostApp.main()
}
