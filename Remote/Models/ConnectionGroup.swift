import Foundation
import SwiftData

@Model
final class ConnectionGroup {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    var username: String?
    var domain: String?
    var credentialProfile: CredentialProfile?
    var createdAt: Date
    var updatedAt: Date

    var defaultCredentialProfile: CredentialProfile? {
        get { credentialProfile }
        set { credentialProfile = newValue }
    }

    var defaultUsername: String? {
        get { username }
        set { username = newValue }
    }

    var defaultDomain: String? {
        get { domain }
        set { domain = newValue }
    }

    var parent: ConnectionGroup?

    @Relationship(deleteRule: .cascade, inverse: \ConnectionGroup.parent)
    var children: [ConnectionGroup]

    @Relationship(deleteRule: .cascade, inverse: \Connection.group)
    var connections: [Connection]

    init(
        id: UUID = UUID(),
        name: String,
        sortOrder: Int = 0,
        parent: ConnectionGroup? = nil,
        credentialProfile: CredentialProfile? = nil,
        username: String? = nil,
        domain: String? = nil,
        children: [ConnectionGroup] = [],
        connections: [Connection] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.parent = parent
        self.credentialProfile = credentialProfile
        self.username = username
        self.domain = domain
        self.children = children
        self.connections = connections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func resolvedCredentialProfile() -> CredentialProfile? {
        firstValueInAncestry(\.credentialProfile)
    }

    func resolvedCredentialProfile(
        for connectionProtocol: ConnectionProtocol
    ) -> CredentialProfile? {
        var group: ConnectionGroup? = self
        var visited = Set<UUID>()

        while let current = group, visited.insert(current.id).inserted {
            if let profile = current.credentialProfile,
               profile.isCompatible(with: connectionProtocol) {
                return profile
            }
            group = current.parent
        }
        return nil
    }

    func resolvedUsername() -> String? {
        firstStringInAncestry(explicit: \.username) { $0.username }
    }

    func resolvedUsername(for connectionProtocol: ConnectionProtocol) -> String? {
        firstStringInAncestry(
            explicit: \.username,
            acceptingProfile: { $0.isCompatible(with: connectionProtocol) },
            profileValue: { $0.username }
        )
    }

    func resolvedDomain() -> String? {
        firstStringInAncestry(explicit: \.domain) { $0.domain }
    }

    func resolvedDomain(for connectionProtocol: ConnectionProtocol) -> String? {
        firstStringInAncestry(
            explicit: \.domain,
            acceptingProfile: { $0.isCompatible(with: connectionProtocol) },
            profileValue: { $0.domain }
        )
    }

    /// Returns true when `candidate` is this group or one of its descendants.
    /// Editors can use this to prevent creating a cycle while moving a group.
    func containsInSubtree(_ candidate: ConnectionGroup) -> Bool {
        var pending = [self]
        var visited = Set<UUID>()

        while let group = pending.popLast() {
            guard visited.insert(group.id).inserted else { continue }
            if group.id == candidate.id { return true }
            pending.append(contentsOf: group.children)
        }

        return false
    }

    private func firstValueInAncestry<Value>(
        _ keyPath: KeyPath<ConnectionGroup, Value?>
    ) -> Value? {
        var group: ConnectionGroup? = self
        var visited = Set<UUID>()

        while let current = group, visited.insert(current.id).inserted {
            if let value = current[keyPath: keyPath] {
                return value
            }
            group = current.parent
        }

        return nil
    }

    private func firstStringInAncestry(
        explicit keyPath: KeyPath<ConnectionGroup, String?>,
        acceptingProfile: (CredentialProfile) -> Bool = { _ in true },
        profileValue: (CredentialProfile) -> String?
    ) -> String? {
        var group: ConnectionGroup? = self
        var visited = Set<UUID>()

        while let current = group, visited.insert(current.id).inserted {
            if let value = nonEmpty(current[keyPath: keyPath]) {
                return value
            }
            if let profile = current.credentialProfile,
               acceptingProfile(profile),
               let value = nonEmpty(profileValue(profile)) {
                return value
            }
            group = current.parent
        }

        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
