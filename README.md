# TN3270Mac

A native Mac terminal emulator for connecting to IBM mainframes over TN3270 and
TN3270E. Connect to your host, work with familiar 3270 screens, and use Mac-style
text selection and copying.

## Features

- Secure connections with SSL/TLS and server certificate verification.
- Support for TN3270 and TN3270E, including optional LU names.
- Terminal models 2, 3, 4 and 5, with extended colors and highlighting.
- Multiple EBCDIC code pages for different host languages.
- Customizable keyboard shortcuts for Enter, PF keys, PA keys and other
  mainframe functions.
- Mouse-drag and Shift+Arrow text selection, including rectangular block selection, with Cmd+C to copy.
- Saved connection settings and keyboard mappings.

## Requirements

- macOS 13 Ventura or later.
- An Apple Silicon Mac (M-series) for the currently available download.
- Access to a TN3270/TN3270E host and its connection details. You may need your
  organization's network or VPN.

No Xcode or developer tools are needed to install the downloaded app.

## Install

1. Open the [Releases page](https://github.com/mradrianhh/TN3270-Mac/releases).
2. Download the **TN3270Mac** ZIP from the release's **Assets** section
   (for example, **TN3270Mac-v1.0.3-arm64.zip**), not the source-code archives.
3. Double-click the ZIP in Finder to extract it.
4. Drag **TN3270Mac.app** into **Applications**.
5. Open **TN3270Mac** from Applications.

The current release is an **alpha**, so expect rough edges.

### If macOS blocks the app

The current download is ad-hoc signed, not Developer ID signed or notarized by
Apple. macOS may warn that it cannot verify the developer.

Only if you trust the download from this repository, try opening the app, then
go to **System Settings > Privacy & Security** and look for **Open Anyway**.
Follow the confirmation prompts. On a managed Mac, your organization's security
policy may prevent this; contact your administrator rather than disabling
security protections.

## Connect to a mainframe

1. Open **Connection > Connection Options**.
2. Enter the host name or IP address and port supplied by your administrator.
3. Set SSL/TLS, terminal model, EBCDIC code page and optional LU name to match
   your host. Keep **Verify server certificate** enabled for secure connections.
4. Click **Save & Connect**.

The status bar shows the session status. Use the toolbar or the **Connection**
menu to connect or disconnect.

## Keyboard and copying

| Action | Mac shortcut |
| --- | --- |
| Send Enter to the host | Return or keypad Enter |
| New Line (move to the first editable position on the next row, searching onward if needed) | Shift+Return |
| Move to the next / previous input field | Tab / Shift+Tab |
| PF1-PF12 | F1-F12 |
| PF13-PF24 | Shift+F1-F12 |
| PF7 / PF8 | Page Up / Page Down |
| Clear | Esc |
| Reset the keyboard | Control+R |
| Select text | Drag with the mouse or hold Shift and use the arrow keys |
| Toggle block selection (on by default) | Option+Cmd+B, or hold Option while dragging |
| Copy selected text | Cmd+C |

Without a selection, Copy copies the whole screen. **Control+C sends Attention
to the host**; use Cmd+C to copy.

Open **Keyboard > Keyboard Options** to customize host key mappings. Depending
on your Mac's keyboard settings, you may need to hold **Fn** to use function keys.

## Update

Quit TN3270Mac, download and extract the newer release, then replace the app in
Applications. If you installed an earlier build named **TN3270**, remove that
older app to avoid keeping two copies.

## Help and development

### Query Monitor reports CQM244E

The emulator reports the EBCDIC code page selected in **Connection Options**
through the 3270 Character Sets query reply. After updating the app, reconnect
and start a new ISPF session so ISPF can query the terminal again.

For compatibility, code page **277** is reported to the host as **1142**,
but text translation remains 277. Select **1142** explicitly to enable Euro
character translation as well.

In ISPF **7.3 (Dialog Test > Variables)**, check `ZTERMCID`, `ZTERMCP`,
`ZTERMCP5`, `ZTERMCS` and `ZTERMCS5`. If the terminal CCSID is still blank or zero,
ask your host administrator to check VTAM/LOGMODE query support. See
[IBM's CQM244E troubleshooting guidance](https://www.ibm.com/support/pages/cqm244e-unable-determine-terminal-ccsid-coded-character-set-identifier-ccsid-terminal-cannot-be-determined).

### Reporting issues

Report bugs or request features on the
[Issues page](https://github.com/mradrianhh/TN3270-Mac/issues). Include your macOS
version and app version, but do not share passwords or sensitive host data.

For building from source, testing, release packaging and protocol details, see
the [Developer Guide](docs/DEVELOPMENT.md).
