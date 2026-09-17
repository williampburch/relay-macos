# Remote Development Rules

- This repository contains a native macOS application built with Swift and SwiftUI.
- Use AppKit only where SwiftUI is insufficient.
- Do not introduce Electron, Chromium, React, or another web application stack.
- Never persist passwords or secrets outside macOS Keychain.
- Never log passwords, secrets, or authentication material.
- SSH integrations must use macOS OpenSSH unless explicitly approved otherwise.
- RDP integrations must use FreeRDP unless explicitly approved otherwise.
- Prefer native macOS APIs and avoid unnecessary dependencies.
- Keep UI, persistence, credentials, SSH, and RDP integrations modular.
- Do not add unrelated remote-management protocols.
- Run a full build before declaring work complete. Fix compiler errors instead of leaving build-breaking placeholders.
- Add focused tests for security-sensitive and persistence logic where practical.
- Preserve user changes and keep commits logically scoped.
