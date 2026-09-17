import Foundation
import SwiftData

@Model
final class CredentialProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var username: String
    var domain: String?
    private var authenticationTypeRawValue: String

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

    init(
        id: UUID = UUID(),
        name: String,
        username: String = "",
        domain: String? = nil,
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
        self.keychainReference = keychainReference
        self.sshKeyPath = sshKeyPath
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
