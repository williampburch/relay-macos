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

    func isSupported(by connectionProtocol: ConnectionProtocol) -> Bool {
        switch connectionProtocol {
        case .ssh:
            return true
        case .rdp:
            return self == .password || self == .promptEveryTime
        }
    }
}
