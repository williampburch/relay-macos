import AppKit
import Foundation

enum SSHLaunchError: LocalizedError, Equatable {
    case missingHost
    case missingKeyPath
    case terminalUnavailable
    case unableToCreateLauncher

    var errorDescription: String? {
        switch self {
        case .missingHost:
            return "Enter a host before starting the SSH connection."
        case .missingKeyPath:
            return "The selected SSH key profile does not have a private key path."
        case .terminalUnavailable:
            return "Terminal could not be found on this Mac."
        case .unableToCreateLauncher:
            return "Remote could not create the temporary SSH launcher."
        }
    }
}

struct SSHLaunchPlan: Equatable {
    let arguments: [String]
    let promptsForPassword: Bool
}

enum SSHCommandBuilder {
    static func makePlan(
        connection: Connection,
        credential: CredentialProfile?
    ) throws -> SSHLaunchPlan {
        let host = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw SSHLaunchError.missingHost }

        var arguments = ["-p", String(connection.port)]

        if let username = nonEmpty(connection.resolvedUsername()) {
            arguments.append(contentsOf: ["-l", username])
        }

        let settings = connection.settings
        if let interval = settings.keepAliveInterval, interval > 0 {
            arguments.append(contentsOf: ["-o", "ServerAliveInterval=\(interval)"])
        }
        if let proxyJump = nonEmpty(settings.proxyJump) {
            arguments.append(contentsOf: ["-J", proxyJump])
        }

        var promptsForPassword = false
        switch credential?.authenticationType {
        case .sshKey:
            guard let path = nonEmpty(credential?.sshKeyPath) else {
                throw SSHLaunchError.missingKeyPath
            }
            let expandedPath = NSString(string: path).expandingTildeInPath
            arguments.append(contentsOf: [
                "-o", "IdentitiesOnly=yes",
                "-i", expandedPath
            ])
        case .password, .promptEveryTime:
            // OpenSSH owns the interactive prompt in Terminal. Authentication
            // material is never placed in arguments, environment, or a script.
            arguments.append(contentsOf: [
                "-o", "PubkeyAuthentication=no",
                "-o", "PreferredAuthentications=keyboard-interactive,password"
            ])
            promptsForPassword = true
        case .sshAgent, nil:
            break
        }

        // Stop option parsing before the user-supplied destination.
        arguments.append("--")
        arguments.append(host)
        return SSHLaunchPlan(arguments: arguments, promptsForPassword: promptsForPassword)
    }

    static func launcherScript(arguments: [String]) -> String {
        let escapedArguments = arguments.map(shellQuote).joined(separator: " ")
        return """
        #!/bin/zsh
        /bin/rm -f -- "$0"
        exec /usr/bin/ssh \(escapedArguments)
        """
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
protocol TerminalLaunching {
    func launchSSH(arguments: [String]) async throws
}

@MainActor
final class TerminalLauncher: TerminalLaunching {
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(
        fileManager: FileManager = .default,
        workspace: NSWorkspace = .shared
    ) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func launchSSH(arguments: [String]) async throws {
        guard let terminalURL = workspace.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else {
            throw SSHLaunchError.terminalUnavailable
        }

        let launcherURL = try makeLauncher(arguments: arguments)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                workspace.open(
                    [launcherURL],
                    withApplicationAt: terminalURL,
                    configuration: configuration
                ) { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            try? fileManager.removeItem(at: launcherURL)
            throw error
        }
    }

    private func makeLauncher(arguments: [String]) throws -> URL {
        guard let cachesDirectory = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw SSHLaunchError.unableToCreateLauncher
        }

        let directory = cachesDirectory
            .appendingPathComponent("com.example.Remote", isDirectory: true)
            .appendingPathComponent("SSHLaunchers", isDirectory: true)
        let launcherURL = directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("command")

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            try SSHCommandBuilder.launcherScript(arguments: arguments)
                .write(to: launcherURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: launcherURL.path
            )
            return launcherURL
        } catch {
            try? fileManager.removeItem(at: launcherURL)
            throw SSHLaunchError.unableToCreateLauncher
        }
    }
}

@MainActor
protocol SSHServicing: SessionLaunching {}

@MainActor
final class SSHService: SSHServicing {
    static let shared = SSHService()

    private let terminalLauncher: TerminalLaunching

    init(terminalLauncher: TerminalLaunching? = nil) {
        self.terminalLauncher = terminalLauncher ?? TerminalLauncher()
    }

    func connect(to connection: Connection, credential: CredentialProfile?) async throws {
        let plan = try SSHCommandBuilder.makePlan(
            connection: connection,
            credential: credential
        )
        try await terminalLauncher.launchSSH(arguments: plan.arguments)
    }

    /// External Terminal sessions own their lifecycle after launch.
    func disconnect(connectionID: UUID) async {}
}
