import Foundation

final class WorkspaceStore {
    private let defaults: UserDefaults
    private let orderKey = "workspaceOrder"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func orderedSnapshots(_ snapshots: [WorkspaceSnapshot]) -> [WorkspaceSnapshot] {
        var order = loadOrder()
        let snapshotsByPath = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.path, $0) })

        if order.isEmpty {
            let initial = snapshots.sorted { lhs, rhs in
                if lhs.modificationDate == rhs.modificationDate {
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
                return lhs.modificationDate > rhs.modificationDate
            }
            saveOrder(initial.map(\.path))
            return initial
        }

        let knownPaths = Set(order)
        let newPaths = snapshots.map(\.path).filter { !knownPaths.contains($0) }
        if !newPaths.isEmpty {
            order.append(contentsOf: newPaths)
            saveOrder(order)
        }

        return order.compactMap { snapshotsByPath[$0] }
    }

    func saveVisibleOrder(_ visiblePaths: [String]) {
        let visibleSet = Set(visiblePaths)
        var remainingVisible = ArraySlice(visiblePaths)
        let existing = loadOrder()
        var updated: [String] = []

        for path in existing {
            if visibleSet.contains(path) {
                if let next = remainingVisible.popFirst() {
                    updated.append(next)
                }
            } else {
                updated.append(path)
            }
        }

        updated.append(contentsOf: remainingVisible)
        saveOrder(unique(updated))
    }

    private func loadOrder() -> [String] {
        defaults.stringArray(forKey: orderKey) ?? []
    }

    private func saveOrder(_ order: [String]) {
        defaults.set(unique(order), forKey: orderKey)
    }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
