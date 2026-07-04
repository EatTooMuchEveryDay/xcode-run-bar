# Xcode Run Bar

A lightweight macOS menu bar app for running, stopping, and focusing open Xcode workspaces without switching back to Xcode.

## Features

- Lists currently open Xcode workspaces and projects.
- Shows the active scheme and run destination for each workspace.
- Provides per-workspace Focus, Run, and Stop actions.
- Keeps a user-controlled workspace order.
- Runs as a menu bar app without a Dock icon.

## Requirements

- macOS 14 or later
- Xcode

## Build

```sh
xcodebuild -project xcode-run-bar.xcodeproj -scheme xcode-run-bar -configuration Release -derivedDataPath .build build
```

The app will be built at:

```text
.build/Build/Products/Release/xcode-run-bar.app
```

## Permissions

The first time Xcode Run Bar reads or controls Xcode, macOS may ask for Automation permission. If permission is denied, open System Settings → Privacy & Security → Automation and allow Xcode Run Bar to control Xcode.

## License

MIT
