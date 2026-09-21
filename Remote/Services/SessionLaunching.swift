import Foundation

enum SessionLaunchError: LocalizedError, Equatable {
    case notImplemented(protocolName: String)

    var errorDescription: String? {
        switch self {
        case .notImplemented(let protocolName):
            return "\(protocolName) launching is planned for a later milestone."
        }
    }
}

/// The boundary between the app's session UI and a concrete protocol integration.
/// External launchers and future embedded sessions can be exchanged without changing
/// connection storage or tab management.
@MainActor
protocol SessionLaunching {
    func connect(to connection: Connection, credential: CredentialProfile?) async throws
    func disconnect(connectionID: UUID) async
}

/// One place for tab, editor, and deletion flows to tear down protocol
/// sessions. Calling both services is intentional and makes cleanup safe even
/// when a connection's protocol was edited while it was open.
@MainActor
enum SessionCoordinator {
    static func isActive(connectionID: UUID) -> Bool {
        SSHSessionService.shared.activeConnectionIDs.contains(connectionID)
            || RDPService.shared.activeConnectionIDs.contains(connectionID)
    }

    static func disconnect(connectionID: UUID) {
        SSHSessionService.shared.disconnect(connectionID: connectionID)
        RDPService.shared.disconnectNow(connectionID: connectionID)
    }
}
