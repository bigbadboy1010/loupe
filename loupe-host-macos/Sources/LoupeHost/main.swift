// Loupe macOS host — entry-point shim.
//
// There are two entry paths in the same executable:
//   1. LoupeHostApp.main() — product GUI used by the bundled .app and Xcode
//      when launched with `--app`.
//   2. LoupeHostCLI.run() — developer/fallback CLI used by `--cli` and by
//      plain `swift run LoupeHost`.
//
// SwiftPM does not provide a native macOS .app bundle for executable targets,
// so Xcode's SwiftPM scheme normally launches the raw executable. The explicit
// `--app` argument makes that raw executable enter the SwiftUI host UI anyway,
// which lets developers run the Host Pairing UI directly from Xcode without
// first packaging /Applications/LoupeHost.app.

import Foundation
import CoreGraphics
import LoupeHostCore

private enum HostDefaults {
    static let sessionId = "loupe-beta-session"
    static let signalingURL = "wss://signaling.theloupe.team/ws"
    static let hostKeychainAccount = "macos-host"
}

private struct HostLaunchOptions {
    let sessionId: String
    let signalingURL: URL
    let mode: Mode

    enum Mode {
        case automatic
        case app
        case cli
    }
}

private func parseArguments() -> HostLaunchOptions {
    var argv = CommandLine.arguments
    let executable = argv.removeFirst()
    var mode: HostLaunchOptions.Mode = .automatic

    if let first = argv.first {
        switch first {
        case "--app":
            mode = .app
            argv.removeFirst()
        case "--cli":
            mode = .cli
            argv.removeFirst()
        case "--help", "-h":
            print("""
            LoupeHost

            Usage:
              LoupeHost --app [sessionId] [signalingURL]   Start the SwiftUI Host app UI.
              LoupeHost --cli [sessionId] [signalingURL]   Start the developer CLI host.
              LoupeHost [sessionId] [signalingURL]         Auto: .app bundle => UI, raw executable => CLI.

            Defaults:
              sessionId:    \(HostDefaults.sessionId)
              signalingURL: \(HostDefaults.signalingURL)
            """)
            exit(0)
        default:
            break
        }
    }

    let sessionId = argv.count > 0 ? argv[0] : HostDefaults.sessionId
    let urlString = argv.count > 1 ? argv[1] : HostDefaults.signalingURL
    guard let url = URL(string: urlString) else {
        FileHandle.standardError.write(Data("Invalid signaling URL: \(urlString)\n".utf8))
        FileHandle.standardError.write(Data("Executable: \(executable)\n".utf8))
        exit(2)
    }
    return HostLaunchOptions(sessionId: sessionId, signalingURL: url, mode: mode)
}

// When the binary is launched as a `.app` bundle via Finder or `open`,
// Bundle.main.bundleIdentifier is set by Info.plist and the user expects a
// GUI window. When launched as a raw SwiftPM executable, there is no bundle
// identifier; in that case keep the legacy CLI unless `--app` is explicit.
private func isLikelyBundledLaunch() -> Bool {
    Bundle.main.bundleIdentifier != nil
}

let options = parseArguments()

switch options.mode {
case .app:
    LoupeHostApp.main()
case .cli:
    LoupeHostCLI.run(
        sessionId: options.sessionId,
        signalingURL: options.signalingURL,
        hostKeychainAccount: HostDefaults.hostKeychainAccount
    )
case .automatic:
    if isLikelyBundledLaunch() {
        LoupeHostApp.main()
    } else {
        LoupeHostCLI.run(
            sessionId: options.sessionId,
            signalingURL: options.signalingURL,
            hostKeychainAccount: HostDefaults.hostKeychainAccount
        )
    }
}
