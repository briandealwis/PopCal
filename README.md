# PopCal 🗓️

A lightweight macOS menubar calendar app. Lives in your system tray, shows the current month in a clean popover, and stays out of your way.

## Features

- **Menubar icon** — click to show/hide the calendar popover
- **Global hotkey** — configurable keyboard shortcut (default: ⌘Space) to summon the calendar from anywhere
- **Month navigation** — swipe up/down on the calendar, or use the chevron buttons, to navigate months
- **Today highlighting** — today's date is always clearly marked with your accent color
- **Configurable week start** — choose Sunday or Monday as the first day of the week
- **Settings** — right-click or ⌘-click the menubar icon to access settings
- **Dark/Light mode** — respects your system appearance

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15 or later

## Setup

### 1. Open in Xcode

```bash
open PopCal.xcodeproj
```

### 2. Configure Signing

In Xcode:
- Select the **PopCal** target
- Go to **Signing & Capabilities**
- Set your **Team** to your Apple Developer account (or use Personal Team for local builds)

### 3. Build & Run

Press **⌘R** in Xcode. The app will appear in your menubar — no Dock icon.

### 4. (Optional) Launch at Login

To have PopCal start automatically:
- Open **System Settings → General → Login Items**
- Add PopCal to the list

---

## Usage

| Action | Result |
|--------|--------|
| Click menubar icon | Show/hide calendar popover |
| Right-click or ⌘-click icon | Open context menu |
| Swipe up on calendar | Go to next month |
| Swipe down on calendar | Go to previous month |
| Click chevrons | Navigate months |
| Click "Today" (footer) | Jump back to current month |
| Global hotkey (default ⌘Space) | Show calendar from anywhere |

## Settings

Open Settings via the context menu (right-click or ⌘-click the menubar icon):

- **Week starts on** — Sunday or Monday
- **Enable hotkey** — toggle the global shortcut on/off
- **Shortcut** — click "Record" and press any key combination to set a new hotkey

## Architecture

```
PopCal/
├── PopCalApp.swift        — App entry point (@main)
├── AppDelegate.swift      — Menubar icon, popover, hotkey registration
├── AppPreferences.swift   — UserDefaults-backed settings (ObservableObject)
├── CalendarView.swift     — Main calendar UI with swipe navigation
├── SettingsView.swift     — Settings window
└── Info.plist             — LSUIElement=true (no Dock icon)
```

## Customization

### Changing the default hotkey

Edit `AppPreferences.swift`:
```swift
hotkeyKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? 49 // 49 = Space
let rawMods = ... ?? NSEvent.ModifierFlags.command.rawValue // change default modifiers
```

Common key codes: `Space=49`, `Return=36`, letters A-Z use the key codes in `keyCodeToString()`.

### Changing the popover size

Edit `AppDelegate.swift`:
```swift
popover?.contentSize = NSSize(width: 300, height: 320)
```

And `CalendarView.swift`:
```swift
.frame(width: 300, height: 320)
```

---

## Notes

- The app uses `LSUIElement = true` to hide from the Dock
- Sandboxing is disabled (required for global hotkeys via Carbon `RegisterEventHotKey`)
- Settings are persisted via `UserDefaults`
- The global hotkey uses the Carbon Event Manager API, which requires a non-sandboxed app
