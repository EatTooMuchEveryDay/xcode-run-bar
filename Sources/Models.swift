import Foundation

enum WorkspaceRowState: String, Equatable {
    case idle = "Idle"
    case starting = "Starting"
    case running = "Running"
    case stopping = "Stopping"
    case succeeded = "Succeeded"
    case failed = "Failed"

    var isBusy: Bool {
        self == .starting || self == .running || self == .stopping
    }
}

struct WorkspaceSession: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    let schemeName: String
    let destinationName: String
    let modificationDate: Date
    var state: WorkspaceRowState

    var isBusy: Bool {
        state == .starting || state == .running || state == .stopping
    }
}

enum WorkspaceListState: Equatable {
    case loading
    case ready([WorkspaceSession])
    case xcodeNotRunning
    case noWorkspaces
    case automationPermissionNeeded
    case failed(String)
}

struct WorkspaceSnapshot {
    let raw: XBWorkspaceSnapshot
    let name: String
    let path: String
    let schemeName: String
    let destinationName: String
    let modificationDate: Date
}
