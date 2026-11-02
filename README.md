# ClipNest

A macOS menu bar clipboard manager, built as a CopyClip replacement with more features.

The interface is in Indonesian.

## Features

- **⇧⌘V** opens a popup with tabs for All, Text, Images, Files, Pinned and Snippets
- Fuzzy search, including text inside images (OCR)
- Click an item to paste it straight into the app you were using
- Keyboard shortcuts:

  | Key | Action |
  |---|---|
  | ↩ | Paste |
  | ⇧↩ | Paste as plain text |
  | ⌘1–⌘9 | Paste one of the first nine items |
  | ⌘P | Pin or unpin |
  | ⌘⌫ | Delete |
  | ⇥ | Switch tab |
  | esc | Close |

- Transform text before pasting: UPPER/lower case, pretty-print JSON, join lines,
  URL and Base64 encode/decode
- Privacy:
  - ignores data from password managers and items marked concealed or transient
  - pause recording
  - exclude specific apps
  - auto-delete history after a set number of days (pinned items are kept)
- Images pasted into a terminal (Ghostty, Terminal, iTerm2, Warp, kitty, Alacritty, WezTerm)
  are sent with Ctrl+V, so TUI apps such as Claude Code can read them

## Build

Requires macOS 13+ and a Swift toolchain (the Xcode Command Line Tools are enough).

```bash
./build.sh   # builds, signs and installs ~/Applications/ClipNest.app
```

`build.sh` signs with your Apple Development or Developer ID certificate when one is
available, so permissions survive rebuilds. Otherwise it uses an ad-hoc signature.

## Permissions

- **Accessibility** (System Settings → Privacy & Security → Accessibility) is needed for
  auto-paste. Without it, items are still copied to the clipboard and you press ⌘V yourself.

History is stored in `~/Library/Application Support/ClipNest`.
