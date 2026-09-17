import Foundation

@MainActor
protocol SSHServicing: SessionLaunching {}

@MainActor
final class SSHService: SSHServicing {
    func connect(to connection: Connection, credential: CredentialProfile?) async throws {
        throw SessionLaunchError.notImplemented(protocolName: "SSH")
    }

    func disconnect(connectionID: UUID) async {}
}
