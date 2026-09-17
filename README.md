# Remote

Remote is a lightweight native macOS connection manager for organizing SSH and RDP
connections. Milestone 1 provides the connection library, hierarchical groups, reusable
credential metadata, search, editing, and placeholder session tabs.

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

## Security boundary

The SwiftData store contains connection definitions and credential metadata only. A
credential profile has an opaque `keychainReference`; no password field exists in the data
model. Keychain creation, access-control policy, and secret CRUD belong to Milestone 2.

## Protocol boundary

`SSHService` and `RDPService` conform to a common session-launching interface. They are
deliberate Milestone 1 placeholders. SSH will delegate to macOS OpenSSH, and RDP will remain
isolated behind the FreeRDP bridge.
