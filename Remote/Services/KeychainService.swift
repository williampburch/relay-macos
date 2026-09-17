import Foundation
import Security

enum KeychainServiceError: LocalizedError, Equatable {
    case invalidSecretEncoding
    case unexpectedData
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSecretEncoding:
            return "The password could not be encoded for secure storage."
        case .unexpectedData:
            return "The stored Keychain item is not valid password data."
        case .operationFailed(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return message.map { "Keychain operation failed: \($0)" }
                ?? "Keychain operation failed with status \(status)."
        }
    }
}

/// Stores authentication material in macOS Keychain. Callers persist only the
/// opaque reference returned by this service.
final class KeychainService {
    static let shared = KeychainService()
    static let defaultServiceIdentifier = "com.example.Remote.credentials.v1"

    private let serviceIdentifier: String

    init(serviceIdentifier: String = KeychainService.defaultServiceIdentifier) {
        self.serviceIdentifier = serviceIdentifier
    }

    /// Creates or replaces a generic-password item and returns its opaque
    /// reference. Password values are intentionally never logged or described.
    @discardableResult
    func savePassword(_ password: String, reference: String? = nil) throws -> String {
        guard let data = password.data(using: .utf8) else {
            throw KeychainServiceError.invalidSecretEncoding
        }

        let resolvedReference = reference ?? UUID().uuidString
        let lookup = baseQuery(reference: resolvedReference)
        let updateStatus = SecItemUpdate(
            lookup as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return resolvedReference
        case errSecItemNotFound:
            var item = lookup
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrLabel as String] = "Remote credential"

            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainServiceError.operationFailed(addStatus)
            }
            return resolvedReference
        default:
            throw KeychainServiceError.operationFailed(updateStatus)
        }
    }

    /// Returns nil when the reference has no corresponding Keychain item.
    func password(reference: String) throws -> String? {
        var query = baseQuery(reference: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let password = String(data: data, encoding: .utf8)
            else {
                throw KeychainServiceError.unexpectedData
            }
            return password
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainServiceError.operationFailed(status)
        }
    }

    /// Deleting a missing item succeeds so model and Keychain cleanup can be
    /// safely retried.
    func deletePassword(reference: String) throws {
        let status = SecItemDelete(baseQuery(reference: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.operationFailed(status)
        }
    }

    private func baseQuery(reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: reference,
            kSecAttrSynchronizable as String: false
        ]
    }
}
