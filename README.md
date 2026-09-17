# Remote

Remote is a lightweight native macOS connection manager for organizing SSH and RDP
connections. Milestone 1 provides the connection library, hierarchical groups, reusable
credential metadata, optional RD Gateway configuration, search, editing, and placeholder
session tabs.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- Swift 5.9 or later

Open `Remote.xcodeproj` in Xcode and run the `Remote` application scheme. `Package.swift`
provides the same source tree for command-line validation. From a terminal with the full
Xcode developer directory selected, run:

```sh
swift build
swift test
```

If `xcode-select -p` still reports `/Library/Developer/CommandLineTools` after installing
Xcode, select the full installation and complete its first-launch setup:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

FreeRDP is not required to work on Milestones 1–3. Install its Homebrew package before the
RDP prototype milestone:

```sh
brew install freerdp
```

## Security boundary

The SwiftData store contains connection definitions and credential metadata only. A
credential profile has an opaque `keychainReference`; no password field exists in the data
model. Keychain creation, access-control policy, and secret CRUD belong to Milestone 2.

## Protocol boundary

`SSHService` and `RDPService` conform to a common session-launching interface. They are
deliberate Milestone 1 placeholders. SSH will delegate to macOS OpenSSH, and RDP will remain
isolated behind the FreeRDP bridge. Each RDP connection may specify an RD Gateway host, port,
and optional gateway credential profile; omitting the gateway profile reuses the connection's
resolved credential profile.
