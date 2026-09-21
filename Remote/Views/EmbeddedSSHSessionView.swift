import AppKit
import Combine
import SwiftTerm
import SwiftUI

@MainActor
final class SSHSessionService: ObservableObject {
    static let shared = SSHSessionService()

    @Published private(set) var activeConnectionIDs: Set<UUID> = []
    @Published private(set) var sessions: [UUID: SSHSessionController] = [:]

    func connect(
        to connection: Connection,
        credential: CredentialProfile?
    ) throws -> SSHSessionController {
        if let existing = sessions[connection.id], existing.isRunning {
            return existing
        }
        if let stale = sessions.removeValue(forKey: connection.id) {
            stale.disconnect()
        }

        let plan = try SSHCommandBuilder.makePlan(
            connection: connection,
            credential: credential
        )
        let connectionID = connection.id
        let controller = SSHSessionController(
            connectionID: connectionID,
            title: connection.name
        )
        controller.onTermination = { [weak self, weak controller] in
            guard let self, self.sessions[connectionID] === controller else { return }
            self.activeConnectionIDs.remove(connectionID)
            self.sessions.removeValue(forKey: connectionID)
        }
        sessions[connectionID] = controller
        controller.start(arguments: plan.arguments)
        activeConnectionIDs.insert(connectionID)
        return controller
    }

    func session(connectionID: UUID) -> SSHSessionController? {
        sessions[connectionID]
    }

    func disconnect(connectionID: UUID) {
        activeConnectionIDs.remove(connectionID)
        guard let controller = sessions.removeValue(forKey: connectionID) else { return }
        controller.disconnect()
    }

    func disconnectAll() {
        let controllers = sessions.values
        sessions.removeAll()
        activeConnectionIDs.removeAll()
        controllers.forEach { $0.disconnect() }
    }
}

@MainActor
final class SSHSessionController: NSObject, ObservableObject {
    enum Placement: Equatable {
        case embedded
        case windowed
        case fullScreen
    }

    let connectionID: UUID
    let terminalView: LocalProcessTerminalView

    @Published private(set) var placement: Placement = .embedded
    @Published private(set) var isRunning = false
    @Published private(set) var exitCode: Int32?

    var onTermination: (() -> Void)?

    private let sessionTitle: String
    private var detachedWindow: NSWindow?
    private var isTearingDown = false

    init(connectionID: UUID, title: String) {
        self.connectionID = connectionID
        self.sessionTitle = title
        terminalView = LocalProcessTerminalView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 600)
        )
        super.init()

        terminalView.processDelegate = self
        terminalView.nativeForegroundColor = NSColor(
            calibratedWhite: 0.88,
            alpha: 1
        )
        terminalView.nativeBackgroundColor = NSColor(
            calibratedRed: 0.055,
            green: 0.067,
            blue: 0.09,
            alpha: 1
        )
        terminalView.caretColor = .systemCyan
        terminalView.layer?.backgroundColor = terminalView.nativeBackgroundColor.cgColor
    }

    func start(arguments: [String]) {
        guard !isRunning else { return }
        exitCode = nil
        isTearingDown = false
        isRunning = true
        terminalView.startProcess(
            executable: "/usr/bin/ssh",
            args: arguments,
            execName: "ssh"
        )
    }

    func disconnect() {
        guard !isTearingDown else { return }
        isTearingDown = true
        onTermination = nil
        terminalView.processDelegate = nil
        if isRunning {
            terminalView.terminate()
        }
        isRunning = false
        closeDetachedWindow()
    }

    func popOut(fullScreen: Bool = false) {
        if let detachedWindow {
            detachedWindow.makeKeyAndOrderFront(nil)
            NSApp.activate()
            if fullScreen, !detachedWindow.styleMask.contains(.fullScreen) {
                detachedWindow.toggleFullScreen(nil)
            }
            return
        }

        terminalView.removeFromSuperview()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 980, height: 680))
        installTerminal(in: container)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(sessionTitle) — SSH"
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        detachedWindow = window
        placement = fullScreen ? .fullScreen : .windowed
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        if fullScreen {
            DispatchQueue.main.async {
                window.toggleFullScreen(nil)
            }
        }
    }

    func showDetachedWindow() {
        detachedWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func reattach() {
        closeDetachedWindow()
        placement = .embedded
    }

    func attach(to container: NSView) {
        guard placement == .embedded else { return }
        installTerminal(in: container)
        DispatchQueue.main.async { [weak terminalView] in
            terminalView?.window?.makeFirstResponder(terminalView)
        }
    }

    private func installTerminal(in container: NSView) {
        guard terminalView.superview !== container else { return }
        terminalView.removeFromSuperview()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private func closeDetachedWindow() {
        guard let detachedWindow else { return }
        detachedWindow.delegate = nil
        terminalView.removeFromSuperview()
        self.detachedWindow = nil
        detachedWindow.orderOut(nil)
        detachedWindow.close()
    }
}

extension SSHSessionController: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(
        source: LocalProcessTerminalView,
        newCols: Int,
        newRows: Int
    ) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        guard !title.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            detachedWindow?.title = "\(sessionTitle) — \(title)"
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !isTearingDown else { return }
            isRunning = false
            self.exitCode = exitCode
            onTermination?()
        }
    }
}

extension SSHSessionController: NSWindowDelegate {
    func windowWillEnterFullScreen(_ notification: Notification) {
        placement = .fullScreen
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if detachedWindow != nil {
            placement = .windowed
        }
    }

    func windowWillClose(_ notification: Notification) {
        terminalView.removeFromSuperview()
        detachedWindow = nil
        if !isTearingDown {
            placement = .embedded
        }
    }
}

struct EmbeddedSSHSessionView: NSViewRepresentable {
    @ObservedObject var controller: SSHSessionController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(
            calibratedRed: 0.055,
            green: 0.067,
            blue: 0.09,
            alpha: 1
        ).cgColor
        controller.attach(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.attach(to: nsView)
    }
}
