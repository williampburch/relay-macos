# FreeRDP bridge boundary

Milestone 4 proves RDP connectivity by launching Homebrew's `sdl-freerdp` through
`RDPService`. That process boundary provides keyboard, mouse, clipboard, dynamic resizing,
fullscreen, and RD Gateway support without linking FreeRDP into the main app target.

The future C/Swift bridge for embedded rendering belongs in this directory. It should replace
only the external process adapter while retaining `RDPService`, connection models, credential
resolution, and the rule that secrets move from Keychain directly into transient memory.
