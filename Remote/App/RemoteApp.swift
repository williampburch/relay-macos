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
        SSHSessionService.shared.disconnectAll()
    }
}

@main
struct RelayApp: App {
    @NSApplicationDelegateAdaptor(RelayApplicationDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let startupIssue: String?

    init() {
        do {
            modelContainer = try ConnectionStore.makePersistentContainer()
            startupIssue = nil
        } catch {
            let persistentStoreError = error.localizedDescription
            do {
                modelContainer = try ConnectionStore.makeInMemoryContainer()
                startupIssue = persistentStoreError
            } catch {
                fatalError("Unable to initialize Relay's recovery database: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RelayRootView(startupIssue: startupIssue)
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

private struct RelayRootView: View {
    let startupIssue: String?

    @State private var continuingTemporarily = false

    var body: some View {
        if let startupIssue, !continuingTemporarily {
            ContentUnavailableView {
                Label("Relay Couldn’t Open Its Data", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Your saved data was left untouched. Relay can continue with a temporary workspace, but changes will not be saved after you quit.\n\n\(startupIssue)")
                    .frame(maxWidth: 560)
            } actions: {
                Button("Continue Temporarily") {
                    continuingTemporarily = true
                }
                Button("Quit Relay") {
                    NSApp.terminate(nil)
                }
            }
        } else {
            MainView()
        }
    }
}
