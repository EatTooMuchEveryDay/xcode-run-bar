import Foundation

enum XcodeIntegrationError: Error {
    case xcodeNotRunning
    case automationPermissionNeeded
    case commandFailed(String)
}

final class XcodeIntegration {
    private let bridge = XcodeBridge()

    var isXcodeRunning: Bool {
        bridge.isXcodeRunning
    }

    func fetchWorkspaces() throws -> [WorkspaceSnapshot] {
        do {
            return try bridge.fetchWorkspaces().map { snapshot in
                WorkspaceSnapshot(
                    raw: snapshot,
                    name: snapshot.name,
                    path: snapshot.path,
                    schemeName: snapshot.schemeName,
                    destinationName: snapshot.destinationName,
                    modificationDate: snapshot.modificationDate
                )
            }
        } catch {
            throw map(error)
        }
    }

    func run(_ workspace: XBWorkspaceSnapshot) throws -> XBActionResult {
        do {
            return try bridge.runWorkspace(workspace)
        } catch {
            throw map(error)
        }
    }

    func stop(_ workspace: XBWorkspaceSnapshot) throws {
        do {
            try bridge.stopWorkspace(workspace)
        } catch {
            throw map(error)
        }
    }

    func focus(_ workspace: XBWorkspaceSnapshot) throws {
        do {
            try bridge.focusWorkspace(workspace)
        } catch {
            throw map(error)
        }
    }

    func actionCompleted(_ result: XBActionResult) throws -> Bool {
        do {
            return try bridge.completedValue(forAction: result).boolValue
        } catch {
            throw map(error)
        }
    }

    func actionStatus(_ result: XBActionResult) throws -> XBSchemeActionStatus {
        do {
            let value = try bridge.statusValue(forAction: result).intValue
            return XBSchemeActionStatus(rawValue: value) ?? .errorOccurred
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> XcodeIntegrationError {
        let nsError = error as NSError
        NSLog("xcode-run-bar: integration error domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)")
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            NSLog("xcode-run-bar: underlying error domain=\(underlying.domain) code=\(underlying.code) description=\(underlying.localizedDescription)")
        }

        guard nsError.domain == XBErrorDomain else {
            return .commandFailed(message(for: nsError))
        }

        switch nsError.code {
        case XBErrorCode.xcodeNotRunning.rawValue:
            return .xcodeNotRunning
        case XBErrorCode.automationPermissionNeeded.rawValue:
            return .automationPermissionNeeded
        default:
            return .commandFailed(message(for: nsError))
        }
    }

    private func message(for error: NSError) -> String {
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return "\(underlying.domain) \(underlying.code): \(underlying.localizedDescription)"
        }
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
