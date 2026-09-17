import SwiftData
import SwiftUI

struct CredentialManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var credentialProfiles: [CredentialProfile]

    @State private var selection: UUID?
    @State private var profileToEdit: CredentialProfile?
    @State private var showingNewProfile = false
    @State private var keychainErrorMessage = ""
    @State private var showingKeychainError = false

    private let keychainService = KeychainService.shared

    private var sortedProfiles: [CredentialProfile] {
        credentialProfiles.sorted {
            $0.sortOrder == $1.sortOrder
                ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                : $0.sortOrder < $1.sortOrder
        }
    }

    private var selectedProfile: CredentialProfile? {
        guard let selection else { return nil }
        return credentialProfiles.first { $0.id == selection }
    }

    var body: some View {
        NavigationSplitView {
            List(sortedProfiles, selection: $selection) { profile in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                        Text(profile.authenticationType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: icon(for: profile.authenticationType))
                }
                .tag(profile.id)
                .contextMenu {
                    Button("Edit") { profileToEdit = profile }
                    Divider()
                    Button("Delete", role: .destructive) { delete(profile) }
                }
            }
            .navigationTitle("Credentials")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProfile = true
                    } label: {
                        Label("New Credential Profile", systemImage: "plus")
                    }
                }
            }
            .overlay {
                if credentialProfiles.isEmpty {
                    ContentUnavailableView {
                        Label("No Credential Profiles", systemImage: "key")
                    } description: {
                        Text("Create a profile to reuse usernames and authentication settings.")
                    } actions: {
                        Button("New Profile") { showingNewProfile = true }
                    }
                }
            }
        } detail: {
            if let selectedProfile {
                CredentialProfileDetail(profile: selectedProfile) {
                    profileToEdit = selectedProfile
                }
            } else {
                ContentUnavailableView("Select a Credential Profile", systemImage: "key")
            }
        }
        .frame(minWidth: 680, minHeight: 440)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingNewProfile) {
            CredentialProfileEditorView(profile: nil)
        }
        .sheet(item: $profileToEdit) { profile in
            CredentialProfileEditorView(profile: profile)
        }
        .alert("Unable to Delete Credential", isPresented: $showingKeychainError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keychainErrorMessage)
        }
    }

    private func delete(_ profile: CredentialProfile) {
        do {
            if let reference = profile.keychainReference {
                try keychainService.deletePassword(reference: reference)
            }
            if selection == profile.id { selection = nil }
            modelContext.delete(profile)
        } catch {
            keychainErrorMessage = error.localizedDescription
            showingKeychainError = true
        }
    }

    private func icon(for type: AuthenticationType) -> String {
        switch type {
        case .password: "key.fill"
        case .sshKey: "doc.badge.key"
        case .sshAgent: "person.badge.key"
        case .promptEveryTime: "ellipsis.bubble"
        }
    }
}

private struct CredentialProfileDetail: View {
    let profile: CredentialProfile
    let edit: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("Name", value: profile.name)
                LabeledContent("Username", value: profile.username.isEmpty ? "Not set" : profile.username)
                LabeledContent("Domain", value: profile.domain ?? "Not set")
                LabeledContent("Authentication", value: profile.authenticationType.displayName)
            }

            if profile.authenticationType == .sshKey {
                Section("SSH Key") {
                    LabeledContent("Path", value: profile.sshKeyPath ?? "Not set")
                }
            }

            if profile.authenticationType == .password {
                Section("Password") {
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

private struct CredentialProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let profile: CredentialProfile?

    @State private var name: String
    @State private var username: String
    @State private var domain: String
    @State private var authenticationType: AuthenticationType
    @State private var sshKeyPath: String
    @State private var password = ""
    @State private var keychainErrorMessage = ""
    @State private var showingKeychainError = false

    private let keychainService = KeychainService.shared

    init(profile: CredentialProfile?) {
        self.profile = profile
        _name = State(initialValue: profile?.name ?? "")
        _username = State(initialValue: profile?.username ?? "")
        _domain = State(initialValue: profile?.domain ?? "")
        _authenticationType = State(initialValue: profile?.authenticationType ?? .promptEveryTime)
        _sshKeyPath = State(initialValue: profile?.sshKeyPath ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name", text: $name)
                    TextField("Username", text: $username)
                    TextField("Domain", text: $domain)
                }

                Section("Authentication") {
                    Picker("Method", selection: $authenticationType) {
                        ForEach(AuthenticationType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    if authenticationType == .sshKey {
                        TextField("Private key path", text: $sshKeyPath, prompt: Text("~/.ssh/id_ed25519"))
                    }

                    if authenticationType == .password {
                        SecureField(
                            profile?.keychainReference == nil ? "Password" : "New password (leave blank to keep current)",
                            text: $password
                        )
                        .textContentType(.password)

                        Text("Passwords are stored only in macOS Keychain. Authentication material is never saved in the profile database.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(profile == nil ? "New Credential Profile" : "Edit Credential Profile")
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
        .frame(width: 480, height: 470)
        .alert("Unable to Save Credential", isPresented: $showingKeychainError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(keychainErrorMessage)
        }
    }

    private func save() {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = profile ?? CredentialProfile(
            name: normalizedName,
            username: username,
            domain: nilIfEmpty(domain),
            authenticationType: authenticationType
        )

        do {
            if authenticationType == .password {
                if !password.isEmpty {
                    target.keychainReference = try keychainService.savePassword(
                        password,
                        reference: target.keychainReference
                    )
                }
            } else if let reference = target.keychainReference {
                try keychainService.deletePassword(reference: reference)
                target.keychainReference = nil
            }

            target.name = normalizedName
            target.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            target.domain = nilIfEmpty(domain)
            target.authenticationType = authenticationType
            target.sshKeyPath = authenticationType == .sshKey ? nilIfEmpty(sshKeyPath) : nil

            if profile == nil { modelContext.insert(target) }
            dismiss()
        } catch {
            keychainErrorMessage = error.localizedDescription
            showingKeychainError = true
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if authenticationType == .password {
            return profile?.keychainReference != nil || !password.isEmpty
        }
        return true
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
