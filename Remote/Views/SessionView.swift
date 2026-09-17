import SwiftUI

struct SessionView: View {
    let connection: Connection

    @ObservedObject private var rdpService = RDPService.shared
    @State private var status: SessionStatus = .idle
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

                if status == .launched, connection.connectionProtocol == .rdp {
                    Button {
                        showRDPWindow()
                    } label: {
                        Label("Show Window", systemImage: "macwindow.on.rectangle")
                    }

                    Button("Disconnect", role: .destructive) {
                        disconnectRDP()
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
            connection.connectionProtocol == .ssh ? "SSH opened in Terminal" : "Session launched"
        }
    }

    private var placeholderMessage: String {
        switch connection.connectionProtocol {
        case .ssh:
            if status == .launched {
                "This first working version runs macOS OpenSSH in Terminal. Close the Terminal window when you are finished."
            } else if connection.resolvedCredentialProfile()?.authenticationType == .password {
                "Terminal will securely prompt for the SSH password. Remote never places it in a command or environment variable."
            } else {
                "The connection will use macOS OpenSSH and open in Terminal."
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
                    try await SSHService.shared.connect(
                        to: connection,
                        credential: credential
                    )
                case .rdp:
                    try await rdpService.connect(
                        to: connection,
                        credential: credential
                    )
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
}

private enum SessionStatus: Equatable {
    case idle
    case connecting
    case launched

    var displayName: String {
        switch self {
        case .idle: "Disconnected"
        case .connecting: "Connecting"
        case .launched: "FreeRDP running"
        }
    }
}
