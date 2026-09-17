import XCTest
@testable import Remote

final class CredentialInheritanceTests: XCTestCase {
    func testConnectionInheritsCredentialAndIdentityFromNearestGroup() {
        let productionCredential = CredentialProfile(
            name: "Production Administrator",
            username: "prod-admin",
            domain: "EXAMPLE",
            authenticationType: .password,
            keychainReference: "credential.production"
        )
        let root = ConnectionGroup(
            name: "Production",
            credentialProfile: productionCredential,
            username: "root-default",
            domain: "ROOT"
        )
        let windows = ConnectionGroup(
            name: "Windows",
            parent: root,
            username: "windows-admin"
        )
        let connection = Connection(
            name: "DC01",
            host: "dc01.example.test",
            connectionProtocol: .rdp,
            group: windows
        )

        XCTAssertTrue(connection.resolvedCredentialProfile() === productionCredential)
        XCTAssertEqual(connection.resolvedUsername(), "windows-admin")
        XCTAssertEqual(connection.resolvedDomain(), "ROOT")
    }

    func testConnectionOverridesInheritedValues() {
        let groupCredential = CredentialProfile(
            name: "Shared",
            username: "shared-user",
            authenticationType: .password,
            keychainReference: "credential.shared"
        )
        let connectionCredential = CredentialProfile(
            name: "Emergency",
            username: "emergency-user",
            domain: "LOCAL",
            authenticationType: .promptEveryTime
        )
        let group = ConnectionGroup(
            name: "Servers",
            credentialProfile: groupCredential,
            username: "group-user",
            domain: "GROUP"
        )
        let connection = Connection(
            name: "APP01",
            host: "app01.example.test",
            connectionProtocol: .ssh,
            group: group,
            credentialProfile: connectionCredential,
            usernameOverride: "one-off-user",
            domainOverride: "OVERRIDE"
        )

        XCTAssertTrue(connection.resolvedCredentialProfile() === connectionCredential)
        XCTAssertEqual(connection.resolvedUsername(), "one-off-user")
        XCTAssertEqual(connection.resolvedDomain(), "OVERRIDE")
    }

    func testGroupResolutionStopsWhenParentGraphContainsCycle() {
        let first = ConnectionGroup(name: "First", username: "first-user")
        let second = ConnectionGroup(name: "Second", parent: first)
        first.parent = second

        XCTAssertEqual(second.resolvedUsername(), "first-user")
        XCTAssertNil(second.resolvedCredentialProfile())
        XCTAssertNil(second.resolvedDomain())
    }

    func testRDPGatewayCanUseSeparateCredentialProfile() {
        let serverCredential = CredentialProfile(
            name: "Server Login",
            username: "server-user",
            authenticationType: .password
        )
        let gatewayCredential = CredentialProfile(
            name: "Gateway Login",
            username: "gateway-user",
            domain: "EDGE",
            authenticationType: .password
        )
        let connection = Connection(
            name: "DC01",
            host: "dc01.internal.example",
            connectionProtocol: .rdp,
            credentialProfile: serverCredential,
            rdpGatewayHost: "gateway.example.com",
            rdpGatewayPort: 443,
            rdpGatewayCredentialProfile: gatewayCredential
        )

        XCTAssertTrue(connection.usesRDPGateway)
        XCTAssertEqual(connection.rdpGatewayHost, "gateway.example.com")
        XCTAssertTrue(connection.resolvedRDPGatewayCredentialProfile() === gatewayCredential)
    }

    func testRDPGatewayFallsBackToConnectionCredential() {
        let credential = CredentialProfile(
            name: "Shared Login",
            username: "shared-user",
            authenticationType: .password
        )
        let connection = Connection(
            name: "SQL01",
            host: "sql01.internal.example",
            connectionProtocol: .rdp,
            credentialProfile: credential,
            rdpGatewayHost: "gateway.example.com"
        )

        XCTAssertTrue(connection.resolvedRDPGatewayCredentialProfile() === credential)
    }
}
