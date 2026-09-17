import AppKit
import Combine
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
    case unsupportedPasswordCharacters
    case sessionNotRunning
    case sessionEnded(exitStatus: Int32, details: String)
    case windowActivationFailed
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
        case .unsupportedPasswordCharacters:
            return "FreeRDP cannot securely receive a password containing a line break, or an RD Gateway password containing a comma."
        case .sessionNotRunning:
            return "The FreeRDP session is no longer running. Connect again to start a new session."
        case .sessionEnded(let exitStatus, let details):
            return RDPFailureInterpreter.message(
                exitStatus: exitStatus,
                details: details
            )
        case .windowActivationFailed:
            return "The FreeRDP window could not be brought forward. Look for sdl-freerdp in the Dock or use Command-Tab."
        case .launchFailed(let message):
            return "FreeRDP could not be launched: \(message)"
        }
    }
}

struct RDPLaunchPlan: Equatable {
    let arguments: [String]
    let needsGatewayPassword: Bool
}

struct RDPSessionFailure: Equatable {
    let exitStatus: Int32
    let details: String
}

enum RDPFailureInterpreter {
    static func isExpectedTermination(exitStatus: Int32) -> Bool {
        // FreeRDP: success, disconnect, logoff, or disconnect initiated by the user.
        [0, 1, 2, 11].contains(exitStatus)
    }

    static func message(exitStatus: Int32, details: String) -> String {
        if details.localizedCaseInsensitiveContains("E_PROXY_RAP_ACCESSDENIED") {
            return """
            RD Gateway accepted the authentication request, but its Resource Authorization Policy denied access to the requested computer.

            Use the gateway-approved internal computer name or FQDN instead of an IP address. If that name is already correct, the RD Gateway administrator must grant your account access to that computer or resource group.
            """
        }

        let diagnostic = details.isEmpty
            ? "No additional diagnostic was reported."
            : details
        return "FreeRDP ended during connection setup (exit code \(exitStatus)).\n\n\(diagnostic)"
    }
}

enum RDPDiagnosticSanitizer {
    static func sanitize(_ output: String, redacting sensitiveValues: [String]) -> String {
        let noteworthyLines = output
            .components(separatedBy: .newlines)
            .filter { line in
                let lowercased = line.lowercased()
                return lowercased.contains("error")
                    || lowercased.contains("warn")
                    || lowercased.contains("fail")
                    || lowercased.contains("errconnect")
            }

        var sanitized = noteworthyLines.suffix(12).joined(separator: "\n")
        for value in sensitiveValues
            .filter({ !$0.isEmpty })
            .sorted(by: { $0.count > $1.count }) {
            sanitized = sanitized.replacingOccurrences(
                of: value,
                with: "[redacted]",
                options: [.caseInsensitive]
            )
        }

        let secretPatterns = [
            #"(?i)(password|passwd|token|authorization|cookie|secret)(\s*[:=]\s*)[^\s,;]+"#,
            #"(?i)(^|[\s,])/??(?:p|gp):[^\s,]+"#
        ]
        for pattern in secretPatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: "$1[redacted]",
                options: .regularExpression
            )
        }

        if sanitized.count > 6_000 {
            sanitized = String(sanitized.suffix(6_000))
        }
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RDPArgumentStreamBuilder {
    static let processArguments = ["/args-from:stdin"]

    static func makeInput(
        plan: RDPLaunchPlan,
        serverPassword: String,
        gatewayPassword: String?
    ) throws -> Data {
        guard !serverPassword.contains("\n"),
              !serverPassword.contains("\r") else {
            throw RDPLaunchError.unsupportedPasswordCharacters
        }
        if let gatewayPassword {
            guard !gatewayPassword.contains("\n"),
                  !gatewayPassword.contains("\r"),
                  !gatewayPassword.contains(",") else {
                throw RDPLaunchError.unsupportedPasswordCharacters
            }
        }

        var arguments = plan.arguments
        arguments.append("/p:\(serverPassword)")

        if let gatewayPassword,
           let gatewayIndex = arguments.firstIndex(where: { $0.hasPrefix("/gateway:") }) {
            arguments[gatewayIndex].append(",p:\(gatewayPassword)")
        }

        return Data((arguments.joined(separator: "\n") + "\n").utf8)
    }
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
            "/log-level:WARN",
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
            gatewayParts.append(
                "type:\(settings.effectiveRDPGatewayTransport.freeRDPValue)"
            )
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
final class RDPService: RDPServicing, ObservableObject {
    static let shared = RDPService()

    private let keychainService: KeychainService
    private let passwordPrompt: RDPPasswordPrompting
    private let fileManager: FileManager
    private var processes: [UUID: Process] = [:]
    private var processDiagnostics: [UUID: String] = [:]
    @Published private(set) var activeConnectionIDs: Set<UUID> = []
    @Published private(set) var sessionFailures: [UUID: RDPSessionFailure] = [:]

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
        var argumentInput = try RDPArgumentStreamBuilder.makeInput(
            plan: plan,
            serverPassword: serverPassword,
            gatewayPassword: gatewayPassword
        )
        defer {
            argumentInput.resetBytes(in: argumentInput.startIndex..<argumentInput.endIndex)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = RDPArgumentStreamBuilder.processArguments
        let argumentPipe = Pipe()
        let diagnosticPipe = Pipe()
        process.standardInput = argumentPipe
        process.standardOutput = diagnosticPipe
        process.standardError = diagnosticPipe
        processDiagnostics[connectionID] = ""
        sessionFailures.removeValue(forKey: connectionID)

        let sensitiveValues = diagnosticRedactionValues(
            connection: connection,
            credential: credential,
            gatewayCredential: gatewayCredential,
            passwords: [serverPassword, gatewayPassword].compactMap { $0 }
        )
        diagnosticPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let output = String(data: data, encoding: .utf8) else { return }
            let sanitized = RDPDiagnosticSanitizer.sanitize(
                output,
                redacting: sensitiveValues
            )
            guard !sanitized.isEmpty else { return }
            Task { @MainActor in
                self?.appendDiagnostic(sanitized, connectionID: connectionID)
            }
        }
        process.terminationHandler = { [weak self] finishedProcess in
            Task { @MainActor in
                guard self?.processes[connectionID] === finishedProcess else { return }
                try? await Task.sleep(for: .milliseconds(150))
                diagnosticPipe.fileHandleForReading.readabilityHandler = nil
                self?.processes.removeValue(forKey: connectionID)
                let details = self?.processDiagnostics.removeValue(forKey: connectionID) ?? ""
                let exitStatus = finishedProcess.terminationStatus
                if RDPFailureInterpreter.isExpectedTermination(exitStatus: exitStatus) {
                    self?.sessionFailures.removeValue(forKey: connectionID)
                } else {
                    self?.sessionFailures[connectionID] = RDPSessionFailure(
                        exitStatus: exitStatus,
                        details: details
                    )
                }
                self?.activeConnectionIDs.remove(connectionID)
            }
        }

        do {
            processes[connectionID] = process
            try process.run()
            activeConnectionIDs.insert(connectionID)
            try argumentPipe.fileHandleForWriting.write(contentsOf: argumentInput)
            try argumentPipe.fileHandleForWriting.close()
        } catch {
            try? argumentPipe.fileHandleForWriting.close()
            diagnosticPipe.fileHandleForReading.readabilityHandler = nil
            processes.removeValue(forKey: connectionID)
            processDiagnostics.removeValue(forKey: connectionID)
            activeConnectionIDs.remove(connectionID)
            if process.isRunning { process.terminate() }
            throw RDPLaunchError.launchFailed(error.localizedDescription)
        }
    }

    func showWindow(connectionID: UUID) throws {
        guard let process = processes[connectionID], process.isRunning else {
            activeConnectionIDs.remove(connectionID)
            throw RDPLaunchError.sessionNotRunning
        }
        guard let application = NSRunningApplication(
            processIdentifier: process.processIdentifier
        ) else {
            throw RDPLaunchError.windowActivationFailed
        }

        application.unhide()
        guard application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]) else {
            throw RDPLaunchError.windowActivationFailed
        }
    }

    func disconnect(connectionID: UUID) async {
        activeConnectionIDs.remove(connectionID)
        sessionFailures.removeValue(forKey: connectionID)
        processDiagnostics.removeValue(forKey: connectionID)
        guard let process = processes.removeValue(forKey: connectionID) else { return }
        if process.isRunning {
            process.terminate()
        }
    }

    func disconnectAll() {
        let runningProcesses = processes.values
        processes.removeAll()
        processDiagnostics.removeAll()
        sessionFailures.removeAll()
        activeConnectionIDs.removeAll()
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

    private func appendDiagnostic(_ diagnostic: String, connectionID: UUID) {
        let current = processDiagnostics[connectionID] ?? ""
        let combined = current.isEmpty ? diagnostic : "\(current)\n\(diagnostic)"
        processDiagnostics[connectionID] = String(combined.suffix(6_000))
    }

    private func diagnosticRedactionValues(
        connection: Connection,
        credential: CredentialProfile?,
        gatewayCredential: CredentialProfile?,
        passwords: [String]
    ) -> [String] {
        passwords + ([
            connection.host,
            connection.rdpGatewayHost,
            connection.resolvedUsername(),
            connection.resolvedDomain(),
            credential?.username,
            credential?.domain,
            gatewayCredential?.username,
            gatewayCredential?.domain
        ].compactMap { $0 })
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
