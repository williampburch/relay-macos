import Foundation
import SwiftData

struct ConnectionSettings: Codable, Equatable, Sendable {
    var keepAliveInterval: Int?
    var proxyJump: String?
    var opensInFullScreen: Bool
    var desktopWidth: Int?
    var desktopHeight: Int?

    init(
        keepAliveInterval: Int? = nil,
        proxyJump: String? = nil,
        opensInFullScreen: Bool = false,
        desktopWidth: Int? = nil,
        desktopHeight: Int? = nil
    ) {
        self.keepAliveInterval = keepAliveInterval
        self.proxyJump = proxyJump
        self.opensInFullScreen = opensInFullScreen
        self.desktopWidth = desktopWidth
        self.desktopHeight = desktopHeight
    }
}

@Model
final class Connection {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    private var connectionProtocolRawValue: String
    var port: Int
    var group: ConnectionGroup?
    var credentialProfile: CredentialProfile?
    var usernameOverride: String?
    var domainOverride: String?
    var notes: String?
    private var settingsData: Data
    var sortOrder: Int
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date

    var displayName: String {
        get { name }
        set { name = newValue }
    }

    var protocolType: ConnectionProtocol {
        get { connectionProtocol }
        set { connectionProtocol = newValue }
    }

    var connectionProtocol: ConnectionProtocol {
        get { ConnectionProtocol(rawValue: connectionProtocolRawValue) ?? .ssh }
        set {
            let previousDefaultPort = connectionProtocol.defaultPort
            connectionProtocolRawValue = newValue.rawValue
            if port == previousDefaultPort {
                port = newValue.defaultPort
            }
            updatedAt = Date()
        }
    }

    var settings: ConnectionSettings {
        get {
            (try? JSONDecoder().decode(ConnectionSettings.self, from: settingsData))
                ?? ConnectionSettings()
        }
        set {
            settingsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            updatedAt = Date()
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        connectionProtocol: ConnectionProtocol,
        port: Int? = nil,
        group: ConnectionGroup? = nil,
        credentialProfile: CredentialProfile? = nil,
        usernameOverride: String? = nil,
        domainOverride: String? = nil,
        notes: String? = nil,
        settings: ConnectionSettings = ConnectionSettings(),
        sortOrder: Int = 0,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.connectionProtocolRawValue = connectionProtocol.rawValue
        self.port = port ?? connectionProtocol.defaultPort
        self.group = group
        self.credentialProfile = credentialProfile
        self.usernameOverride = usernameOverride
        self.domainOverride = domainOverride
        self.notes = notes
        self.settingsData = (try? JSONEncoder().encode(settings)) ?? Data()
        self.sortOrder = sortOrder
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    convenience init(
        id: UUID = UUID(),
        displayName: String,
        host: String,
        protocolType: ConnectionProtocol,
        port: Int? = nil,
        group: ConnectionGroup? = nil,
        credentialProfile: CredentialProfile? = nil,
        usernameOverride: String? = nil,
        domainOverride: String? = nil,
        notes: String? = nil,
        settings: ConnectionSettings = ConnectionSettings(),
        sortOrder: Int = 0,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.init(
            id: id,
            name: displayName,
            host: host,
            connectionProtocol: protocolType,
            port: port,
            group: group,
            credentialProfile: credentialProfile,
            usernameOverride: usernameOverride,
            domainOverride: domainOverride,
            notes: notes,
            settings: settings,
            sortOrder: sortOrder,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func resolvedCredentialProfile() -> CredentialProfile? {
        credentialProfile ?? group?.resolvedCredentialProfile()
    }

    func resolvedUsername() -> String? {
        if let value = nonEmpty(usernameOverride) {
            return value
        }
        if let value = nonEmpty(credentialProfile?.username) {
            return value
        }
        return group?.resolvedUsername()
    }

    func resolvedDomain() -> String? {
        if let value = nonEmpty(domainOverride) {
            return value
        }
        if let value = nonEmpty(credentialProfile?.domain) {
            return value
        }
        return group?.resolvedDomain()
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
