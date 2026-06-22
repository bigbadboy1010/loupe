import Foundation
import CryptoKit

/// Human-comparable fingerprints over device public keys (ADR-003).
public enum Fingerprint {

    /// `SHA-256(publicKey)` rendered as grouped uppercase hex, e.g. `A1B2-C3D4-E5F6-…`.
    /// Truncated to `groups` groups of 4 hex chars for readable out-of-band comparison.
    public static func of(_ publicKey: Data, groups: Int = 6) -> String {
        let digest = SHA256.hash(data: publicKey)
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        let wanted = min(groups * 4, hex.count)
        let truncated = String(hex.prefix(wanted))
        return stride(from: 0, to: truncated.count, by: 4).map { offset -> String in
            let start = truncated.index(truncated.startIndex, offsetBy: offset)
            let end = truncated.index(start, offsetBy: min(4, truncated.count - offset))
            return String(truncated[start..<end])
        }.joined(separator: "-")
    }

    /// Fingerprint of a base64url-encoded public key, or nil if the input is malformed.
    public static func ofBase64URL(_ publicKeyBase64URL: String, groups: Int = 6) -> String? {
        guard let data = Data(base64URLEncoded: publicKeyBase64URL) else { return nil }
        return of(data, groups: groups)
    }
}
