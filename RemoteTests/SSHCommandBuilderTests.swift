import XCTest
@testable import Remote

final class SSHCommandBuilderTests: XCTestCase {
    func testAgentPlanUsesResolvedUsernameAndConnectionOptions() throws {
        let credential = CredentialProfile(
            name: "Linux Admin",
            username: "deploy",
            authenticationType: .sshAgent
        )
        let connection = Connection(
            name: "APP01",
            host: "app01.example.test",
            connectionProtocol: .ssh,
            port: 2222,
            credentialProfile: credential,
            settings: ConnectionSettings(
                keepAliveInterval: 30,
                proxyJump: "bastion.example.test"
            )
        )

        let plan = try SSHCommandBuilder.makePlan(
            connection: connection,
            credential: credential
        )

        XCTAssertEqual(plan.arguments, [
            "-p", "2222",
            "-l", "deploy",
            "-o", "ServerAliveInterval=30",
            "-J", "bastion.example.test",
            "--", "app01.example.test"
        ])
        XCTAssertFalse(plan.promptsForPassword)
    }

    func testKeyPlanExpandsHomeDirectoryWithoutReadingTheKey() throws {
        let credential = CredentialProfile(
            name: "Key",
            authenticationType: .sshKey,
            sshKeyPath: "~/.ssh/id_ed25519"
        )
        let connection = Connection(
            name: "DB01",
            host: "db01.example.test",
            connectionProtocol: .ssh
        )

        let plan = try SSHCommandBuilder.makePlan(
            connection: connection,
            credential: credential
        )

        XCTAssertTrue(plan.arguments.contains("IdentitiesOnly=yes"))
        XCTAssertTrue(plan.arguments.contains("-i"))
        XCTAssertTrue(plan.arguments.contains(
            NSString(string: "~/.ssh/id_ed25519").expandingTildeInPath
        ))
        XCTAssertFalse(plan.promptsForPassword)
    }

    func testPasswordPlanForcesAnInteractiveOpenSSHPrompt() throws {
        let credential = CredentialProfile(
            name: "Prompted Login",
            username: "operator",
            authenticationType: .password,
            keychainReference: "opaque-reference"
        )
        let connection = Connection(
            name: "Host",
            host: "host.example.test",
            connectionProtocol: .ssh,
            credentialProfile: credential
        )

        let plan = try SSHCommandBuilder.makePlan(
            connection: connection,
            credential: credential
        )

        XCTAssertTrue(plan.promptsForPassword)
        XCTAssertTrue(plan.arguments.contains("PubkeyAuthentication=no"))
        XCTAssertTrue(plan.arguments.contains("PreferredAuthentications=keyboard-interactive,password"))
        XCTAssertFalse(plan.arguments.contains("opaque-reference"))
    }

    func testLauncherShellQuotesUntrustedValues() {
        let script = SSHCommandBuilder.launcherScript(arguments: [
            "--",
            "host; /usr/bin/touch /tmp/should-not-exist",
            "user's-host"
        ])

        XCTAssertTrue(script.contains("'host; /usr/bin/touch /tmp/should-not-exist'"))
        XCTAssertTrue(script.contains("'user'\"'\"'s-host'"))
        XCTAssertTrue(script.contains("exec /usr/bin/ssh"))
    }

    func testMissingKeyPathIsRejected() {
        let credential = CredentialProfile(
            name: "Broken Key",
            authenticationType: .sshKey
        )
        let connection = Connection(
            name: "Host",
            host: "host.example.test",
            connectionProtocol: .ssh
        )

        XCTAssertThrowsError(
            try SSHCommandBuilder.makePlan(
                connection: connection,
                credential: credential
            )
        ) { error in
            XCTAssertEqual(error as? SSHLaunchError, .missingKeyPath)
        }
    }
}
