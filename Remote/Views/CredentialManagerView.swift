import AppKit
import SwiftData
import SwiftUI

struct CredentialManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var credentialProfiles: [CredentialProfile]

    let initialNewProtocol: ConnectionProtocol?

    @State private var selection: UUID?
    @State private var profileToEdit: CredentialProfile?
    @State private var newProfileProtocol: ConnectionProtocol?
    @State private var didPresentInitialEditor = false
    @State private var keychainErrorMessage = ""
    @State private var showingKeychainError = false

    private let keychainService = KeychainService.shared

    init(initialNewProtocol: ConnectionProtocol? = nil) {
        self.initialNewProtocol = initialNewProtocol
    }

    private var selectedProfile: CredentialProfile? {
        guard let selection else { return nil }
        return credentialProfiles.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Text("Credential Profiles")
                        .font(.headline)
                    Spacer()
                    Menu {
                        Button("New SSH Credential", systemImage: "terminal") {
                            newProfileProtocol = .ssh
                        }
                        Button("New RDP Credential", systemImage: "display") {
                            newProfileProtocol = .rdp
                        }
                    } label: {
                        Label("New Credential", systemImage: "plus")
                    }
                    .menuIndicator(.hidden)
                    .help("Create an SSH or RDP credential")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider()

                List(selection: $selection) {
                    ForEach(ConnectionProtocol.allCases) { connectionProtocol in
                        Section(connectionProtocol.displayName) {
                            ForEach(profiles(for: connectionProtocol)) { profile in
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                        Text(profile.authenticationType.displayName(for: connectionProtocol))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: icon(for: profile))
                                }
                                .tag(profile.id)
                                .contextMenu {
                                    Button("Edit") { profileToEdit = profile }
                                    Divider()
                                    Button("Delete", role: .destructive) { delete(profile) }
                                }
                            }
                        }
                    }
                }
                .overlay {
                    if credentialProfiles.isEmpty {
                        ContentUnavailableView {
                            Label("No Credential Profiles", systemImage: "key")
                        } description: {
                            Text("Create an SSH or RDP profile to reuse identity and authentication settings.")
                        } actions: {
                            HStack {
                                Button("New SSH Credential") { newProfileProtocol = .ssh }
                                Button("New RDP Credential") { newProfileProtocol = .rdp }
                            }
                        }
                    }
                }
            }
        } detail: {
            if let selectedProfile {
                CredentialProfileDetail(profile: selectedProfile) {
                    profileToEdit = selectedProfile
                }
            } else {
                ContentUnavailableView {
                    Label("Select a Credential Profile", systemImage: "key")
                } description: {
                    Text("Use the + button to create an SSH or RDP credential.")
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(item: $newProfileProtocol) { connectionProtocol in
            CredentialProfileEditorView(
                profile: nil,
                initialProtocol: connectionProtocol
            ) { savedProfile in
                selection = savedProfile.id
            }
        }
        .sheet(item: $profileToEdit) { profile in
            CredentialProfileEditorView(profile: profile)
        }
        .alert("Unable to Delete Credential", isPresented: $showingKeychainError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keychainErrorMessage)
        }
        .onAppear {
            guard !didPresentInitialEditor, let initialNewProtocol else { return }
            didPresentInitialEditor = true
            newProfileProtocol = initialNewProtocol
        }
    }

    private func profiles(for connectionProtocol: ConnectionProtocol) -> [CredentialProfile] {
        credentialProfiles
            .filter { $0.connectionProtocol == connectionProtocol }
            .sorted {
                $0.sortOrder == $1.sortOrder
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.sortOrder < $1.sortOrder
            }
    }

    private func delete(_ profile: CredentialProfile) {
        let keychainReference = profile.keychainReference
        do {
            if selection == profile.id { selection = nil }
            modelContext.delete(profile)
            try modelContext.save()
            if let keychainReference {
                try keychainService.deletePassword(reference: keychainReference)
            }
        } catch {
            keychainErrorMessage = error.localizedDescription
            showingKeychainError = true
        }
    }

    private func icon(for profile: CredentialProfile) -> String {
        switch (profile.connectionProtocol, profile.authenticationType) {
        case (.rdp, .password): "key.fill"
        case (.ssh, .sshKey): "doc.badge.key"
        case (.ssh, .sshAgent): "person.badge.key"
        case (.ssh, _): "terminal"
        case (.rdp, _): "display"
        }
    }
}

private struct CredentialProfileDetail: View {
    let profile: CredentialProfile
    let edit: () -> Void

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Name", value: profile.name)
                LabeledContent("Protocol", value: profile.connectionProtocol.displayName)
            }

            Section("Identity") {
                LabeledContent("Username", value: profile.username.isEmpty ? "Not set" : profile.username)
                if profile.connectionProtocol == .rdp {
                    LabeledContent("Domain", value: profile.domain ?? "Not set")
                }
            }

            Section("Authentication") {
                LabeledContent(
                    "Method",
                    value: profile.authenticationType.displayName(for: profile.connectionProtocol)
                )
                if profile.authenticationType == .sshKey {
                    LabeledContent("Private key", value: profile.sshKeyPath ?? "Not set")
                }
                if profile.connectionProtocol == .rdp,
                   profile.authenticationType == .password {
                    LabeledContent(
                        "Keychain",
                        value: profile.keychainReference == nil ? "Not stored" : "Stored securely"
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", action: edit)
            }
        }
    }
}

struct CredentialProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let profile: CredentialProfile?
    private let onSave: ((CredentialProfile) -> Void)?

    @State private var name: String
    @State private var username: String
    @State private var domain: String
    @State private var connectionProtocol: ConnectionProtocol
    @State private var authenticationType: AuthenticationType
    @State private var sshKeyPath: String
    @State private var password = ""
    @State private var keychainErrorMessage = ""
    @State private var showingKeychainError = false

    private let keychainService = KeychainService.shared

    init(
        profile: CredentialProfile?,
        initialProtocol: ConnectionProtocol = .ssh,
        onSave: ((CredentialProfile) -> Void)? = nil
    ) {
        self.profile = profile
        self.onSave = onSave
        let resolvedProtocol = profile?.connectionProtocol ?? initialProtocol
        let availableMethods = AuthenticationType.availableMethods(for: resolvedProtocol)
        let resolvedMethod = profile.map(\.authenticationType).flatMap {
            availableMethods.contains($0) ? $0 : nil
        } ?? availableMethods[0]

        _name = State(initialValue: profile?.name ?? "")
        _username = State(initialValue: profile?.username ?? "")
        _domain = State(initialValue: profile?.domain ?? "")
        _connectionProtocol = State(initialValue: resolvedProtocol)
        _authenticationType = State(initialValue: resolvedMethod)
        _sshKeyPath = State(initialValue: profile?.sshKeyPath ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Profile name", text: $name, prompt: Text(profileNamePrompt))
                    Picker("Protocol", selection: $connectionProtocol) {
                        Label("SSH", systemImage: "terminal").tag(ConnectionProtocol.ssh)
                        Label("RDP", systemImage: "display").tag(ConnectionProtocol.rdp)
                    }
                    .pickerStyle(.segmented)
                    .disabled(profile?.hasExplicitConnectionProtocol == true)
                    .onChange(of: connectionProtocol) { _, newValue in
                        authenticationType = AuthenticationType.availableMethods(for: newValue)[0]
                        domain = ""
                        password = ""
                        sshKeyPath = ""
                    }
                    if profile?.hasExplicitConnectionProtocol == true {
                        Text("A profile's protocol is fixed after creation so existing connections remain valid.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if profile != nil {
                        Text("This older profile has no protocol saved. Choose SSH or RDP once to finish upgrading it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Identity") {
                    TextField("Username", text: $username, prompt: Text(usernamePrompt))
                    if connectionProtocol == .rdp {
                        TextField("Domain (optional)", text: $domain, prompt: Text("CONTOSO"))
                    }
                    Text(identityHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Authentication") {
                    Picker("Method", selection: $authenticationType) {
                        ForEach(AuthenticationType.availableMethods(for: connectionProtocol)) { type in
                            Text(type.displayName(for: connectionProtocol)).tag(type)
                        }
                    }

                    authenticationFields
                }
            }
            .formStyle(.grouped)
            .navigationTitle(profile == nil ? "New \(connectionProtocol.displayName) Credential" : "Edit Credential")
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
        .frame(width: 520, height: 540)
        .alert("Unable to Save Credential", isPresented: $showingKeychainError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keychainErrorMessage)
        }
    }

    @ViewBuilder
    private var authenticationFields: some View {
        switch (connectionProtocol, authenticationType) {
        case (.rdp, .password):
            SecureField(
                profile?.keychainReference == nil
                    ? "Password"
                    : "New password (leave blank to keep current)",
                text: $password
            )
            .textContentType(.password)
            Text("The password is stored only in macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case (.rdp, .promptEveryTime):
            Text("Relay will ask for the RDP password whenever you connect.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case (.ssh, .sshKey):
            HStack {
                TextField("Private key path", text: $sshKeyPath, prompt: Text("~/.ssh/id_ed25519"))
                Button("Choose…", action: chooseSSHKey)
            }
            Text("Relay passes this path to macOS OpenSSH. The key itself is never imported or copied.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case (.ssh, .sshAgent):
            Text("macOS OpenSSH will use your running SSH agent and settings from ~/.ssh/config.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case (.ssh, .promptEveryTime):
            Text("OpenSSH will prompt inside the embedded terminal for a password, key passphrase, or verification code.")
                .font(.caption)
                .foregroundStyle(.secondary)

        default:
            EmptyView()
        }
    }

    private var profileNamePrompt: String {
        connectionProtocol == .ssh ? "Production SSH" : "Production RDP"
    }

    private var usernamePrompt: String {
        connectionProtocol == .ssh ? "william" : "william.p.burch"
    }

    private var identityHelp: String {
        if connectionProtocol == .ssh {
            return "SSH uses a username only. Leave it blank to use your OpenSSH configuration or a connection override."
        }
        return "RDP can use a username by itself or combine it with an optional Windows domain."
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if connectionProtocol == .rdp, authenticationType == .password {
            return profile?.keychainReference != nil || !password.isEmpty
        }
        if connectionProtocol == .ssh, authenticationType == .sshKey {
            return !sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func chooseSSHKey() {
        let panel = NSOpenPanel()
        panel.title = "Choose SSH Private Key"
        panel.prompt = "Choose"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        sshKeyPath = abbreviatedHomePath(url.path)
    }

    private func save() {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = profile == nil
        let target = profile ?? CredentialProfile(
            name: normalizedName,
            username: username,
            domain: connectionProtocol == .rdp ? nilIfEmpty(domain) : nil,
            connectionProtocol: connectionProtocol,
            authenticationType: authenticationType
        )
        var newlyCreatedKeychainReference: String?
        var obsoleteKeychainReference: String?

        do {
            if connectionProtocol == .rdp, authenticationType == .password {
                if !password.isEmpty {
                    let previousReference = target.keychainReference
                    target.keychainReference = try keychainService.savePassword(
                        password,
                        reference: target.keychainReference
                    )
                    if previousReference == nil {
                        newlyCreatedKeychainReference = target.keychainReference
                    }
                }
            } else if let reference = target.keychainReference {
                obsoleteKeychainReference = reference
                target.keychainReference = nil
            }

            target.name = normalizedName
            target.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            target.connectionProtocol = connectionProtocol
            target.domain = connectionProtocol == .rdp ? nilIfEmpty(domain) : nil
            target.authenticationType = authenticationType
            target.sshKeyPath = authenticationType == .sshKey ? nilIfEmpty(sshKeyPath) : nil

            if isNew { modelContext.insert(target) }
            try modelContext.save()
            if let obsoleteKeychainReference {
                try keychainService.deletePassword(reference: obsoleteKeychainReference)
            }
            onSave?(target)
            dismiss()
        } catch {
            if isNew {
                modelContext.delete(target)
                if let newlyCreatedKeychainReference {
                    try? keychainService.deletePassword(reference: newlyCreatedKeychainReference)
                }
            }
            keychainErrorMessage = error.localizedDescription
            showingKeychainError = true
        }
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func abbreviatedHomePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + String(path.dropFirst(home.count))
    }
}
