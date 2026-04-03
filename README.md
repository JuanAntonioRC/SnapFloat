# SnapFloat

A lightweight macOS menu-bar screenshot tool. Select a region, get a floating preview, annotate, copy or save — all without leaving your workflow.

**[Download the latest release](https://github.com/JuanAntonioRC/SnapFloat/releases/latest)**

> Requires **macOS 13 (Ventura)** or later.

---

## Install

1. Download **`SnapFloat-x.x.dmg`** from the [Releases page](https://github.com/JuanAntonioRC/SnapFloat/releases/latest).
2. Open the `.dmg` and drag **SnapFloat** into **Applications**.
3. Launch it — the app lives in the **menu bar** (no Dock icon).
4. Grant **Screen Recording** when macOS prompts you.
5. Press **⇧⌘2** to capture.

---

## What it does

- **Region capture** — press **⇧⌘2** (or your custom shortcut) and drag on any screen. A dimmed overlay shows the selection with a live size label.
- **Multi-monitor** — the overlay appears on all connected displays. Click and drag on whichever screen you want.
- **Floating preview** — a small thumbnail appears on the screen where you captured. It auto-dismisses after a configurable duration.
- **Quick actions** — from the preview: **Copy** to clipboard, **Save** to disk, or **click** to open the annotation editor.
- **Annotation editor** — draw on your screenshot with **Pen**, **Line**, **Arrow**, **Rectangle**, **Oval**, or **Text**. Adjustable stroke width, 7 colors. The window is resizable and preserves the image aspect ratio.
- **Auto-actions** — configure what happens the moment you capture: copy to clipboard, save to a folder, both, or nothing.
- **Configurable shortcut** — change the hotkey in Settings. Uses Carbon hotkeys so no Accessibility permission is needed.
- **Launch at login** — toggle in Settings.
- **Save notifications** — when saving to disk, a notification with **Show in Finder** appears.

---

## Settings

Open from the menu bar or press **⌘,** when the menu is visible.

| Option | Description |
|--------|-------------|
| **Shortcut** | Click the field and press your key combination. |
| **On capture** | What happens immediately after capturing (copy / save / both / nothing). |
| **Preview duration** | How long the thumbnail stays visible (1–30 seconds). |
| **Save location** | Folder for saved screenshots. Required for the Save button. |
| **Launch at login** | Start SnapFloat when you log in. |

---

## Build from source

```bash
git clone https://github.com/JuanAntonioRC/SnapFloat.git
cd SnapFloat
open SnapFloat.xcodeproj
```

Select the **SnapFloat** scheme, pick your Mac as the destination, and hit **⌘R**.

To build a DMG locally:

```bash
./scripts/build-dmg.sh
```

---

## Privacy

- **Screen Recording** permission is required for capturing.
- The global shortcut uses **Carbon** (`RegisterEventHotKey`) — **Accessibility permission is not needed**.
- SnapFloat is fully local. No data is sent to any server. Images only go to the clipboard or a folder you choose.

---

## Contributing

Issues and pull requests are welcome. If you're changing capture or permission-related code, test after resetting Screen Recording consent to make sure repeated permission dialogs don't resurface.

---

## License

[MIT License](LICENSE) — free to use, modify, and distribute.

---

<details>
<summary><strong>Architecture (for contributors)</strong></summary>

### Flow

```
App launch
  → AppDelegate: status item, prepareCapture(), HotkeyManager, notification setup
Hotkey / menu → Capture Area
  → CaptureOverlayWindow (one per screen, high window level)
  → CaptureOverlayView: selection rect → global screen coords
  → ScreenCaptureManager.capture(rect:)
      → performCaptureAction (clipboard / disk)
      → ThumbnailWindowController (preview on capture screen)
            → Copy / Save / click → AnnotationWindowController
```

### Key files

| File | Role |
|------|------|
| `AppDelegate.swift` | Status item, hotkey wiring, menu, notification delegate. |
| `HotkeyManager.swift` | Carbon hotkey registration with configurable key + modifiers. |
| `SettingsManager.swift` | UserDefaults for all preferences; capture action and save logic. |
| `SettingsWindowController.swift` | Preferences window with shortcut recorder. |
| `CaptureOverlayWindow.swift` | Borderless overlays on all screens; crosshair cursor. |
| `CaptureOverlayView.swift` | Selection drawing, coordinate conversion, Escape to cancel. |
| `ScreenCaptureManager.swift` | Cached SCDisplay map; ScreenCaptureKit API (macOS 14+ / 13 fallback). |
| `ThumbnailWindowController.swift` | Floating preview panel with Copy/Save strip. |
| `AnnotationWindowController.swift` | Drawing canvas with 6 tools, color palette, width slider. |

### Technical notes

- Overlay uses a **flipped coordinate system** (origin top-left); converted to AppKit screen coords before capture.
- Capture dimensions use the screen's **`backingScaleFactor`** for Retina-accurate bitmaps.
- A **60 ms delay** after dismissing the overlay prevents capturing the dimmer itself.
- `showsCursor = false` keeps the pointer out of screenshots.
- `SCDisplay` objects are **cached at launch** to avoid repeated permission dialogs on macOS 14/15.

</details>
