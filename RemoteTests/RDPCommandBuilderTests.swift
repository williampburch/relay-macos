import XCTest
@testable import Remote

final class RDPCommandBuilderTests: XCTestCase {
    func testBasicPlanIncludesSafePrototypeFeaturesWithoutSecrets() throws {
        let credential = CredentialProfile(
            name: "Windows Admin",
            username: "administrator",
            domain: "CONTOSO",
            authenticationType: .password,
            keychainReference: "opaque-server-reference"
        )
        let connection = Connection(
            name: "DC01",
            host: "dc01.example.test",
            connectionProtocol: .rdp,
            credentialProfile: credential
        )

        let plan = try RDPCommandBuilder.makePlan(
            connection: connection,
            credential: credential,
            gatewayCredential: nil
        )

        XCTAssertTrue(plan.arguments.contains("/v:dc01.example.test:3389"))
        XCTAssertTrue(plan.arguments.contains("/u:administrator"))
        XCTAssertTrue(plan.arguments.contains("/d:CONTOSO"))
        XCTAssertTrue(plan.arguments.contains("/from-stdin:force"))
        XCTAssertTrue(plan.arguments.contains("/cert:tofu"))
        XCTAssertTrue(plan.arguments.contains("+clipboard"))
        XCTAssertTrue(plan.arguments.contains("+dynamic-resolution"))
        XCTAssertFalse(plan.arguments.contains { $0.contains("opaque-server-reference") })
        XCTAssertFalse(plan.needsGatewayPassword)
    }

    func testGatewayCanUseSeparateCredentialIdentity() throws {
        let serverCredential = CredentialProfile(
            name: "Server",
            username: "server-user",
            domain: "SERVER",
            authenticationType: .password
        )
        let gatewayCredential = CredentialProfile(
            name: "Gateway",
            username: "gateway-user",
            domain: "EDGE",
            authenticationType: .password,
            keychainReference: "opaque-gateway-reference"
        )
        let connection = Connection(
            name: "SQL01",
            host: "sql01.internal.example",
            connectionProtocol: .rdp,
            credentialProfile: serverCredential,
            rdpGatewayHost: "gateway.example.com",
            rdpGatewayPort: 443,
            rdpGatewayCredentialProfile: gatewayCredential
        )

        let plan = try RDPCommandBuilder.makePlan(
            connection: connection,
            credential: serverCredential,
            gatewayCredential: gatewayCredential
        )

        XCTAssertTrue(plan.arguments.contains(
            "/gateway:g:gateway.example.com:443,u:gateway-user,d:EDGE,usage-method:direct,type:auto"
        ))
        XCTAssertFalse(plan.arguments.contains { $0.contains("opaque-gateway-reference") })
        XCTAssertFalse(plan.arguments.contains { $0.contains(",p:") })
        XCTAssertTrue(plan.needsGatewayPassword)
    }

    func testGatewayFallbackUsesResolvedConnectionIdentity() throws {
        let credential = CredentialProfile(
            name: "Shared",
            username: "profile-user",
            domain: "PROFILE",
            authenticationType: .password
        )
        let connection = Connection(
            name: "Host",
            host: "host.internal.example",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            usernameOverride: "connection-user",
            domainOverride: "CONNECTION",
            rdpGatewayHost: "gateway.example.com"
        )

        let plan = try RDPCommandBuilder.makePlan(
            connection: connection,
            credential: credential,
            gatewayCredential: credential
        )

        XCTAssertTrue(plan.arguments.contains(
            "/gateway:g:gateway.example.com:443,u:connection-user,d:CONNECTION,usage-method:direct,type:auto"
        ))
    }

    func testDisplaySettingsChooseFullscreenOrCustomSize() throws {
        let credential = CredentialProfile(
            name: "Login",
            username: "operator",
            authenticationType: .promptEveryTime
        )
        let fullScreenConnection = Connection(
            name: "Full Screen",
            host: "full.example.test",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            settings: ConnectionSettings(opensInFullScreen: true)
        )
        let sizedConnection = Connection(
            name: "Sized",
            host: "sized.example.test",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            settings: ConnectionSettings(desktopWidth: 1600, desktopHeight: 1000)
        )

        let fullScreenPlan = try RDPCommandBuilder.makePlan(
            connection: fullScreenConnection,
            credential: credential,
            gatewayCredential: nil
        )
        let sizedPlan = try RDPCommandBuilder.makePlan(
            connection: sizedConnection,
            credential: credential,
            gatewayCredential: nil
        )

        XCTAssertTrue(fullScreenPlan.arguments.contains("+f"))
        XCTAssertTrue(sizedPlan.arguments.contains("/size:1600x1000"))
    }

    func testGatewayCompositeDelimitersAreRejected() {
        let credential = CredentialProfile(
            name: "Login",
            username: "operator",
            authenticationType: .password
        )
        let connection = Connection(
            name: "Host",
            host: "host.example.test",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            rdpGatewayHost: "gateway.example.com,type:rpc"
        )

        XCTAssertThrowsError(
            try RDPCommandBuilder.makePlan(
                connection: connection,
                credential: credential,
                gatewayCredential: credential
            )
        ) { error in
            XCTAssertEqual(error as? RDPLaunchError, .invalidGatewayValue)
        }
    }
}
