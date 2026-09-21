import Foundation

enum ConnectionProtocol: String, Codable, CaseIterable, Identifiable, Sendable {
    case ssh
    case rdp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ssh:
            return "SSH"
        case .rdp:
            return "RDP"
        }
    }

    var defaultPort: Int {
        switch self {
        case .ssh:
            return 22
        case .rdp:
            return 3389
        }
    }
}

enum AuthenticationType: String, Codable, CaseIterable, Identifiable, Sendable {
    case password
    case sshKey
    case sshAgent
    case promptEveryTime

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password:
            return "Password"
        case .sshKey:
            return "SSH Key"
        case .sshAgent:
            return "SSH Agent"
        case .promptEveryTime:
            return "Prompt Every Time"
        }
    }

    static func availableMethods(for connectionProtocol: ConnectionProtocol) -> [AuthenticationType] {
        switch connectionProtocol {
        case .ssh:
            return [.promptEveryTime, .sshKey, .sshAgent]
        case .rdp:
            return [.password, .promptEveryTime]
        }
    }

    func displayName(for connectionProtocol: ConnectionProtocol) -> String {
        switch (connectionProtocol, self) {
        case (.ssh, .promptEveryTime):
            return "Password or interactive prompt"
        case (.ssh, .sshKey):
            return "Private key"
        case (.ssh, .sshAgent):
            return "SSH agent or OpenSSH config"
        case (.rdp, .password):
            return "Stored password"
        default:
            return displayName
        }
    }

    func isSupported(by connectionProtocol: ConnectionProtocol) -> Bool {
        Self.availableMethods(for: connectionProtocol).contains(self)
    }
}
