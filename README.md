# Relay

Relay is a lightweight native macOS connection manager for organizing SSH and RDP
connections. It keeps remote workspaces, credentials, and gateway settings together in a
focused native app built for macOS.

![Relay app icon](Remote/Resources/RelayIcon.png)

The current build provides hierarchical groups, protocol-specific credential profiles,
search and editing, embedded SSH sessions with pop-out and full-screen modes, FreeRDP-based
RDP sessions, optional RD Gateway configuration, and MFA-friendly window recovery.

## Requirements

- macOS 14 or later
- Xcode with the macOS SDK
- Swift 5.9 or later

Open `Remote.xcodeproj` in Xcode and run the `Relay` application. `Package.swift`
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
deletes its Keychain item. The legacy Keychain service identifier remains stable across the
Relay rebrand so existing saved credentials continue to resolve.

## SSH

Relay runs `/usr/bin/ssh` in a native SwiftTerm terminal embedded in the selected connection
tab. A live session can move to its own window, enter macOS full screen, and return to Relay
without reconnecting. It supports a username, custom port, SSH key path, ssh-agent,
`~/.ssh/config`, ProxyJump, and server keepalive settings. Password, key-passphrase, and
verification-code prompts stay interactive inside the terminal. Authentication material and
Keychain references never enter process arguments or environment variables.

SSH and RDP credentials have separate creation flows. SSH profiles offer interactive prompt,
private-key, and ssh-agent/OpenSSH-config methods, and use a username without a Windows
domain. RDP profiles offer stored-Keychain-password and prompt-every-time methods with an
optional domain. Use the key menu in Relay's toolbar, or create a compatible profile directly
from a connection editor.

## RDP

`RDPService` launches Homebrew's `sdl-freerdp` in a separate native window. The prototype
supports username/password/domain authentication, prompt-every-time profiles, clipboard,
dynamic resizing, fullscreen, custom desktop dimensions, certificate trust-on-first-use,
and an optional RD Gateway with either shared or separate credentials. Passwords are read
from Keychain and sent through an anonymous standard-input pipe using FreeRDP's
`/args-from:stdin` interface; they never appear in operating-system process arguments,
temporary files, logs, or environment variables. Closing a Relay RDP tab or choosing
Disconnect terminates the associated FreeRDP process. While FreeRDP is running, **Show
Window** brings its windows forward after an external authentication or 2FA flow minimizes
them. Relay also clears the session status when the FreeRDP process exits and presents a
bounded, redacted in-memory error summary when connection setup fails. The summary is never
written to disk.
RD Gateway transport can be selected per connection: RPC, automatic detection, HTTP, or HTTP
without WebSockets. RPC is the compatibility default for classic Windows RD Gateway servers.
Known RD Gateway policy failures such as `E_PROXY_RAP_ACCESSDENIED` are translated into an
actionable message that distinguishes successful MFA from destination authorization.
FreeRDP success, disconnect, logoff, user-disconnect, and closed-window exit codes return the
connection to its idle state without presenting a failure alert.

## Protocol boundary

SSH session ownership and its embedded terminal controller are isolated from connection and
credential persistence. FreeRDP process management and argument construction remain isolated
behind `RDPService` so a later embedded RDP renderer can replace the external SDL window
without changing the connection, credential, or tab models.

## Stability and recovery

Relay explicitly saves connection, group, and credential edits before closing an editor.
Closing a tab, deleting a connection or group, or changing an open connection tears down any
associated SSH and RDP processes. Each FreeRDP launch owns an isolated process-and-pipe bundle,
so output from a previous process cannot be delivered to a reconnect. The embedded terminal
uses SwiftTerm 1.17, which includes bounded PTY buffering and process-lifecycle fixes.

If the persistent SwiftData store cannot open, Relay leaves it untouched and offers a clearly
marked temporary in-memory workspace instead of terminating at launch. Changes made in that
recovery workspace are intentionally not saved.
