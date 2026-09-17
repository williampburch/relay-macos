import AppKit
import Foundation

enum RDPLaunchError: LocalizedError, Equatable {
    case freeRDPNotInstalled
    case missingHost
    case invalidPort
    case missingUsername
    case missingStoredPassword(profileName: String)
    case unsupportedAuthentication(profileName: String)
    case invalidGatewayValue
    case passwordPromptCancelled
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .freeRDPNotInstalled:
            return "FreeRDP was not found. Install it with Homebrew using: brew install freerdp"
        case .missingHost:
            return "Enter a host before starting the RDP connection."
        case .invalidPort:
            return "The RDP port must be between 1 and 65535."
        case .missingUsername:
            return "The RDP connection needs a username or a credential profile with a username."
        case .missingStoredPassword(let profileName):
            return "The credential profile “\(profileName)” does not have a stored Keychain password."
        case .unsupportedAuthentication(let profileName):
            return "The credential profile “\(profileName)” uses an authentication method that RDP does not support."
        case .invalidGatewayValue:
            return "RD Gateway host, username, and domain values cannot contain commas or line breaks."
        case .passwordPromptCancelled:
            return "The password prompt was cancelled."
        case .launchFailed(let message):
            return "FreeRDP could not be launched: \(message)"
        }
    }
}

struct RDPLaunchPlan: Equatable {
    let arguments: [String]
    let needsGatewayPassword: Bool
}

enum RDPCommandBuilder {
    static func makePlan(
        connection: Connection,
        credential: CredentialProfile?,
        gatewayCredential: CredentialProfile?
    ) throws -> RDPLaunchPlan {
        let host = try requiredValue(connection.host, error: .missingHost)
        guard (1...65_535).contains(connection.port) else {
            throw RDPLaunchError.invalidPort
        }
        guard let username = nonEmpty(connection.resolvedUsername()) else {
            throw RDPLaunchError.missingUsername
        }

        if let credential, !credential.authenticationType.isSupported(by: .rdp) {
            throw RDPLaunchError.unsupportedAuthentication(profileName: credential.name)
        }

        var arguments = [
            "/v:\(endpoint(host: host, port: connection.port))",
            "/u:\(username)",
            "/from-stdin:force",
            "/cert:tofu",
            "+clipboard",
            "+dynamic-resolution",
            "/network:auto"
        ]

        if let domain = nonEmpty(connection.resolvedDomain()) {
            arguments.append("/d:\(domain)")
        }

        let settings = connection.settings
        if settings.opensInFullScreen {
            arguments.append("+f")
        } else if let width = settings.desktopWidth,
                  let height = settings.desktopHeight,
                  width > 0,
                  height > 0 {
            arguments.append("/size:\(width)x\(height)")
        }

        var needsGatewayPassword = false
        if connection.usesRDPGateway {
            let gatewayHost = try requiredGatewayValue(connection.rdpGatewayHost)
            let gatewayPort = connection.rdpGatewayPort ?? 443
            guard (1...65_535).contains(gatewayPort) else {
                throw RDPLaunchError.invalidPort
            }
            let usesConnectionIdentity = connection.rdpGatewayCredentialProfile == nil
            let resolvedGatewayUsername = usesConnectionIdentity
                ? connection.resolvedUsername()
                : gatewayCredential?.username
            let resolvedGatewayDomain = usesConnectionIdentity
                ? connection.resolvedDomain()
                : gatewayCredential?.domain
            guard let gatewayUsername = nonEmpty(resolvedGatewayUsername) else {
                throw RDPLaunchError.missingUsername
            }
            guard gatewayCredential?.authenticationType.isSupported(by: .rdp) != false else {
                throw RDPLaunchError.unsupportedAuthentication(
                    profileName: gatewayCredential?.name ?? "RD Gateway"
                )
            }

            var gatewayParts = [
                "g:\(endpoint(host: gatewayHost, port: gatewayPort))",
                "u:\(try gatewayValue(gatewayUsername))"
            ]
            if let gatewayDomain = nonEmpty(resolvedGatewayDomain) {
                gatewayParts.append("d:\(try gatewayValue(gatewayDomain))")
            }
            gatewayParts.append("usage-method:direct")
            gatewayParts.append("type:auto")
            arguments.append("/gateway:\(gatewayParts.joined(separator: ","))")
            needsGatewayPassword = true
        }

        return RDPLaunchPlan(
            arguments: arguments,
            needsGatewayPassword: needsGatewayPassword
        )
    }

    private static func endpoint(host: String, port: Int) -> String {
        let normalizedHost: String
        if host.contains(":"), !host.hasPrefix("[") {
            normalizedHost = "[\(host)]"
        } else {
            normalizedHost = host
        }
        return "\(normalizedHost):\(port)"
    }

    private static func requiredValue(
        _ value: String?,
        error: RDPLaunchError
    ) throws -> String {
        guard let value = nonEmpty(value) else { throw error }
        return value
    }

    private static func requiredGatewayValue(_ value: String?) throws -> String {
        try gatewayValue(requiredValue(value, error: .missingHost))
    }

    private static func gatewayValue(_ value: String) throws -> String {
        guard !value.contains(","),
              !value.contains("\n"),
              !value.contains("\r") else {
            throw RDPLaunchError.invalidGatewayValue
        }
        return value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
protocol RDPPasswordPrompting {
    func requestPassword(title: String, message: String) -> String?
}

@MainActor
final class RDPPasswordPrompt: RDPPasswordPrompting {
    func requestPassword(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")

        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        passwordField.placeholderString = "Password"
        alert.accessoryView = passwordField
        alert.window.initialFirstResponder = passwordField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return passwordField.stringValue
    }
}

@MainActor
protocol RDPServicing: SessionLaunching {}

@MainActor
final class RDPService: RDPServicing {
    static let shared = RDPService()

    private let keychainService: KeychainService
    private let passwordPrompt: RDPPasswordPrompting
    private let fileManager: FileManager
    private var processes: [UUID: Process] = [:]

    init(
        keychainService: KeychainService = .shared,
        passwordPrompt: RDPPasswordPrompting? = nil,
        fileManager: FileManager = .default
    ) {
        self.keychainService = keychainService
        self.passwordPrompt = passwordPrompt ?? RDPPasswordPrompt()
        self.fileManager = fileManager
    }

    func connect(to connection: Connection, credential: CredentialProfile?) async throws {
        let gatewayCredential = connection.resolvedRDPGatewayCredentialProfile()
        let plan = try RDPCommandBuilder.makePlan(
            connection: connection,
            credential: credential,
            gatewayCredential: gatewayCredential
        )
        let executableURL = try freeRDPExecutableURL()

        var serverPassword = try resolvePassword(
            profile: credential,
            promptTitle: "RDP Password",
            promptMessage: "Enter the password for \(connection.name)."
        )
        var gatewayPassword: String?
        if plan.needsGatewayPassword {
            if gatewayCredential?.id == credential?.id {
                gatewayPassword = serverPassword
            } else {
                gatewayPassword = try resolvePassword(
                    profile: gatewayCredential,
                    promptTitle: "RD Gateway Password",
                    promptMessage: "Enter the password for \(connection.rdpGatewayHost ?? "the RD Gateway")."
                )
            }
        }
        defer {
            serverPassword.removeAll(keepingCapacity: false)
            gatewayPassword?.removeAll(keepingCapacity: false)
        }

        await disconnect(connectionID: connection.id)

        let connectionID = connection.id
        let process = Process()
        process.executableURL = executableURL
        process.arguments = plan.arguments
        let inputPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finishedProcess in
            Task { @MainActor in
                guard self?.processes[connectionID] === finishedProcess else { return }
                self?.processes.removeValue(forKey: connectionID)
            }
        }

        do {
            processes[connectionID] = process
            try process.run()

            var credentialData = Data(serverPassword.utf8)
            credentialData.append(0x0A)
            if let gatewayPassword {
                credentialData.append(contentsOf: gatewayPassword.utf8)
                credentialData.append(0x0A)
            }
            try inputPipe.fileHandleForWriting.write(contentsOf: credentialData)
            try inputPipe.fileHandleForWriting.close()
            credentialData.resetBytes(in: credentialData.startIndex..<credentialData.endIndex)
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            processes.removeValue(forKey: connectionID)
            if process.isRunning { process.terminate() }
            throw RDPLaunchError.launchFailed(error.localizedDescription)
        }
    }

    func disconnect(connectionID: UUID) async {
        guard let process = processes.removeValue(forKey: connectionID) else { return }
        if process.isRunning {
            process.terminate()
        }
    }

    func disconnectAll() {
        let runningProcesses = processes.values
        processes.removeAll()
        for process in runningProcesses where process.isRunning {
            process.terminate()
        }
    }

    private func resolvePassword(
        profile: CredentialProfile?,
        promptTitle: String,
        promptMessage: String
    ) throws -> String {
        switch profile?.authenticationType {
        case .password:
            guard let reference = profile?.keychainReference,
                  let password = try keychainService.password(reference: reference),
                  !password.isEmpty else {
                throw RDPLaunchError.missingStoredPassword(
                    profileName: profile?.name ?? "Credential"
                )
            }
            return password
        case .promptEveryTime, nil:
            guard let password = passwordPrompt.requestPassword(
                title: promptTitle,
                message: promptMessage
            ) else {
                throw RDPLaunchError.passwordPromptCancelled
            }
            return password
        case .sshKey, .sshAgent:
            throw RDPLaunchError.unsupportedAuthentication(
                profileName: profile?.name ?? "Credential"
            )
        }
    }

    private func freeRDPExecutableURL() throws -> URL {
        let candidates = [
            "/opt/homebrew/bin/sdl-freerdp",
            "/opt/homebrew/bin/sdl-freerdp3",
            "/usr/local/bin/sdl-freerdp",
            "/usr/local/bin/sdl-freerdp3"
        ]

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw RDPLaunchError.freeRDPNotInstalled
    }
}
