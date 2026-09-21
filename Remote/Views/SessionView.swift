import SwiftUI

struct SessionView: View {
    let connection: Connection

    @ObservedObject private var rdpService = RDPService.shared
    @ObservedObject private var sshService = SSHSessionService.shared
    @State private var status: SessionStatus = .idle
    @State private var sshController: SSHSessionController?
    @State private var showingEditor = false
    @State private var showingConnectionError = false
    @State private var connectionErrorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: connection.connectionProtocol == .ssh ? "terminal.fill" : "display")
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.headline)
                    Text("\(connection.host):\(connection.port)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if connection.usesRDPGateway, let gatewayHost = connection.rdpGatewayHost {
                        Text("via \(gatewayHost):\(connection.rdpGatewayPort ?? 443)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                statusLabel

                Button {
                    showingEditor = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                if status == .launched {
                    if connection.connectionProtocol == .ssh, let sshController {
                        SSHSessionControls(controller: sshController) {
                            disconnectSSH()
                        }
                    } else if connection.connectionProtocol == .rdp {
                        Button {
                            showRDPWindow()
                        } label: {
                            Label("Show Window", systemImage: "macwindow.on.rectangle")
                        }

                        Button("Disconnect", role: .destructive) {
                            disconnectRDP()
                        }
                    }
                } else {
                    Button(connectButtonTitle) {
                        connect()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(status == .connecting)
                }
            }
            .padding()

            Divider()

            sessionSurface
        }
        .navigationTitle(connection.name)
        .sheet(isPresented: $showingEditor) {
            ConnectionEditorView(connection: connection)
        }
        .alert("Unable to Connect", isPresented: $showingConnectionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionErrorMessage)
        }
        .onChange(of: rdpService.activeConnectionIDs) { _, activeConnectionIDs in
            guard connection.connectionProtocol == .rdp,
                  status == .launched,
                  !activeConnectionIDs.contains(connection.id) else { return }
            status = .idle
            if let failure = rdpService.sessionFailures[connection.id] {
                presentRDPFailure(failure)
            }
        }
        .onChange(of: sshService.activeConnectionIDs) { _, activeConnectionIDs in
            guard connection.connectionProtocol == .ssh,
                  status == .launched,
                  !activeConnectionIDs.contains(connection.id) else { return }
            status = .idle
        }
        .onAppear {
            if connection.connectionProtocol == .ssh,
               let existing = sshService.session(connectionID: connection.id),
               existing.isRunning {
                sshController = existing
                status = .launched
            } else if connection.connectionProtocol == .rdp,
                      rdpService.activeConnectionIDs.contains(connection.id) {
                status = .launched
            }
        }
    }

    @ViewBuilder
    private var sessionSurface: some View {
        if connection.connectionProtocol == .ssh,
           status == .launched,
           let sshController {
            SSHSessionSurface(controller: sshController)
        } else {
            ZStack {
                Color(nsColor: .textBackgroundColor)

                VStack(spacing: 14) {
                    Image(systemName: connection.connectionProtocol == .ssh ? "terminal" : "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(sessionTitle)
                        .font(.title2)
                    Text(placeholderMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                .padding(32)
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var connectButtonTitle: String {
        switch status {
        case .idle: "Connect"
        case .connecting: "Connecting…"
        case .launched:
            connection.connectionProtocol == .rdp ? "Disconnect" : "Open Again"
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: .secondary
        case .connecting: .orange
        case .launched: .green
        }
    }

    private var sessionTitle: String {
        switch status {
        case .idle: "Ready to connect"
        case .connecting: "Opening session"
        case .launched:
            connection.connectionProtocol == .ssh ? "SSH session" : "Session launched"
        }
    }

    private var placeholderMessage: String {
        switch connection.connectionProtocol {
        case .ssh:
            if status == .launched {
                "The SSH process has ended. Connect again to start a new embedded session."
            } else if connection.resolvedCredentialProfile()?.authenticationType == .promptEveryTime {
                "OpenSSH will securely prompt inside this tab. Relay never places passwords in a command or environment variable."
            } else {
                "The connection will open in this tab using macOS OpenSSH."
            }
        case .rdp:
            if status == .launched {
                "FreeRDP is running in its own window. After approving 2FA, use Show Window if the desktop remains minimized."
            } else {
                "The connection will open in a FreeRDP window with clipboard and dynamic resizing enabled."
            }
        }
    }

    private func connect() {
        guard status != .connecting else { return }

        status = .connecting

        Task { @MainActor in
            do {
                let credential = connection.resolvedCredentialProfile()
                switch connection.connectionProtocol {
                case .ssh:
                    sshController = try sshService.connect(
                        to: connection,
                        credential: credential
                    )
                case .rdp:
                    try await rdpService.connect(
                        to: connection,
                        credential: credential
                    )
                    if let failure = rdpService.sessionFailures[connection.id] {
                        throw RDPLaunchError.sessionEnded(
                            exitStatus: failure.exitStatus,
                            details: failure.details
                        )
                    }
                    guard rdpService.activeConnectionIDs.contains(connection.id) else {
                        throw RDPLaunchError.sessionNotRunning
                    }
                }
                status = .launched
            } catch {
                status = .idle
                connectionErrorMessage = error.localizedDescription
                showingConnectionError = true
            }
        }
    }

    private func showRDPWindow() {
        do {
            try rdpService.showWindow(connectionID: connection.id)
        } catch {
            status = .idle
            connectionErrorMessage = error.localizedDescription
            showingConnectionError = true
        }
    }

    private func disconnectRDP() {
        status = .connecting
        Task { @MainActor in
            await rdpService.disconnect(connectionID: connection.id)
            status = .idle
        }
    }

    private func disconnectSSH() {
        sshService.disconnect(connectionID: connection.id)
        sshController = nil
        status = .idle
    }

    private func presentRDPFailure(_ failure: RDPSessionFailure) {
        connectionErrorMessage = RDPLaunchError.sessionEnded(
            exitStatus: failure.exitStatus,
            details: failure.details
        ).localizedDescription
        showingConnectionError = true
    }
}

private struct SSHSessionControls: View {
    @ObservedObject var controller: SSHSessionController
    let disconnect: () -> Void

    var body: some View {
        if controller.placement == .embedded {
            Button {
                controller.popOut()
            } label: {
                Label("Pop Out", systemImage: "macwindow.badge.plus")
            }

            Button {
                controller.popOut(fullScreen: true)
            } label: {
                Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
        } else {
            Button {
                controller.showDetachedWindow()
            } label: {
                Label("Show Window", systemImage: "macwindow.on.rectangle")
            }

            Button {
                controller.reattach()
            } label: {
                Label("Move Here", systemImage: "rectangle.inset.filled")
            }
        }

        Button("Disconnect", role: .destructive, action: disconnect)
    }
}

private struct SSHSessionSurface: View {
    @ObservedObject var controller: SSHSessionController

    var body: some View {
        if controller.placement == .embedded {
            EmbeddedSSHSessionView(controller: controller)
                .background(Color.black)
        } else {
            ContentUnavailableView {
                Label("SSH Session Popped Out", systemImage: "macwindow.on.rectangle")
            } description: {
                Text("The live session is running in its own window.")
            } actions: {
                Button("Show Window") { controller.showDetachedWindow() }
                Button("Move Back to Relay") { controller.reattach() }
            }
        }
    }
}

private enum SessionStatus: Equatable {
    case idle
    case connecting
    case launched

    var displayName: String {
        switch self {
        case .idle: "Disconnected"
        case .connecting: "Connecting"
        case .launched: "Connected"
        }
    }
}
