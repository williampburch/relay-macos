import SwiftData
import SwiftUI

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var groups: [ConnectionGroup]
    @Query private var connections: [Connection]

    @Binding var selectedConnectionID: UUID?
    @Binding var selectedGroupID: UUID?

    @State private var searchText = ""
    @State private var groupToEdit: ConnectionGroup?
    @State private var connectionToEdit: Connection?
    @State private var showingNewGroup = false
    @State private var showingNewConnection = false

    private var rootGroups: [ConnectionGroup] {
        groups
            .filter { $0.parent == nil }
            .filter(groupIsVisible)
            .sorted(by: groupSort)
    }

    private var ungroupedConnections: [Connection] {
        connections
            .filter { $0.group == nil }
            .filter(connectionIsVisible)
            .sorted(by: connectionSort)
    }

    var body: some View {
        List(selection: $selectedConnectionID) {
            if !ungroupedConnections.isEmpty {
                Section("Connections") {
                    ForEach(ungroupedConnections) { connection in
                        connectionRow(connection)
                    }
                }
            }

            Section("Groups") {
                ForEach(rootGroups) { group in
                    GroupTreeRow(
                        group: group,
                        searchText: searchText,
                        selectedConnectionID: $selectedConnectionID,
                        selectedGroupID: $selectedGroupID,
                        onEditGroup: { groupToEdit = $0 },
                        onDeleteGroup: deleteGroup,
                        onEditConnection: { connectionToEdit = $0 },
                        onDeleteConnection: deleteConnection
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search connections")
        .navigationTitle("Relay")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Connection", systemImage: "rectangle.connected.to.line.below") {
                        showingNewConnection = true
                    }
                    Button("New Group", systemImage: "folder.badge.plus") {
                        showingNewGroup = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuIndicator(.hidden)
            }
        }
        .sheet(isPresented: $showingNewConnection) {
            ConnectionEditorView(connection: nil, initialGroupID: selectedGroupID)
        }
        .sheet(item: $connectionToEdit) { connection in
            ConnectionEditorView(connection: connection)
        }
        .sheet(isPresented: $showingNewGroup) {
            GroupEditorView(group: nil, initialParentID: selectedGroupID)
        }
        .sheet(item: $groupToEdit) { group in
            GroupEditorView(group: group)
        }
        .overlay {
            if groups.isEmpty && connections.isEmpty {
                ContentUnavailableView {
                    Label("No Connections", systemImage: "sidebar.left")
                } description: {
                    Text("Add a connection or group to get started.")
                }
            } else if rootGroups.isEmpty && ungroupedConnections.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    @ViewBuilder
    private func connectionRow(_ connection: Connection) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                Text("\(connection.host):\(connection.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: connection.connectionProtocol == .ssh ? "terminal" : "display")
        }
        .tag(connection.id)
        .contextMenu {
            Button("Edit") { connectionToEdit = connection }
            Divider()
            Button("Delete", role: .destructive) { deleteConnection(connection) }
        }
    }

    private func groupIsVisible(_ group: ConnectionGroup) -> Bool {
        guard !searchText.isEmpty else { return true }
        if group.name.localizedCaseInsensitiveContains(searchText) { return true }
        if group.connections.contains(where: connectionIsVisible) { return true }
        return group.children.contains(where: groupIsVisible)
    }

    private func connectionIsVisible(_ connection: Connection) -> Bool {
        guard !searchText.isEmpty else { return true }
        return connection.name.localizedCaseInsensitiveContains(searchText)
            || connection.host.localizedCaseInsensitiveContains(searchText)
            || (connection.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            || groupNames(for: connection.group).contains {
                $0.localizedCaseInsensitiveContains(searchText)
            }
    }

    private func groupNames(for initialGroup: ConnectionGroup?) -> [String] {
        var names = [String]()
        var group = initialGroup
        var visited = Set<UUID>()
        while let current = group, visited.insert(current.id).inserted {
            names.append(current.name)
            group = current.parent
        }
        return names
    }

    private func deleteConnection(_ connection: Connection) {
        if selectedConnectionID == connection.id { selectedConnectionID = nil }
        modelContext.delete(connection)
    }

    private func deleteGroup(_ group: ConnectionGroup) {
        if selectedGroupID == group.id { selectedGroupID = nil }
        modelContext.delete(group)
    }

    private func groupSort(_ lhs: ConnectionGroup, _ rhs: ConnectionGroup) -> Bool {
        lhs.sortOrder == rhs.sortOrder
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.sortOrder < rhs.sortOrder
    }

    private func connectionSort(_ lhs: Connection, _ rhs: Connection) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
        return lhs.sortOrder == rhs.sortOrder
            ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            : lhs.sortOrder < rhs.sortOrder
    }
}

private struct GroupTreeRow: View {
    let group: ConnectionGroup
    let searchText: String
    @Binding var selectedConnectionID: UUID?
    @Binding var selectedGroupID: UUID?
    let onEditGroup: (ConnectionGroup) -> Void
    let onDeleteGroup: (ConnectionGroup) -> Void
    let onEditConnection: (Connection) -> Void
    let onDeleteConnection: (Connection) -> Void

    @State private var isExpanded = true

    private var visibleChildren: [ConnectionGroup] {
        group.children
            .filter(groupIsVisible)
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.sortOrder < $1.sortOrder
            }
    }

    private var visibleConnections: [Connection] {
        group.connections
            .filter(connectionIsVisible)
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
                return $0.sortOrder == $1.sortOrder
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.sortOrder < $1.sortOrder
            }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(visibleChildren) { child in
                GroupTreeRow(
                    group: child,
                    searchText: searchText,
                    selectedConnectionID: $selectedConnectionID,
                    selectedGroupID: $selectedGroupID,
                    onEditGroup: onEditGroup,
                    onDeleteGroup: onDeleteGroup,
                    onEditConnection: onEditConnection,
                    onDeleteConnection: onDeleteConnection
                )
            }
            ForEach(visibleConnections) { connection in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(connection.name)
                            if connection.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(connection.host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: connection.connectionProtocol == .ssh ? "terminal" : "display")
                }
                .tag(connection.id)
                .contextMenu {
                    Button("Edit") { onEditConnection(connection) }
                    Divider()
                    Button("Delete", role: .destructive) { onDeleteConnection(connection) }
                }
            }
        } label: {
            Label(group.name, systemImage: "folder")
                .contentShape(Rectangle())
                .onTapGesture { selectedGroupID = group.id }
                .contextMenu {
                    Button("Edit") { onEditGroup(group) }
                    Divider()
                    Button("Delete", role: .destructive) { onDeleteGroup(group) }
                }
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty { isExpanded = true }
        }
    }

    private func groupIsVisible(_ candidate: ConnectionGroup) -> Bool {
        guard !searchText.isEmpty else { return true }
        return candidate.name.localizedCaseInsensitiveContains(searchText)
            || candidate.connections.contains(where: connectionIsVisible)
            || candidate.children.contains(where: groupIsVisible)
    }

    private func connectionIsVisible(_ connection: Connection) -> Bool {
        guard !searchText.isEmpty else { return true }
        return connection.name.localizedCaseInsensitiveContains(searchText)
            || connection.host.localizedCaseInsensitiveContains(searchText)
            || (connection.notes?.localizedCaseInsensitiveContains(searchText) ?? false)
            || groupNames(for: connection.group).contains {
                $0.localizedCaseInsensitiveContains(searchText)
            }
    }

    private func groupNames(for initialGroup: ConnectionGroup?) -> [String] {
        var names = [String]()
        var group = initialGroup
        var visited = Set<UUID>()
        while let current = group, visited.insert(current.id).inserted {
            names.append(current.name)
            group = current.parent
        }
        return names
    }
}
