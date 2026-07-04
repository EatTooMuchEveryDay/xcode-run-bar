# xcode-run-bar

xcode-run-bar is a lightweight macOS menu bar tool that controls running Xcode workspaces without switching back to the Xcode IDE.

## Language

**Workspace Session**:
An open Xcode workspace or project document that can have its own active scheme and run destination.
_Avoid_: Xcode IDE instance, project window

**Active Workspace Session**:
The Workspace Session currently considered selected by Xcode, usually the frontmost Xcode workspace/project window.
_Avoid_: current project, foreground Xcode

**Scheme Action**:
A Xcode operation such as build, run, test, debug, clean, or stop performed against a Workspace Session.
_Avoid_: job, task

**Owned Action**:
A Scheme Action started by Xcode Run Bar and therefore tracked by Xcode Run Bar through the result object returned by Xcode scripting.
_Avoid_: current action, managed task

**External Action**:
A Scheme Action started outside Xcode Run Bar, such as from the Xcode UI or another tool, whose state Xcode Run Bar may not be able to reliably track. In the first version, Workspace Sessions without an Owned Action are presented as idle rather than unknown.
_Avoid_: manual action, untracked task

**Command Feedback**:
A short-lived state shown after Xcode Run Bar sends a command, such as starting, stopping, or succeeded, before the UI returns to its steady state.
_Avoid_: real action state, confirmed state

**Last Used Workspace Session**:
The Workspace Session most recently selected for a Run command in Xcode Run Bar. This term is not used for first-version ordering; workspace order is user-controlled after initial discovery.
_Avoid_: default workspace, favorite project

**Workspace Order**:
A persisted relative order of Workspace Session paths. On first discovery it is initialized by each `.xcworkspace` or `.xcodeproj` document path's last modified time descending; after that, Xcode Run Bar preserves the relative order, manual dragging updates that relative order, newly discovered Workspace Sessions are appended, and missing paths are not actively cleaned.
_Avoid_: recent workspace order, last used order
