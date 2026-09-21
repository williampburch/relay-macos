import Foundation
import SwiftData

@Model
final class CredentialProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var username: String
    var domain: String?
    private var authenticationTypeRawValue: String

    /// Optional for lightweight migration of profiles created before profiles
    /// were separated by protocol. Legacy key and agent profiles resolve to
    /// SSH; legacy password and prompt profiles resolve to RDP.
    private var connectionProtocolRawValue: String?

    /// An opaque identifier used by KeychainService to locate authentication
    /// material. This value is not authentication material itself.
    var keychainReference: String?

    /// A filesystem location is configuration, not secret key contents. The
    /// model never reads or persists the key itself.
    var sshKeyPath: String?
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var authenticationType: AuthenticationType {
        get { AuthenticationType(rawValue: authenticationTypeRawValue) ?? .promptEveryTime }
        set {
            authenticationTypeRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var connectionProtocol: ConnectionProtocol {
        get {
            if let connectionProtocolRawValue,
               let value = ConnectionProtocol(rawValue: connectionProtocolRawValue) {
                return value
            }
            switch authenticationType {
            case .sshKey, .sshAgent:
                return .ssh
            case .password, .promptEveryTime:
                return .rdp
            }
        }
        set {
            connectionProtocolRawValue = newValue.rawValue
            if !AuthenticationType.availableMethods(for: newValue).contains(authenticationType) {
                authenticationTypeRawValue = AuthenticationType.availableMethods(for: newValue)[0].rawValue
            }
            updatedAt = Date()
        }
    }

    /// Profiles created before protocol-specific credentials can be assigned
    /// once in the editor. Newly created and migrated profiles stay fixed so
    /// connections cannot silently switch authentication semantics.
    var hasExplicitConnectionProtocol: Bool {
        connectionProtocolRawValue != nil
    }

    func isCompatible(with connectionProtocol: ConnectionProtocol) -> Bool {
        self.connectionProtocol == connectionProtocol
            && AuthenticationType.availableMethods(for: connectionProtocol).contains(authenticationType)
    }

    init(
        id: UUID = UUID(),
        name: String,
        username: String = "",
        domain: String? = nil,
        connectionProtocol: ConnectionProtocol? = nil,
        authenticationType: AuthenticationType = .promptEveryTime,
        keychainReference: String? = nil,
        sshKeyPath: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.username = username
        self.domain = domain
        self.authenticationTypeRawValue = authenticationType.rawValue
        self.connectionProtocolRawValue = connectionProtocol?.rawValue
        self.keychainReference = keychainReference
        self.sshKeyPath = sshKeyPath
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
