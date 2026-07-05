import AppKit
import SwiftUI

final class StatusController: NSObject, ObservableObject, NSMenuDelegate {
    @Published var listState: WorkspaceListState = .loading

    private struct TrackedAction {
        let result: XBActionResult
        var stopRequested: Bool
        var pollFailureCount: Int
    }

    private let store: WorkspaceStore
    private let xcode: XcodeIntegration
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let menuItem = NSMenuItem()
    private var menuHostingView: NSHostingView<WorkspacePanelView>?
    private var snapshotsByPath: [String: WorkspaceSnapshot] = [:]
    private var rowStates: [String: WorkspaceRowState] = [:]
    private var trackedActions: [String: TrackedAction] = [:]
    private var pollTimer: Timer?

    init(store: WorkspaceStore, xcode: XcodeIntegration) {
        self.store = store
        self.xcode = xcode
        super.init()
    }

    func start() {
        configureStatusItem()
        updateMenuBarIcon()
    }

    func refreshWorkspaces() {
        listState = .loading

        do {
            let snapshots = try xcode.fetchWorkspaces()
            guard !snapshots.isEmpty else {
                snapshotsByPath = [:]
                listState = .noWorkspaces
                return
            }

            let ordered = store.orderedSnapshots(snapshots)
            NSLog("xcode-run-bar: refreshWorkspaces succeeded: \(ordered.count) workspace(s)")
            snapshotsByPath = Dictionary(uniqueKeysWithValues: ordered.map { ($0.path, $0) })
            let duplicateNames = duplicateWorkspaceNames(in: ordered)
            let sessions = ordered.map { snapshot in
                session(from: snapshot, showPath: duplicateNames.contains(snapshot.name))
            }
            listState = .ready(sessions)
        } catch XcodeIntegrationError.xcodeNotRunning {
            NSLog("xcode-run-bar: refreshWorkspaces failed: xcodeNotRunning")
            snapshotsByPath = [:]
            listState = .xcodeNotRunning
        } catch XcodeIntegrationError.automationPermissionNeeded {
            NSLog("xcode-run-bar: refreshWorkspaces failed: automationPermissionNeeded")
            listState = .automationPermissionNeeded
        } catch {
            let message = failureMessage(for: error)
            NSLog("xcode-run-bar: refreshWorkspaces failed: \(message)")
            listState = .failed(message)
        }
    }

    func focusWorkspace(path: String) {
        guard let snapshot = snapshotsByPath[path] else { return }
        do {
            try xcode.focus(snapshot.raw)
        } catch XcodeIntegrationError.automationPermissionNeeded {
            listState = .automationPermissionNeeded
        } catch {
            mark(path: path, as: .failed)
        }
    }

    func runWorkspace(path: String) {
        guard let snapshot = snapshotsByPath[path] else { return }

        switch state(for: path) {
        case .starting, .stopping:
            return
        case .running:
            rerunWorkspace(path: path, snapshot: snapshot)
            return
        case .idle, .succeeded, .failed:
            break
        }

        mark(path: path, as: .starting)

        do {
            let result = try xcode.run(snapshot.raw)
            trackedActions[path] = TrackedAction(result: result, stopRequested: false, pollFailureCount: 0)
            mark(path: path, as: .running)
            startPollingIfNeeded()
        } catch XcodeIntegrationError.automationPermissionNeeded {
            listState = .automationPermissionNeeded
        } catch {
            trackedActions[path] = nil
            mark(path: path, as: .failed)
        }
    }

    private func rerunWorkspace(path: String, snapshot: WorkspaceSnapshot) {
        trackedActions[path] = nil
        mark(path: path, as: .stopping)

        do {
            try xcode.stop(snapshot.raw)
            scheduleRun(path: path, after: 0.8)
        } catch XcodeIntegrationError.automationPermissionNeeded {
            listState = .automationPermissionNeeded
        } catch {
            mark(path: path, as: .failed)
        }
    }

    func stopWorkspace(path: String) {
        guard let snapshot = snapshotsByPath[path] else { return }
        trackedActions[path] = nil
        mark(path: path, as: .stopping)

        do {
            try xcode.stop(snapshot.raw)
            scheduleState(path: path, state: .idle, after: 1)
        } catch XcodeIntegrationError.automationPermissionNeeded {
            listState = .automationPermissionNeeded
        } catch {
            mark(path: path, as: .failed)
        }
    }

    func moveWorkspace(from source: String, to destination: String) {
        guard case .ready(let sessions) = listState else { return }
        guard let fromIndex = sessions.firstIndex(where: { $0.path == source }),
              let toIndex = sessions.firstIndex(where: { $0.path == destination }),
              fromIndex != toIndex else { return }

        var reordered = sessions
        let moved = reordered.remove(at: fromIndex)
        reordered.insert(moved, at: toIndex)
        store.saveVisibleOrder(reordered.map(\.path))
        listState = .ready(reordered)
    }

    func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        menu.delegate = self
        menu.addItem(menuItem)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshWorkspaces()
        updateMenuContent()
    }

    private func updateMenuContent() {
        let contentSize = WorkspacePanelView.contentSize(for: listState)
        if let menuHostingView {
            menuHostingView.rootView = WorkspacePanelView(controller: self)
            menuHostingView.frame = NSRect(origin: .zero, size: contentSize)
        } else {
            let hostingView = NSHostingView(rootView: WorkspacePanelView(controller: self))
            hostingView.frame = NSRect(origin: .zero, size: contentSize)
            menuHostingView = hostingView
            menuItem.view = hostingView
        }
    }

    private func pollActions() {
        guard !trackedActions.isEmpty else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }

        for (path, tracked) in trackedActions {
            do {
                let completed = try xcode.actionCompleted(tracked.result)
                if tracked.pollFailureCount > 0 {
                    trackedActions[path] = TrackedAction(result: tracked.result, stopRequested: tracked.stopRequested, pollFailureCount: 0)
                }
                guard completed else { continue }

                let status = try xcode.actionStatus(tracked.result)
                trackedActions[path] = nil

                switch status {
                case XBSchemeActionStatus.succeeded:
                    mark(path: path, as: .succeeded)
                    scheduleState(path: path, state: .idle, after: 2)
                default:
                    mark(path: path, as: .failed)
                }
            } catch {
                let failureCount = tracked.pollFailureCount + 1
                NSLog("xcode-run-bar: action polling failed for \(path); failureCount=\(failureCount)")

                if failureCount < 3 {
                    trackedActions[path] = TrackedAction(result: tracked.result, stopRequested: tracked.stopRequested, pollFailureCount: failureCount)
                    continue
                }

                trackedActions[path] = nil
                mark(path: path, as: .failed)
            }
        }
    }

    private func startPollingIfNeeded() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pollActions()
            }
        }
    }

    private func scheduleState(path: String, state: WorkspaceRowState, after delay: TimeInterval) {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.mark(path: path, as: state)
            }
        }
    }

    private func scheduleRun(path: String, after delay: TimeInterval) {
        Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.state(for: path) == .stopping else { return }
                self.mark(path: path, as: .idle)
                self.runWorkspace(path: path)
            }
        }
    }

    private func mark(path: String, as state: WorkspaceRowState) {
        rowStates[path] = state
        updateVisibleRows()
        updateMenuContent()
    }

    private func updateVisibleRows() {
        guard case .ready(let sessions) = listState else { return }
        let duplicateNames = duplicateWorkspaceNames(in: sessions)
        listState = .ready(sessions.map { session in
            var updated = session
            updated.state = state(for: session.path)
            return withDisplayPathIfNeeded(updated, duplicateNames: duplicateNames)
        })
    }

    private func failureMessage(for error: Error) -> String {
        if case XcodeIntegrationError.commandFailed(let message) = error {
            return message
        }
        return String(describing: error)
    }

    private func updateMenuBarIcon() {
        let image = NSImage(systemSymbolName: "hammer", accessibilityDescription: "xcode-run-bar")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func session(from snapshot: WorkspaceSnapshot, showPath: Bool) -> WorkspaceSession {
        WorkspaceSession(
            id: snapshot.path,
            name: snapshot.name,
            path: snapshot.path,
            schemeName: detailPrefix(for: snapshot, showPath: showPath),
            destinationName: snapshot.destinationName,
            modificationDate: snapshot.modificationDate,
            state: state(for: snapshot.path)
        )
    }

    private func withDisplayPathIfNeeded(_ session: WorkspaceSession, duplicateNames: Set<String>) -> WorkspaceSession {
        guard duplicateNames.contains(session.name), let snapshot = snapshotsByPath[session.path] else { return session }
        return self.session(from: snapshot, showPath: true)
    }

    private func detailPrefix(for snapshot: WorkspaceSnapshot, showPath: Bool) -> String {
        if showPath {
            return "\(shortPath(snapshot.path)) · \(snapshot.schemeName)"
        }
        return snapshot.schemeName
    }

    private func state(for path: String) -> WorkspaceRowState {
        rowStates[path] ?? .idle
    }

    private func duplicateWorkspaceNames(in snapshots: [WorkspaceSnapshot]) -> Set<String> {
        duplicateNames(snapshots.map(\.name))
    }

    private func duplicateWorkspaceNames(in sessions: [WorkspaceSession]) -> Set<String> {
        duplicateNames(sessions.map(\.name))
    }

    private func duplicateNames(_ names: [String]) -> Set<String> {
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return Set(counts.filter { $0.value > 1 }.map(\.key))
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
