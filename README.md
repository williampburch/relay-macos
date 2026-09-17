# Remote

Remote is a lightweight native macOS connection manager for organizing SSH and RDP
connections. The current build provides the connection library, hierarchical groups,
reusable credentials backed by macOS Keychain, optional RD Gateway configuration, search,
editing, working external SSH sessions, and a FreeRDP-based RDP prototype.

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

The RDP prototype requires FreeRDP's Homebrew package:

```sh
brew install freerdp
```

## Security boundary

The SwiftData store contains connection definitions and credential metadata only. A
credential profile has an opaque `keychainReference`; no password field exists in the data
model. Passwords are saved, retrieved, updated, and deleted through `KeychainService` using
macOS Security APIs. Items are device-local and available only while the Mac is unlocked.
Deleting a credential profile or changing it to a non-password authentication method also
deletes its Keychain item.

## SSH

`SSHService` delegates connections to `/usr/bin/ssh` and opens each session in Terminal. It
supports the resolved username, custom port, SSH key path, ssh-agent, `~/.ssh/config`,
ProxyJump, and server keepalive settings. A temporary executable launcher passes only
shell-quoted connection options and deletes itself as soon as it starts. Passwords and
Keychain references never enter the launcher, process arguments, or environment. Password
profiles use OpenSSH's interactive Terminal prompt in this first working version.

## RDP

`RDPService` launches Homebrew's `sdl-freerdp` in a separate native window. The prototype
supports username/password/domain authentication, prompt-every-time profiles, clipboard,
dynamic resizing, fullscreen, custom desktop dimensions, certificate trust-on-first-use,
and an optional RD Gateway with either shared or separate credentials. Passwords are read
from Keychain and written to FreeRDP's standard input; they never appear in process arguments,
temporary files, logs, or environment variables. Closing a Remote RDP tab or choosing
Disconnect terminates the associated FreeRDP process.

## Protocol boundary

`SSHService` and `RDPService` conform to a common session-launching interface. The SSH
implementation is isolated behind that interface so a future PTY-based tab can continue to
use OpenSSH. FreeRDP process management and argument construction remain isolated behind
`RDPService` so an embedded renderer can replace the external SDL window without changing
the connection, credential, or tab models.
