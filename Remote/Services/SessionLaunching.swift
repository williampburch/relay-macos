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
