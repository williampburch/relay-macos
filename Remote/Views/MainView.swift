import SwiftData
import SwiftUI

struct MainView: View {
    @Query private var connections: [Connection]

    @State private var selectedConnectionID: UUID?
    @State private var selectedGroupID: UUID?
    @State private var openConnectionIDs: [UUID] = []
    @State private var showingConnectionEditor = false
    @State private var showingCredentialManager = false
    @State private var credentialManagerInitialProtocol: ConnectionProtocol?

    private var selectedConnection: Connection? {
        guard let selectedConnectionID else { return nil }
        return connections.first { $0.id == selectedConnectionID }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedConnectionID: $selectedConnectionID,
                selectedGroupID: $selectedGroupID
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
        } detail: {
            sessionArea
        }
        .frame(minWidth: 760, minHeight: 480)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    showingConnectionEditor = true
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
                .help("Create a connection")

                Menu {
                    Button("Manage Credential Profiles…", systemImage: "key") {
                        credentialManagerInitialProtocol = nil
                        showingCredentialManager = true
                    }
                    Divider()
                    Button("New SSH Credential…", systemImage: "terminal") {
                        credentialManagerInitialProtocol = .ssh
                        showingCredentialManager = true
                    }
                    Button("New RDP Credential…", systemImage: "display") {
                        credentialManagerInitialProtocol = .rdp
                        showingCredentialManager = true
                    }
                } label: {
                    Label("Credentials", systemImage: "key")
                }
                .help("Manage credential profiles")
            }
        }
        .sheet(isPresented: $showingConnectionEditor) {
            ConnectionEditorView(connection: nil, initialGroupID: selectedGroupID)
        }
        .sheet(isPresented: $showingCredentialManager) {
            CredentialManagerView(initialNewProtocol: credentialManagerInitialProtocol)
        }
        .onChange(of: selectedConnectionID) { _, newValue in
            guard let newValue, !openConnectionIDs.contains(newValue) else { return }
            openConnectionIDs.append(newValue)
        }
        .onChange(of: connections.map(\.id)) { _, availableIDs in
            let removedIDs = Set(openConnectionIDs).subtracting(availableIDs)
            removedIDs.forEach { SessionCoordinator.disconnect(connectionID: $0) }
            openConnectionIDs.removeAll { !availableIDs.contains($0) }
            if let selectedConnectionID, !availableIDs.contains(selectedConnectionID) {
                self.selectedConnectionID = openConnectionIDs.last
            }
        }
    }

    @ViewBuilder
    private var sessionArea: some View {
        if openConnections.isEmpty {
            ContentUnavailableView {
                Label("No Connection Selected", systemImage: "rectangle.connected.to.line.below")
            } description: {
                Text("Choose a connection in the sidebar or create a new one.")
            } actions: {
                Button("New Connection") {
                    showingConnectionEditor = true
                }
            }
        } else {
            VStack(spacing: 0) {
                SessionTabBar(
                    connections: openConnections,
                    selectedConnectionID: $selectedConnectionID,
                    close: closeTab
                )
                Divider()

                if let selectedConnection {
                    SessionView(connection: selectedConnection)
                } else if let first = openConnections.first {
                    SessionView(connection: first)
                        .onAppear { selectedConnectionID = first.id }
                }
            }
        }
    }

    private var openConnections: [Connection] {
        openConnectionIDs.compactMap { id in
            connections.first { $0.id == id }
        }
    }

    private func closeTab(_ id: UUID) {
        guard let index = openConnectionIDs.firstIndex(of: id) else { return }
        SessionCoordinator.disconnect(connectionID: id)
        let wasSelected = selectedConnectionID == id
        openConnectionIDs.remove(at: index)

        if wasSelected {
            if openConnectionIDs.indices.contains(index) {
                selectedConnectionID = openConnectionIDs[index]
            } else {
                selectedConnectionID = openConnectionIDs.last
            }
        }
    }
}

private struct SessionTabBar: View {
    let connections: [Connection]
    @Binding var selectedConnectionID: UUID?
    let close: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(connections) { connection in
                    HStack(spacing: 6) {
                        Image(systemName: connection.connectionProtocol == .ssh ? "terminal" : "display")
                            .foregroundStyle(.secondary)
                        Text(connection.name)
                            .lineLimit(1)
                        Button {
                            close(connection.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help("Close tab")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        selectedConnectionID == connection.id
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedConnectionID = connection.id }
                }
            }
            .padding(5)
        }
        .scrollIndicators(.hidden)
        .background(.bar)
    }
}

#Preview {
    MainView()
        .modelContainer(for: [ConnectionGroup.self, Connection.self, CredentialProfile.self], inMemory: true)
}
