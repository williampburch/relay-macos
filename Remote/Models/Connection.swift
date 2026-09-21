import Foundation
import SwiftData

enum RDPGatewayTransport: String, Codable, CaseIterable, Identifiable, Sendable {
    case rpc
    case automatic
    case http
    case httpWithoutWebSockets

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rpc: "RPC (classic RD Gateway)"
        case .automatic: "Automatic"
        case .http: "HTTP"
        case .httpWithoutWebSockets: "HTTP without WebSockets"
        }
    }

    var freeRDPValue: String {
        switch self {
        case .rpc: "rpc"
        case .automatic: "auto"
        case .http: "http"
        case .httpWithoutWebSockets: "http,no-websockets"
        }
    }
}

struct ConnectionSettings: Codable, Equatable, Sendable {
    var keepAliveInterval: Int?
    var proxyJump: String?
    var opensInFullScreen: Bool
    var desktopWidth: Int?
    var desktopHeight: Int?
    var rdpGatewayTransport: RDPGatewayTransport?

    init(
        keepAliveInterval: Int? = nil,
        proxyJump: String? = nil,
        opensInFullScreen: Bool = false,
        desktopWidth: Int? = nil,
        desktopHeight: Int? = nil,
        rdpGatewayTransport: RDPGatewayTransport? = nil
    ) {
        self.keepAliveInterval = keepAliveInterval
        self.proxyJump = proxyJump
        self.opensInFullScreen = opensInFullScreen
        self.desktopWidth = desktopWidth
        self.desktopHeight = desktopHeight
        self.rdpGatewayTransport = rdpGatewayTransport
    }

    var effectiveRDPGatewayTransport: RDPGatewayTransport {
        rdpGatewayTransport ?? .rpc
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
    var rdpGatewayHost: String?
    var rdpGatewayPort: Int?
    var rdpGatewayCredentialProfile: CredentialProfile?
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
        rdpGatewayHost: String? = nil,
        rdpGatewayPort: Int? = nil,
        rdpGatewayCredentialProfile: CredentialProfile? = nil,
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
        self.rdpGatewayHost = rdpGatewayHost
        self.rdpGatewayPort = rdpGatewayPort
        self.rdpGatewayCredentialProfile = rdpGatewayCredentialProfile
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
        rdpGatewayHost: String? = nil,
        rdpGatewayPort: Int? = nil,
        rdpGatewayCredentialProfile: CredentialProfile? = nil,
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
            rdpGatewayHost: rdpGatewayHost,
            rdpGatewayPort: rdpGatewayPort,
            rdpGatewayCredentialProfile: rdpGatewayCredentialProfile,
            notes: notes,
            settings: settings,
            sortOrder: sortOrder,
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func resolvedCredentialProfile() -> CredentialProfile? {
        if let credentialProfile,
           credentialProfile.isCompatible(with: connectionProtocol) {
            return credentialProfile
        }
        return group?.resolvedCredentialProfile(for: connectionProtocol)
    }

    func resolvedUsername() -> String? {
        if let value = nonEmpty(usernameOverride) {
            return value
        }
        if credentialProfile?.isCompatible(with: connectionProtocol) == true,
           let value = nonEmpty(credentialProfile?.username) {
            return value
        }
        return group?.resolvedUsername(for: connectionProtocol)
    }

    func resolvedDomain() -> String? {
        if let value = nonEmpty(domainOverride) {
            return value
        }
        if credentialProfile?.isCompatible(with: connectionProtocol) == true,
           let value = nonEmpty(credentialProfile?.domain) {
            return value
        }
        return group?.resolvedDomain(for: connectionProtocol)
    }

    var usesRDPGateway: Bool {
        connectionProtocol == .rdp && nonEmpty(rdpGatewayHost) != nil
    }

    /// A gateway can use its own reusable profile or fall back to the
    /// connection's resolved profile. Authentication material remains in Keychain.
    func resolvedRDPGatewayCredentialProfile() -> CredentialProfile? {
        if let rdpGatewayCredentialProfile,
           rdpGatewayCredentialProfile.isCompatible(with: .rdp) {
            return rdpGatewayCredentialProfile
        }
        return resolvedCredentialProfile()
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
