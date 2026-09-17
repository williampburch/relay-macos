import AppKit
import SwiftData
import SwiftUI

@MainActor
final class RemoteApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        RDPService.shared.disconnectAll()
    }
}

@main
struct RemoteApp: App {
    @NSApplicationDelegateAdaptor(RemoteApplicationDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ConnectionStore.makePersistentContainer()
        } catch {
            fatalError("Unable to initialize the application database: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 920, minHeight: 600)
        }
        .modelContainer(modelContainer)
        .commands {
            SidebarCommands()
        }

        Settings {
            CredentialManagerView()
                .modelContainer(modelContainer)
                .frame(minWidth: 620, minHeight: 420)
        }
    }
}
