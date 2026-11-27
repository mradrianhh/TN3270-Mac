# TN3270Mac Developer Guide

A native macOS TN3270 terminal emulator for connecting to IBM z/OS systems.

For installation and everyday use, see the [app guide](../README.md).
Run the commands below from the repository root.

## Features

- **TN3270E** (RFC 2355) with device-type/LU negotiation, BIND-IMAGE, RESPONSES and
  SYSREQ functions, with automatic fallback to traditional **TN3270** (RFC 1576/1646).
- **SSL/TLS** via Network.framework — TLS 1.3 is the default minimum version
  (TLS 1.2 can be selected for older hosts), with optional certificate verification
  bypass for self-signed / private CA certificates.
- 3270 data stream: Write, Erase/Write, Erase/Write Alternate, Read Buffer, Read
  Modified (All), Erase All Unprotected, Write Structured Field (Read Partition
  Query, Erase/Reset, Outbound 3270DS) and all orders (SF, SFE, SBA, SA, MF, IC,
  PT, RA, EUA, GE), extended colors and highlighting.
- Terminal models 2 (24×80), 3 (32×80), 4 (43×80) and 5 (27×132).
- Terminal sizing uses the view's safe area and final rounded cell dimensions
  to keep every row clear of the title bar and status area.
- Field-attribute positions remain blank without reverse video or background
  color, preserving separators between highlighted fields.
- EBCDIC code pages 037, 273, 277, 278, 280, 284, 285, 297, 500, 1047 and the
  Euro variants 1140–1148.
- Read Partition Query and Query List report Character Sets (`0x85`) with
  the configured code page's CGCSGID (GCSGID 697, or 695 for Euro variants).
  Only the base single-byte set (LCID 0) is advertised, not APL or DBCS.
  Query List supports List, Equivalent+List and All; unsupported lists return
  a Null reply.
- Compatibility exception: selecting 277 advertises the Euro-capable 1142
  CGCSGID (GCSGID 695, CPGID 1142), while retaining 277 translation. Select
  1142 explicitly when Euro-aware encoding and decoding are also needed.
- **Connection Options** window (Connection ▸ Connection Options…, ⇧⌘,): host /
  IP address, port, EBCDIC code page, terminal model, LU name, TN3270E and TLS.
- **Keyboard Options** window (Keyboard ▸ Keyboard Options…, ⌥⌘K): map any Mac
  key combination to a 3270 function (Enter, Clear, PF1–PF24, PA1–PA3, Attn,
  SysReq, Reset, Erase EOF, Insert, field tab, …). Mappings are saved
  automatically.
- **Text selection**: drag with the mouse or hold Shift and use the arrow keys,
  then press Cmd+C to copy the highlighted text. Selection is local and needs no
  host key mapping. Without a selection, Copy continues to copy the whole screen.
- **Block selection** (Edit ▸ Block Selection, ⌥⌘B, on by default): selects a
  rectangle of cells instead of a run of text, and copies one line per row. The
  status bar shows BLOCK while it is on. Holding Option while dragging switches mode for
  that one selection. The setting is saved.

### Default key map

| Mac key | 3270 function |
| --- | --- |
| Return / keypad Enter | Enter |
| ⇧ Return | New Line |
| Tab / ⇧ Tab | Field Tab / Backtab |
| F1–F12 / ⇧ F1–F12 | PF1–PF12 / PF13–PF24 |
| Page Up / Page Down | PF7 / PF8 |
| Esc | Clear |
| ⌃R | Reset |
| ⌃C | Attention |
| ⌃S | System Request |
| ⌃1 / ⌃2 / ⌃3 | PA1 / PA2 / PA3 |
| End / ⌃E | Erase EOF |
| Help (Insert) / ⌃I | Insert mode |
| Home | Home |
| ⌫ / ⌦ | Backspace / Delete |

## Building and running

Requires macOS 13 or later and Xcode 15 (Swift 5.9) or later.

```sh
swift run TN3270Mac        # build and launch the app
swift test                 # run the unit tests
```

You can also open `Package.swift` in Xcode and run the `TN3270Mac` scheme.

### Release app for Applications

```sh
bash scripts/build-app.sh
open -R .build/release/TN3270Mac.app
```

Drag `TN3270Mac.app` from Finder into Applications, then launch it like any other
Mac app. Quit any running copy before replacing it with a newer build.

The script builds an optimized release for your Mac's architecture and packages
it as an app with an ad-hoc signature for local use. It does not require an Apple
Developer account. Distribution to other Macs requires separate Developer ID
signing and notarization for normal Gatekeeper approval.

Each successful run increments the patch number in [VERSION](../VERSION) (starting
from `1.0.2`, so the next build is `1.0.3`) and uses it for both app bundle version
fields. Edit the major/minor numbers in that file manually when needed; the patch
number is incremented on the next build. Failed builds do not advance the version.

The script also creates `releases/TN3270Mac-v<version>-<architecture>.zip`.
The ZIP contains only `TN3270Mac.app` (the executable, icon, metadata and signature),
not source code or other build files. Existing release ZIPs are never overwritten.
Generated ZIPs are ignored by Git; upload the ZIP as a GitHub release asset.

The app icon is generated from [Resources/AppIcon.png](../Resources/AppIcon.png) during packaging. To change
it, replace that image with a square PNG (ideally 1024 × 1024) and rebuild.

## Project layout

- [Sources/TN3270Core](../Sources/TN3270Core) – platform independent protocol engine: EBCDIC code pages,
  telnet/TN3270E negotiation, 3270 data stream processing, screen buffer,
  key map and the Network.framework TLS transport.
- [Sources/TN3270Mac](../Sources/TN3270Mac) – SwiftUI/AppKit macOS application (built on macOS only).
- [Tests/TN3270CoreTests](../Tests/TN3270CoreTests) – XCTest unit tests (run on macOS and Linux).
