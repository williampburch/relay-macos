import AppKit
import SwiftData
import SwiftUI

private enum RelayBrand {
    static let accent = Color(red: 0.15, green: 0.42, blue: 0.86)
}

@MainActor
final class RelayApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        RDPService.shared.disconnectAll()
    }
}

@main
struct RelayApp: App {
    @NSApplicationDelegateAdaptor(RelayApplicationDelegate.self) private var appDelegate

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
                .tint(RelayBrand.accent)
        }
        .modelContainer(modelContainer)
        .commands {
            SidebarCommands()
        }

        Settings {
            CredentialManagerView()
                .modelContainer(modelContainer)
                .frame(minWidth: 620, minHeight: 420)
                .tint(RelayBrand.accent)
        }
    }
}
