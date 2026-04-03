# SnapFloat

**SnapFloat** is a lightweight macOS menu-bar utility for **region screenshots**: select an area on screen, get a floating thumbnail, then **copy**, **save to disk**, or **open a simple annotation editor** before copying or saving.

Built with **Swift**, **AppKit**, and **ScreenCaptureKit**. No Dock icon—only a status item and a **configurable** global shortcut (default **⇧⌘2**).

---

## Table of contents

- [Features](#features)
- [Settings](#settings)
- [Requirements](#requirements)
- [Permissions](#permissions)
- [How to use](#how-to-use)
- [Build from source](#build-from-source)
- [Architecture](#architecture)
- [Project layout](#project-layout)
- [Technical notes](#technical-notes)
- [Contributing](#contributing)
- [License](#license)

---

## Features

| Area | What it does |
|------|----------------|
| **Capture** | Full-screen overlay on the display under the cursor; drag to define a rectangle. Semi-transparent dimming outside the selection, live size label (e.g. `1920 × 1080`). |
| **Global shortcut** | **Configurable** in **Settings** (default **⇧⌘2**). Implemented with **Carbon** (`RegisterEventHotKey`) so **Accessibility** permission is **not** required for the hotkey. The menu bar shows the current shortcut next to **Capture Area**. |
| **Menu bar** | SF Symbol `camera.viewfinder`; **Capture Area** (with shortcut in the title), **Settings…** (⌘,), **Quit SnapFloat** (⌘Q). |
| **Settings** | **Shortcut** (click the field to record; combinations with **3 components** save automatically; **2-component** combos need **Save**). **On capture:** copy to clipboard / do nothing / save to folder / copy and save. **Preview duration** (1–30 s, default 5) for the thumbnail. **Save location** (optional folder + **Choose…**). **Launch at login** (`SMAppService`). |
| **Post-capture (immediate)** | Right after pixels are captured, **`SettingsManager.performCaptureAction`** runs according to **On capture** (clipboard and/or PNG under the chosen folder). File names look like `SnapFloat_yyyy-MM-dd_HH-mm-ss.png`. |
| **Thumbnail** | Small **floating** panel (max ~200 pt on the long edge) **bottom-right** of the main screen’s visible frame, with fade-in. **Copy** / **Save** strip buttons; **click image** → annotation editor. Auto-**dismiss** after **preview duration** (does not re-run the capture action on timeout). |
| **Annotations** | Window **SnapFloat — Annotate**; **freehand** strokes, **7 colors**, **↩ Undo**, **✓ Copy**, **⤓ Save** (save uses the same folder settings as the thumbnail). |
| **Cancel capture** | **Escape** closes the selection overlay; very small drags (under ~5 pt) cancel without capturing. |
| **Multi-display** | Overlay targets the screen containing the mouse; captures use the correct display via cached `SCDisplay` metadata. |
| **Notifications** | When a file is saved to disk, a **Screenshot saved** notification can appear with **Show in Finder** (standard notification permission). |

---

## Settings

Open **Settings…** from the menu bar (or **⌘,** when the menu is open).

| Option | Behavior |
|--------|----------|
| **Shortcut** | Click the field, then press your combo. **⌘** or **⌃** must be part of the final key event. **Escape** cancels recording. |
| **On capture** | Controls what happens **immediately** after a successful capture (before you interact with the thumbnail). |
| **Preview duration** | How long the thumbnail stays visible if you do nothing (1–30 seconds). |
| **Save location** | Enable saving, pick a folder; required for **Save** on the thumbnail or in the editor when using disk. |
| **Launch at login** | Registers the app with **SMAppService** (macOS login item APIs). |

---

## Requirements

- **macOS 13.0 (Ventura)** or later (`LSMinimumSystemVersion` / `MACOSX_DEPLOYMENT_TARGET` = 13.0).
- **Screen Recording** permission for the app (see below).
- **Xcode** (recent release recommended) if you are building from source.

---

## Permissions

### Screen Recording

SnapFloat uses **ScreenCaptureKit** (`SCScreenshotManager` on macOS 14+, `SCStream` fallback on macOS 13) to grab pixels from the selected rectangle.

- The bundle includes **`NSScreenCaptureUsageDescription`** (Spanish string in `Info.plist`) so macOS shows a clear prompt when access is needed.
- On first launch, `ScreenCaptureManager.prepareCapture()` triggers **one** `SCShareableContent` fetch to populate permission UI and **cache** `SCDisplay` objects. Later captures reuse that cache so **repeated permission dialogs** (a common issue on macOS 14/15 when calling shareable content APIs too often) are avoided.

### Notifications (optional)

If you save screenshots to disk, the app may show a local notification with **Show in Finder**. macOS will prompt for notification permission when the app requests it.

### What SnapFloat does *not* need for the hotkey

The global shortcut is registered with **Carbon** (`RegisterEventHotKey`), not via `CGEvent.tap` or similar, so you do **not** need to grant **Accessibility** just to use the shortcut.

---

## How to use

1. Launch **SnapFloat**. It appears only in the **menu bar**.
2. Grant **Screen Recording** when macOS asks (**System Settings → Privacy & Security → Screen Recording**).
3. Start capture with your **shortcut** (default **⇧⌘2**) or **Capture Area** from the menu.
4. **Click-drag** on the dimmed overlay to select a region; release to capture.
5. According to **Settings → On capture**, the image may be **copied**, **saved**, **both**, or **neither** right away.
6. While the **thumbnail** is visible:
   - **Wait** until the preview timer ends → thumbnail closes (clipboard/disk actions already ran per settings).
   - **Copy** / **Save** on the strip for an extra manual action (Save opens Settings if no folder is set).
   - **Click the image** → **SnapFloat — Annotate**; use **✓ Copy** or **⤓ Save**, then the window closes.

---

## Build from source

1. Clone the repository:
   ```bash
   git clone https://github.com/JuanAntonioRC/SnapFloat.git
   cd SnapFloat
   ```
2. Open **`SnapFloat.xcodeproj`** in Xcode.
3. Select the **SnapFloat** scheme and your Mac as run destination.
4. **Product → Run** (⌘R).

The app is configured as a **menu-bar–only** agent (`LSUIElement` = true): no Dock icon.

**Identifiers (from the project):**

- **Bundle ID:** `com.snapfloat.SnapFloat`
- **Marketing version:** `1.0` (as set in Xcode; adjust as you release)

**Optional:** `generate_icon.swift` at the repo root is a helper script to generate app icon assets (not part of the Xcode target by default).

---

## Architecture

High-level flow:

```text
App launch
  → AppDelegate: accessory policy, prepareCapture(), menu bar, notifications,
     HotkeyManager (shortcut from SettingsManager), observer for hotkey changes
Hotkey / menu “Capture Area”
  → CaptureOverlayWindow (per-screen frame, high window level)
  → CaptureOverlayView: selection rect, coordinate flip → global screen rect
  → (short delay) ScreenCaptureManager.capture(rect:)
        → SettingsManager.performCaptureAction (clipboard / disk per prefs)
        → ThumbnailWindowController.show
              → Copy / Save strip, or click → AnnotationWindowController
              → timer → animate out (dismiss only)
```

### Key components

| Component | Role |
|-----------|------|
| `AppDelegate` | Status item; wires hotkey and menu; updates capture menu title when shortcut changes; notification delegate for **Show in Finder**. |
| `HotkeyManager` | Carbon hotkey with **configurable** key code + modifiers; `InstallEventHandler` + `RegisterEventHotKey`; display string helpers. |
| `SettingsManager` | `UserDefaults`: capture action, preview duration, save folder, launch at login, hotkey; `performCaptureAction`, `saveToDiskIfNeeded`, notifications. |
| `SettingsWindowController` | Preferences window; includes `ShortcutRecorderView` (local event monitor for recording). |
| `CaptureOverlayWindow` / `CaptureOverlayView` | Borderless overlay; crosshair; Escape; maps flipped view coords to AppKit screen space. |
| `ScreenCaptureManager` | Cached `SCDisplay` map; `SCContentFilter` + `SCStreamConfiguration`; macOS 14+ screenshot API vs. stream helper on 13. |
| `ThumbnailWindowController` | `NSPanel` thumbnail, configurable timer, Copy/Save, click → editor. |
| `AnnotationWindowController` | `DrawingCanvasView` + toolbar (colors, undo, copy, save); `compositeImage()` rasterizes strokes at image resolution. |
| `main.swift` | Minimal entry: `NSApplication` + delegate + `run()`. |

---

## Project layout

```text
SnapFloat/
├── SnapFloat.xcodeproj/          # Xcode project
├── SnapFloat/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── HotkeyManager.swift
│   ├── SettingsManager.swift
│   ├── SettingsWindowController.swift   # includes ShortcutRecorderView
│   ├── ScreenCaptureManager.swift
│   ├── CaptureOverlayWindow.swift
│   ├── CaptureOverlayView.swift
│   ├── ThumbnailWindowController.swift
│   ├── AnnotationWindowController.swift
│   ├── Info.plist
│   └── Assets.xcassets/
├── generate_icon.swift             # optional icon generator (repo root)
├── .gitignore
└── README.md
```

---

## Technical notes

- **Coordinate systems:** The overlay view is **flipped** (origin top-left). Before capture, the selection is converted to **global AppKit screen coordinates** for `ScreenCaptureManager`, which then converts to **display-local** space with Y flipped for `SCStreamConfiguration.sourceRect`.
- **Retina:** Capture width/height use the screen’s **`backingScaleFactor`** so bitmaps match physical pixels.
- **Overlay vs. capture:** A small **delay (~60 ms)** after dismissing the overlay avoids capturing the dimmer window in the shot.
- **Cursor:** `showsCursor = false` on the stream configuration so the pointer is not baked into the image.
- **Security / privacy:** Only standard AppKit pasteboard and local file APIs are used; images are not sent to any server (fully local app).

---

## Contributing

Issues and pull requests are welcome. When changing capture or permission-related code, test on a **clean user** or after resetting Screen Recording consent to ensure you do not reintroduce repeated system prompts.

---

## License

SnapFloat is released under the **[MIT License](LICENSE)**.

In short: you may **use**, **modify**, **copy**, and **distribute** the software (including commercially) **free of charge**, as long as you keep the copyright and permission notice in copies. The software is provided **as is**, without warranty.

See the [`LICENSE`](LICENSE) file for the full legal text.
