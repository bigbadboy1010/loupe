import Foundation
import Security

/// Keychain-backed storage for the long-lived device private key.
/// Uses a generic-password item scoped by service/account and stores the raw
/// Curve25519 private key representation as non-synchronizing device-local data.
public final class KeychainKeyStorage: KeyStorage, @unchecked Sendable {

    private let service: String
    private let account: String
    private let accessGroup: String?

    public init(
        service: String = "com.miggu69.loupe.device-identity",
        account: String = "default",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func loadPrivateKey() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainKeyStorageError.securityStatus(status) }
        guard let data = result as? Data else { throw KeychainKeyStorageError.unexpectedPayload }
        return data
    }

    public func savePrivateKey(_ raw: Data) throws {
        var item = baseQuery()
        item[kSecValueData as String] = raw
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecSuccess { return }
        if addStatus != errSecDuplicateItem { throw KeychainKeyStorageError.securityStatus(addStatus) }

        let attributes: [String: Any] = [kSecValueData as String: raw]
        let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess else { throw KeychainKeyStorageError.securityStatus(updateStatus) }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

public enum KeychainKeyStorageError: Error, Sendable, Equatable {
    case securityStatus(OSStatus)
    case unexpectedPayload
}
