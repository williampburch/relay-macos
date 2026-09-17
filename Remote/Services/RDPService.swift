import Foundation

@MainActor
protocol RDPServicing: SessionLaunching {}

@MainActor
final class RDPService: RDPServicing {
    func connect(to connection: Connection, credential: CredentialProfile?) async throws {
        throw SessionLaunchError.notImplemented(protocolName: "RDP")
    }

    func disconnect(connectionID: UUID) async {}
}
