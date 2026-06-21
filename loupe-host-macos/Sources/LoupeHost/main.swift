import Foundation
import CoreGraphics
import LoupeHostKit

#if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import ImageIO
import UniformTypeIdentifiers
#endif

// Loupe macOS host — command-line bring-up entry point.
//
// Usage:
//   LoupeHost [sessionId] [signalingURL]
//
// Production defaults are preconfigured for the deployed public endpoint:
//   sessionId:    loupe-dev-session
//   signalingURL: wss://signaling.theloupe.team/ws
//
// Requires Screen Recording and Accessibility permissions. If missing, it prints
// what to grant and triggers the system prompts.

private enum HostDefaults {
    static let sessionId = "loupe-dev-session"
    static let signalingURL = "wss://signaling.theloupe.team/ws"
    static let hostKeychainAccount = "macos-host"
}

func parseArguments() -> (sessionId: String, signalingURL: URL) {
    let args = CommandLine.arguments
    let sessionId = args.count > 1 ? args[1] : HostDefaults.sessionId
    let urlString = args.count > 2 ? args[2] : HostDefaults.signalingURL
    guard let url = URL(string: urlString) else {
        FileHandle.standardError.write(Data("Invalid signaling URL: \(urlString)\n".utf8))
        exit(2)
    }
    return (sessionId, url)
}

func mainDisplayBounds() -> CGRect {
    let displayId = CGMainDisplayID()
    return CGDisplayBounds(displayId)
}

func onlineDisplaySummaries() -> [String] {
    var count: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &count)
    guard count > 0 else { return [] }
    var displays = Array(repeating: CGDirectDisplayID(0), count: Int(count))
    CGGetOnlineDisplayList(count, &displays, &count)
    return displays.prefix(Int(count)).map { displayId in
        let bounds = CGDisplayBounds(displayId)
        let isMain = displayId == CGMainDisplayID()
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let originX = Int(bounds.origin.x)
        let originY = Int(bounds.origin.y)
        return "display id=\(displayId) main=\(isMain) bounds=\(width)x\(height)@\(originX),\(originY)"
    }
}

func printDisplayDiagnostics() {
    let summaries = onlineDisplaySummaries()
    FileHandle.standardError.write(Data("Display count: \(summaries.count)\n".utf8))
    for summary in summaries {
        FileHandle.standardError.write(Data("[LoupeHost] \(summary)\n".utf8))
    }
}

func ensurePermissions() {
    var status = Permissions.current()
    if !status.screenRecording {
        FileHandle.standardError.write(Data("Requesting Screen Recording permission…\n".utf8))
        Permissions.requestScreenRecording()
    }
    if !status.accessibility {
        FileHandle.standardError.write(Data("Requesting Accessibility permission…\n".utf8))
        Permissions.requestAccessibility()
    }
    status = Permissions.current()
    if !status.allGranted {
        let message =
            "Missing permissions — grant both in System Settings › Privacy & Security, then re-run:\n" +
            "  Screen Recording: \(status.screenRecording ? "OK" : "MISSING")\n" +
            "  Accessibility:    \(status.accessibility ? "OK" : "MISSING")\n"
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
}

func loadIdentityOrExit() -> DeviceIdentity {
    do {
        return try DeviceIdentity.loadOrCreate(storage: KeychainKeyStorage(account: HostDefaults.hostKeychainAccount))
    } catch {
        FileHandle.standardError.write(Data("Failed to load host identity from Keychain: \(error)\n".utf8))
        exit(1)
    }
}

func printPairingToken(sessionId: String, signalingURL: URL, identity: DeviceIdentity, hostId: String) {
    let payload = PairingPayload(
        sessionId: sessionId,
        hostId: hostId,
        hostKey: identity.publicKeyBase64URL,
        signaling: signalingURL.absoluteString
    )
    do {
        let token = try payload.encodeToToken()
        FileHandle.standardError.write(Data("Host fingerprint: \(identity.fingerprint)\n".utf8))
        FileHandle.standardError.write(Data("Pairing token: \(token)\n".utf8))
        writePairingQRCode(token: token, sessionId: sessionId)
    } catch {
        FileHandle.standardError.write(Data("Failed to create pairing payload: \(error)\n".utf8))
    }
}

func writePairingQRCode(token: String, sessionId: String) {
    #if canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    guard let image = QRCodeGenerator.cgImage(forToken: token, scale: 12) else {
        FileHandle.standardError.write(Data("Pairing QR could not be generated. Use the printed token instead.\n".utf8))
        return
    }

    let filename = "loupe-pairing-\(sessionId).png"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("Pairing QR could not be written. Use the printed token instead.\n".utf8))
        return
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("Pairing QR could not be finalized. Use the printed token instead.\n".utf8))
        return
    }

    FileHandle.standardError.write(Data("Pairing QR PNG: \(url.path)\n".utf8))
    #else
    FileHandle.standardError.write(Data("Pairing QR generation unavailable. Use the printed token instead.\n".utf8))
    #endif
}

let (sessionId, signalingURL) = parseArguments()
ensurePermissions()
printDisplayDiagnostics()

let identity = loadIdentityOrExit()
let hostId = "macos-host-\(identity.fingerprint)"
printPairingToken(sessionId: sessionId, signalingURL: signalingURL, identity: identity, hostId: hostId)

let signaling = SignalingClient(url: signalingURL)

// Use the real libwebrtc transport when the dependency is resolved; otherwise
// fall back to the null transport so the capture/encode pipeline can be brought
// up without WebRTC.
#if canImport(WebRTC)
let peer: PeerConnection = WebRTCPeerConnection(identity: identity)
FileHandle.standardError.write(Data("Transport: libwebrtc (DTLS-fingerprint binding enforced)\n".utf8))
#else
let peer: PeerConnection = NullPeerConnection()
FileHandle.standardError.write(Data("Transport: null (build with the WebRTC package for real P2P)\n".utf8))
#endif

let host = HostSession(
    sessionId: sessionId,
    peerId: hostId,
    signaling: signaling,
    peer: peer,
    displayBounds: mainDisplayBounds()
)

let semaphore = DispatchSemaphore(value: 0)

signalHandlers: do {
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler {
        FileHandle.standardError.write(Data("\nShutting down…\n".utf8))
        Task {
            await host.stop()
            semaphore.signal()
        }
    }
    source.resume()
    signal(SIGINT, SIG_IGN)
}

Task {
    do {
        FileHandle.standardError.write(Data("Starting Loupe host, session=\(sessionId), signaling=\(signalingURL.absoluteString)\n".utf8))
        try await host.start()
        FileHandle.standardError.write(Data("Host running. Press Ctrl-C to stop.\n".utf8))
    } catch {
        FileHandle.standardError.write(Data("Failed to start: \(error)\n".utf8))
        semaphore.signal()
    }
}

semaphore.wait()
