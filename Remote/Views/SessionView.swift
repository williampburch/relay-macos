import SwiftUI

struct SessionView: View {
    let connection: Connection

    @State private var status: SessionStatus = .idle
    @State private var showingEditor = false

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
                }

                Spacer()

                statusLabel

                Button {
                    showingEditor = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(status == .idle ? "Connect" : "Disconnect") {
                    status = status == .idle ? .preview : .idle
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            ZStack {
                Color(nsColor: .textBackgroundColor)

                VStack(spacing: 14) {
                    Image(systemName: connection.connectionProtocol == .ssh ? "terminal" : "rectangle.inset.filled.and.person.filled")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(status == .idle ? "Ready to connect" : "Session preview")
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
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status == .idle ? Color.secondary : Color.orange)
                .frame(width: 7, height: 7)
            Text(status == .idle ? "Disconnected" : "Preview")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderMessage: String {
        switch connection.connectionProtocol {
        case .ssh:
            "The macOS OpenSSH session will appear here when session launching is enabled."
        case .rdp:
            "The FreeRDP desktop session will appear here when session launching is enabled."
        }
    }
}

private enum SessionStatus {
    case idle
    case preview
}
