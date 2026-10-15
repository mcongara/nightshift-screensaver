# Night Shift · Claude Code screensaver

A dim screen showing the latest status of your Claude Code sessions, with optional
idle-sleep protection while the actual screensaver is active. The heading reads
“Shift.” when sessions exist. With no sessions, only “Night Shift”, “Idle.” and
the clock appear.

## Requirements

- Apple Silicon Mac (M series).
- macOS 15 or later. Tested locally on macOS 26.
- Python 3.9+ and local Claude Code with hooks enabled.
  Install Python from python.org or use your existing Homebrew installation.
  The prebuilt package does not require Xcode or compilation.

## Install

1. Extract the entire ZIP. Keep its folder structure intact.
2. Double-click `Install.command`. Terminal displays the installation result.
3. Select Night Shift in System Settings → Wallpaper → Screen Saver.
   You may need to expand Other → Show All.
4. Restart Claude Code sessions so they load the new hooks. Sessions that started
   before installation are not discovered retroactively.
5. Set an automatic start time or a Hot Corner to activate the screensaver.

Installation is per-user and does not require sudo. The installer backs up your
Claude settings and adds only Night Shift hooks, preserving other hooks.
Reinstalling does not duplicate its hooks. The TR and EN editions replace each
other; they use the same preferences, bridge and session data.

## Options and behavior

Options: text brightness, clock visibility, hidden project names, and keep awake.
On macOS Tahoe, the Options sheet can be delayed; reopen System Settings if needed.
The local bridge must be running to save preferences.

Keep awake prevents automatic display and system idle sleep only while the actual
screensaver is active. It releases protection on exit. A thumbnail or development
preview alone cannot enable protection. It does not prevent lid-close or manual
sleep, adjust physical display brightness, or change lock/password settings.

Only project folder names, tool types and last hook times are displayed. Prompts,
commands and conversation content are not collected. After 15 minutes without a
hook signal, status becomes unknown; a long silent operation can also appear
unknown. Sessions are hidden after 24 hours without a signal. “Response complete”
means the response ended, not necessarily that the overall task succeeded.

## Uninstall

Double-click `Uninstall.command`. This removes the screensaver, background helpers,
and only Night Shift's Claude hooks. Local data and settings backups remain.

## Test build

This package is ad-hoc signed, without a Developer ID signature or Apple
notarization. macOS may block a download received through a browser or messaging
app. The installer does not change security settings or remove quarantine flags.
If blocked, report the exact message to the maintainer.

The ZIP contains no personal Claude settings, credentials or session data.
The bridge binds only to 127.0.0.1:47831. No API key is needed.
