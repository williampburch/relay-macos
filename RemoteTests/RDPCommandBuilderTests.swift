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
        XCTAssertFalse(plan.arguments.contains("/from-stdin:force"))
        XCTAssertEqual(RDPArgumentStreamBuilder.processArguments, ["/args-from:stdin"])
        XCTAssertTrue(plan.arguments.contains("/log-level:WARN"))
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
            "/gateway:g:gateway.example.com:443,u:gateway-user,d:EDGE,usage-method:direct,type:rpc"
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
            "/gateway:g:gateway.example.com:443,u:connection-user,d:CONNECTION,usage-method:direct,type:rpc"
        ))
    }

    func testGatewayTransportCanDisableWebSockets() throws {
        let credential = CredentialProfile(
            name: "Gateway",
            username: "operator",
            authenticationType: .password
        )
        let connection = Connection(
            name: "Desktop",
            host: "desktop.example.test",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            rdpGatewayHost: "gateway.example.test",
            settings: ConnectionSettings(
                rdpGatewayTransport: .httpWithoutWebSockets
            )
        )

        let plan = try RDPCommandBuilder.makePlan(
            connection: connection,
            credential: credential,
            gatewayCredential: credential
        )

        XCTAssertTrue(plan.arguments.contains(
            "/gateway:g:gateway.example.test:443,u:operator,usage-method:direct,type:http,no-websockets"
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

    func testDiagnosticSanitizerRedactsConnectionIdentityAndSecrets() {
        let diagnostic = """
        [ERROR] gateway.example.test failed for CONTOSO\\operator
        [WARN] authorization=BearerValue token:TopSecret password=hunter2
        """

        let result = RDPDiagnosticSanitizer.sanitize(
            diagnostic,
            redacting: ["gateway.example.test", "CONTOSO", "operator"]
        )

        XCTAssertFalse(result.contains("gateway.example.test"))
        XCTAssertFalse(result.contains("CONTOSO"))
        XCTAssertFalse(result.contains("operator"))
        XCTAssertFalse(result.contains("BearerValue"))
        XCTAssertFalse(result.contains("TopSecret"))
        XCTAssertFalse(result.contains("hunter2"))
        XCTAssertTrue(result.contains("[redacted]"))
    }

    func testArgumentStreamKeepsSecretsOutOfProcessArguments() throws {
        let credential = CredentialProfile(
            name: "Shared",
            username: "operator",
            domain: "CONTOSO",
            authenticationType: .password
        )
        let connection = Connection(
            name: "Desktop",
            host: "desktop.example.test",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            rdpGatewayHost: "gateway.example.test"
        )
        let plan = try RDPCommandBuilder.makePlan(
            connection: connection,
            credential: credential,
            gatewayCredential: credential
        )

        let input = try RDPArgumentStreamBuilder.makeInput(
            plan: plan,
            serverPassword: "server-secret",
            gatewayPassword: "gateway-secret"
        )
        let inputText = try XCTUnwrap(String(data: input, encoding: .utf8))

        XCTAssertEqual(RDPArgumentStreamBuilder.processArguments, ["/args-from:stdin"])
        XCTAssertTrue(inputText.contains("/p:server-secret"))
        XCTAssertTrue(inputText.contains(",p:gateway-secret"))
        XCTAssertFalse(RDPArgumentStreamBuilder.processArguments.contains {
            $0.contains("secret") || $0.contains("desktop.example.test")
        })
    }

    func testArgumentStreamRejectsUnsafeLineAndGatewayDelimiters() throws {
        let credential = CredentialProfile(
            name: "Login",
            username: "operator",
            authenticationType: .password
        )
        let connection = Connection(
            name: "Desktop",
            host: "desktop.example.test",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            rdpGatewayHost: "gateway.example.test"
        )
        let plan = try RDPCommandBuilder.makePlan(
            connection: connection,
            credential: credential,
            gatewayCredential: credential
        )

        XCTAssertThrowsError(try RDPArgumentStreamBuilder.makeInput(
            plan: plan,
            serverPassword: "line\nbreak",
            gatewayPassword: "safe"
        ))
        XCTAssertThrowsError(try RDPArgumentStreamBuilder.makeInput(
            plan: plan,
            serverPassword: "safe",
            gatewayPassword: "comma,break"
        ))
    }

    func testRAPAccessDeniedGetsActionableExplanation() {
        let message = RDPFailureInterpreter.message(
            exitStatus: 133,
            details: "RPC Fault PDU: status=E_PROXY_RAP_ACCESSDENIED"
        )

        XCTAssertTrue(message.contains("Resource Authorization Policy"))
        XCTAssertTrue(message.contains("internal computer name or FQDN"))
        XCTAssertFalse(message.contains("exit code 133"))
    }
}
