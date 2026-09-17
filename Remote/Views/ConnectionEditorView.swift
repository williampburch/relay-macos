import SwiftData
import SwiftUI

struct ConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var groups: [ConnectionGroup]
    @Query private var credentialProfiles: [CredentialProfile]

    private let connection: Connection?
    private let initialGroupID: UUID?

    @State private var displayName: String
    @State private var host: String
    @State private var protocolType: ConnectionProtocol
    @State private var port: Int
    @State private var groupID: UUID?
    @State private var credentialProfileID: UUID?
    @State private var usernameOverride: String
    @State private var domainOverride: String
    @State private var notes: String
    @State private var isFavorite: Bool

    init(connection: Connection?, initialGroupID: UUID? = nil) {
        self.connection = connection
        self.initialGroupID = initialGroupID
        _displayName = State(initialValue: connection?.name ?? "")
        _host = State(initialValue: connection?.host ?? "")
        _protocolType = State(initialValue: connection?.connectionProtocol ?? .ssh)
        _port = State(initialValue: connection?.port ?? 22)
        _groupID = State(initialValue: connection?.group?.id ?? initialGroupID)
        _credentialProfileID = State(initialValue: connection?.credentialProfile?.id)
        _usernameOverride = State(initialValue: connection?.usernameOverride ?? "")
        _domainOverride = State(initialValue: connection?.domainOverride ?? "")
        _notes = State(initialValue: connection?.notes ?? "")
        _isFavorite = State(initialValue: connection?.isFavorite ?? false)
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...65_535).contains(port)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Name", text: $displayName, prompt: Text("Production Server"))
                    TextField("Host", text: $host, prompt: Text("server.example.com"))

                    Picker("Protocol", selection: $protocolType) {
                        Label("SSH", systemImage: "terminal").tag(ConnectionProtocol.ssh)
                        Label("Remote Desktop", systemImage: "display").tag(ConnectionProtocol.rdp)
                    }
                    .onChange(of: protocolType) { oldValue, newValue in
                        if (oldValue == .ssh && port == 22) || (oldValue == .rdp && port == 3389) {
                            port = newValue == .ssh ? 22 : 3389
                        }
                    }

                    TextField("Port", value: $port, format: .number.grouping(.never))
                }

                Section("Organization") {
                    Picker("Group", selection: $groupID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(sortedGroups) { group in
                            Text(groupPath(for: group)).tag(group.id as UUID?)
                        }
                    }
                    Toggle("Favorite", isOn: $isFavorite)
                }

                Section("Authentication") {
                    Picker("Credential profile", selection: $credentialProfileID) {
                        Text("Inherit from group").tag(nil as UUID?)
                        ForEach(sortedProfiles) { profile in
                            Text(profile.name).tag(profile.id as UUID?)
                        }
                    }
                    TextField("Username override", text: $usernameOverride)
                    if protocolType == .rdp {
                        TextField("Domain override", text: $domainOverride)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

            }
            .formStyle(.grouped)
            .navigationTitle(connection == nil ? "New Connection" : "Edit Connection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
            }
        }
        .frame(width: 500, height: 590)
    }

    private var sortedGroups: [ConnectionGroup] {
        groups.sorted {
            groupPath(for: $0).localizedStandardCompare(groupPath(for: $1)) == .orderedAscending
        }
    }

    private var sortedProfiles: [CredentialProfile] {
        credentialProfiles.sorted {
            $0.sortOrder == $1.sortOrder
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.sortOrder < $1.sortOrder
        }
    }

    private func groupPath(for group: ConnectionGroup) -> String {
        var components = [group.name]
        var current = group.parent
        var visited = Set<UUID>()
        visited.insert(group.id)

        while let parent = current, !visited.contains(parent.id) {
            components.insert(parent.name, at: 0)
            visited.insert(parent.id)
            current = parent.parent
        }
        return components.joined(separator: " / ")
    }

    private func save() {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = connection ?? Connection(
            name: normalizedName,
            host: normalizedHost,
            connectionProtocol: protocolType,
            port: port
        )

        target.name = normalizedName
        target.host = normalizedHost
        target.connectionProtocol = protocolType
        target.port = port
        target.group = groups.first { $0.id == groupID }
        target.credentialProfile = credentialProfiles.first { $0.id == credentialProfileID }
        target.usernameOverride = nilIfEmpty(usernameOverride)
        target.domainOverride = protocolType == .rdp ? nilIfEmpty(domainOverride) : nil
        target.notes = nilIfEmpty(notes)
        target.isFavorite = isFavorite

        if connection == nil { modelContext.insert(target) }
        dismiss()
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct GroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var groups: [ConnectionGroup]
    @Query private var credentialProfiles: [CredentialProfile]

    private let group: ConnectionGroup?

    @State private var name: String
    @State private var parentID: UUID?
    @State private var defaultCredentialProfileID: UUID?
    @State private var defaultUsername: String
    @State private var defaultDomain: String

    init(group: ConnectionGroup?, initialParentID: UUID? = nil) {
        self.group = group
        _name = State(initialValue: group?.name ?? "")
        _parentID = State(initialValue: group?.parent?.id ?? initialParentID)
        _defaultCredentialProfileID = State(initialValue: group?.credentialProfile?.id)
        _defaultUsername = State(initialValue: group?.username ?? "")
        _defaultDomain = State(initialValue: group?.domain ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Name", text: $name)
                    Picker("Parent group", selection: $parentID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(availableParents) { candidate in
                            Text(candidate.name).tag(candidate.id as UUID?)
                        }
                    }
                }

                Section("Defaults") {
                    Picker("Credential profile", selection: $defaultCredentialProfileID) {
                        Text("None").tag(nil as UUID?)
                        ForEach(credentialProfiles.sorted(by: { $0.name < $1.name })) { profile in
                            Text(profile.name).tag(profile.id as UUID?)
                        }
                    }
                    TextField("Username", text: $defaultUsername)
                    TextField("Domain", text: $defaultDomain)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(group == nil ? "New Group" : "Edit Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 450, height: 380)
    }

    private var availableParents: [ConnectionGroup] {
        return groups
            .filter { candidate in
                guard let group else { return true }
                return !group.containsInSubtree(candidate)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func save() {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = group ?? ConnectionGroup(name: normalizedName)
        target.name = normalizedName
        target.parent = groups.first { $0.id == parentID }
        target.credentialProfile = credentialProfiles.first { $0.id == defaultCredentialProfileID }
        target.username = nilIfEmpty(defaultUsername)
        target.domain = nilIfEmpty(defaultDomain)

        if group == nil { modelContext.insert(target) }
        dismiss()
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
