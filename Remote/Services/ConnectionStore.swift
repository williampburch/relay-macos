import Foundation
import SwiftData

@MainActor
final class ConnectionStore {
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    init(inMemory: Bool = false) throws {
        let schema = Self.schema
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        let container = try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
        self.modelContainer = container
        self.modelContext = ModelContext(container)
    }

    init(container: ModelContainer) {
        self.modelContainer = container
        self.modelContext = ModelContext(container)
    }

    static var schema: Schema {
        Schema([
            Connection.self,
            ConnectionGroup.self,
            CredentialProfile.self
        ])
    }

    static func makePersistentContainer() throws -> ModelContainer {
        let schema = Self.schema
        let configuration = ModelConfiguration(schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static func makePreview(populated: Bool = true) throws -> ConnectionStore {
        let store = try ConnectionStore(inMemory: true)
        guard populated else { return store }

        let linux = ConnectionGroup(name: "Linux", sortOrder: 0)
        let windows = ConnectionGroup(name: "Windows", sortOrder: 1)
        let linuxAdmin = CredentialProfile(
            name: "Linux Admin",
            username: "admin",
            authenticationType: .sshAgent
        )
        linux.credentialProfile = linuxAdmin

        store.insert(linuxAdmin)
        store.insert(linux)
        store.insert(windows)
        store.insert(
            Connection(
                name: "APP01",
                host: "app01.example.test",
                connectionProtocol: .ssh,
                group: linux
            )
        )
        store.insert(
            Connection(
                name: "DC01",
                host: "dc01.example.test",
                connectionProtocol: .rdp,
                group: windows,
                isFavorite: true
            )
        )
        try store.save()
        return store
    }

    func insert<Model: PersistentModel>(_ model: Model) {
        modelContext.insert(model)
    }

    func delete<Model: PersistentModel>(_ model: Model) {
        modelContext.delete(model)
    }

    func save() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    func fetchGroups() throws -> [ConnectionGroup] {
        let descriptor = FetchDescriptor<ConnectionGroup>(
            sortBy: [
                SortDescriptor(\ConnectionGroup.sortOrder),
                SortDescriptor(\ConnectionGroup.name)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchRootGroups() throws -> [ConnectionGroup] {
        try fetchGroups().filter { $0.parent == nil }
    }

    func fetchConnections() throws -> [Connection] {
        let descriptor = FetchDescriptor<Connection>(
            sortBy: [
                SortDescriptor(\Connection.sortOrder),
                SortDescriptor(\Connection.name)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func fetchCredentialProfiles() throws -> [CredentialProfile] {
        let descriptor = FetchDescriptor<CredentialProfile>(
            sortBy: [
                SortDescriptor(\CredentialProfile.sortOrder),
                SortDescriptor(\CredentialProfile.name)
            ]
        )
        return try modelContext.fetch(descriptor)
    }

    func searchConnections(query: String) throws -> [Connection] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return try fetchConnections() }

        return try fetchConnections().filter { connection in
            connection.name.localizedCaseInsensitiveContains(normalizedQuery)
                || connection.host.localizedCaseInsensitiveContains(normalizedQuery)
                || connection.notes?.localizedCaseInsensitiveContains(normalizedQuery) == true
                || groupNames(for: connection.group).contains {
                    $0.localizedCaseInsensitiveContains(normalizedQuery)
                }
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
