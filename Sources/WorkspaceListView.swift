import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WorkspacePanelView: View {
    @ObservedObject var controller: StatusController

    static func contentSize(for state: WorkspaceListState) -> NSSize {
        WorkspaceListView.contentSize(for: state)
    }

    var body: some View {
        WorkspaceListView(controller: controller)
            .frame(width: Self.contentSize(for: controller.listState).width, height: Self.contentSize(for: controller.listState).height)
            .background(Color.clear)
    }
}

struct WorkspaceListView: View {
    static let width: CGFloat = 440
    static let rowHeight: CGFloat = 56
    static let rowSlotHeight: CGFloat = 56
    static let footerHeight: CGFloat = 28
    static let headerHeight: CGFloat = 16
    static let minVisibleRows: CGFloat = 1
    static let maxVisibleRows: CGFloat = 6

    @ObservedObject var controller: StatusController
    @State private var draggingPath: String?

    static func contentSize(for state: WorkspaceListState) -> NSSize {
        NSSize(width: width, height: height(for: state))
    }

    static func height(for state: WorkspaceListState) -> CGFloat {
        listHeight(for: state) + headerHeight + footerHeight
    }

    private static func listHeight(for state: WorkspaceListState) -> CGFloat {
        let visibleRows: CGFloat
        switch state {
        case .ready(let sessions):
            visibleRows = min(max(CGFloat(sessions.count), minVisibleRows), maxVisibleRows)
        case .loading, .xcodeNotRunning, .noWorkspaces, .failed:
            visibleRows = minVisibleRows
        case .automationPermissionNeeded:
            visibleRows = 3
        }
        return visibleRows * rowSlotHeight
    }

    private var contentHeight: CGFloat {
        Self.listHeight(for: controller.listState)
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: Self.headerHeight)
            content
                .frame(height: contentHeight)
            footer
                .frame(height: Self.footerHeight)
        }
        .frame(width: Self.width, height: Self.height(for: controller.listState))
    }

    @ViewBuilder
    private var content: some View {
        switch controller.listState {
        case .loading:
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        case .ready(let sessions):
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sessions) { session in
                        WorkspaceRowView(session: session, controller: controller, draggingPath: $draggingPath)
                            .frame(height: Self.rowHeight)
                            .opacity(draggingPath == session.path ? 0.35 : 1)
                            .onDrop(of: [.plainText], delegate: WorkspaceDropDelegate(destination: session, controller: controller, draggingPath: $draggingPath))
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: sessions.map(\.path))
            }
            .background(ScrollViewStyleConfigurator())
        case .xcodeNotRunning:
            EmptyStateView(
                title: "Xcode is not running",
                message: "Open Xcode to see workspaces."
            )
        case .noWorkspaces:
            EmptyStateView(
                title: "No workspaces open",
                message: "Open a project or workspace in Xcode."
            )
        case .automationPermissionNeeded:
            EmptyStateView(
                title: "Automation permission needed",
                message: "Allow xcode-run-bar to control Xcode in System Settings.",
                buttonTitle: "Open System Settings",
                action: controller.openSystemSettings
            )
        case .failed(let message):
            EmptyStateView(
                title: "Could not read Xcode workspaces",
                message: message
            )
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Quit") {
                controller.quit()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 14)
    }
}

private struct WorkspaceRowView: View {
    let session: WorkspaceSession
    @ObservedObject var controller: StatusController
    @Binding var draggingPath: String?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            dragHandle

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(session.schemeName)
                    Text("·")
                    Text(session.destinationName)
                    Text("·")
                    Text(session.state.rawValue)
                        .foregroundStyle(stateColor)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                controller.focusWorkspace(path: session.path)
            } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .help("Focus Workspace")
            .buttonStyle(RowIconButtonStyle())

            Button {
                controller.stopWorkspace(path: session.path)
            } label: {
                Image(systemName: "stop.fill")
            }
            .help("Stop")
            .buttonStyle(RowIconButtonStyle())
            .opacity(stopOpacity)

            Button {
                controller.runWorkspace(path: session.path)
            } label: {
                Image(systemName: runButtonSymbolName)
            }
            .help(runButtonHelp)
            .buttonStyle(RowIconButtonStyle())
            .disabled(!canRun)
            .opacity(canRun ? 1 : 0.35)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .background(isHovering ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 34)
            .contentShape(Rectangle())
            .opacity(isHovering ? 1 : 0)
            .onDrag {
                draggingPath = session.path
                return NSItemProvider(object: session.path as NSString)
            } preview: {
                dragPreview
            }
    }

    private var dragPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                Text("\(session.schemeName) · \(session.destinationName) · \(session.state.rawValue)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)
        }
        .frame(width: WorkspaceListView.width - 28, height: WorkspaceListView.rowHeight)
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var runButtonSymbolName: String {
        session.state == .running ? "arrow.clockwise" : "play.fill"
    }

    private var runButtonHelp: String {
        session.state == .running ? "Rerun" : "Run"
    }

    private var canRun: Bool {
        session.state != .starting && session.state != .stopping
    }

    private var stateColor: Color {
        switch session.state {
        case .idle:
            return .secondary
        case .starting, .running, .stopping:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private var stopOpacity: Double {
        switch session.state {
        case .starting, .running, .stopping:
            return 1
        case .idle, .succeeded, .failed:
            return 0.45
        }
    }
}

private struct ScrollViewStyleConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureScrollView(near: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureScrollView(near: nsView)
        }
    }

    private func configureScrollView(near view: NSView) {
        guard let scrollView = findScrollView(from: view) else { return }
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
    }

    private func findScrollView(from view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        if let scrollView = view.enclosingScrollView {
            return scrollView
        }
        if let scrollView = view.superview.flatMap(findScrollViewInDescendants) {
            return scrollView
        }
        return view.window?.contentView.flatMap(findScrollViewInDescendants)
    }

    private func findScrollViewInDescendants(of view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollViewInDescendants(of: subview) {
                return scrollView
            }
        }
        return nil
    }
}

private struct RowIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowIconButton(configuration: configuration)
    }
}

private struct RowIconButton: View {
    let configuration: ButtonStyle.Configuration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(backgroundColor)
            .clipShape(Circle())
            .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.14)
        }
        if isHovering {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }
}

private struct EmptyStateView: View {
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .padding(.top, 6)
            }
            Spacer()
        }
        .padding(24)
    }
}

private struct WorkspaceDropDelegate: DropDelegate {
    let destination: WorkspaceSession
    let controller: StatusController
    @Binding var draggingPath: String?

    func dropEntered(info: DropInfo) {
        guard let draggingPath, draggingPath != destination.path else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            controller.moveWorkspace(from: draggingPath, to: destination.path)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingPath = nil
        return true
    }

    func dropExited(info: DropInfo) {
        guard !info.hasItemsConforming(to: [.plainText]) else { return }
        draggingPath = nil
    }
}
