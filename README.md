# SnapFloat

**SnapFloat** is a lightweight macOS menu-bar utility for **region screenshots**: select an area on screen, get a floating thumbnail, then either **copy the capture to the clipboard** or **open a simple annotation editor** before copying.

Built with **Swift**, **AppKit**, and **ScreenCaptureKit**. No Dock icon—only a status item and global shortcuts.

---

## Table of contents

- [Features](#features)
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
| **Global shortcut** | **⇧⌘2** (Shift + Command + 2) starts capture from anywhere, implemented with **Carbon** so **Accessibility** permission is **not** required for the hotkey. |
| **Menu bar** | SF Symbol `camera.viewfinder`; menu entries **Capturar área ⇧⌘2** and **Salir de SnapFloat** (⌘Q). |
| **Post-capture** | Small **floating thumbnail** (max ~200 pt on the long edge) in the **bottom-right** of the main screen’s visible frame, with fade-in. |
| **Thumbnail behavior** | **Click** → opens annotation window and cancels the auto-timer. **No click for 5 seconds** → copies the **original** image to the **general pasteboard** and dismisses. |
| **Annotations** | Floating window with the screenshot; **freehand strokes**, **7 colors** (system palette + white/black), **Deshacer** (undo last stroke), **Copiar** composites image + strokes at full resolution and copies to clipboard, then closes. |
| **Cancel capture** | **Escape** closes the selection overlay; very small drags (under ~5 pt) cancel without capturing. |
| **Multi-display** | Overlay targets the screen containing the mouse; captures use the correct display via cached `SCDisplay` metadata. |

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

### What SnapFloat does *not* need for the hotkey

The global shortcut is registered with **Carbon** (`RegisterEventHotKey`), not via `CGEvent.tap` or similar, so you do **not** need to grant **Accessibility** just to use **⇧⌘2**.

---

## How to use

1. Launch **SnapFloat** (after building or installing). It appears only in the **menu bar**.
2. Grant **Screen Recording** when macOS asks (System Settings → Privacy & Security → Screen Recording).
3. Start capture with **⇧⌘2** or **Capturar área** from the menu.
4. **Click-drag** on the dimmed overlay to select a region; release to capture.
5. Either:
   - **Wait ~5 seconds** — original image is copied to the clipboard, thumbnail disappears; or  
   - **Click the thumbnail** — open **SnapFloat — Anotar**, draw, use **Deshacer** / color dots, then **✓ Copiar** to copy the composited result.

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

---

## Architecture

High-level flow:

```text
App launch
  → AppDelegate: accessory policy, prepareCapture(), menu bar, HotkeyManager
Hotkey / menu “Capturar”
  → CaptureOverlayWindow (per-screen frame, high window level)
  → CaptureOverlayView: selection rect, coordinate flip → global screen rect
  → (short delay) ScreenCaptureManager.capture(rect:)
  → ThumbnailWindowController.show
        → click → AnnotationWindowController.show → composite → pasteboard
        → timeout → pasteboard (original only)
```

### Key components

| Component | Role |
|-----------|------|
| `AppDelegate` | `NSApplication` delegate; status item; wires hotkey to `initiateCapture()`. |
| `HotkeyManager` | Carbon hotkey **⇧⌘2**; installs `InstallEventHandler` + `RegisterEventHotKey`. |
| `CaptureOverlayWindow` / `CaptureOverlayView` | Borderless overlay; crosshair; Escape; maps flipped view coords to AppKit screen space. |
| `ScreenCaptureManager` | Cached `SCDisplay` map; `SCContentFilter` + `SCStreamConfiguration`; macOS 14+ screenshot API vs. stream helper on 13. |
| `ThumbnailWindowController` | `NSPanel` thumbnail, 5 s timer, clipboard on timeout, click → editor. |
| `AnnotationWindowController` | `DrawingCanvasView` + toolbar (colors, undo, copy); `compositeImage()` rasterizes strokes at image resolution. |
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
│   ├── ScreenCaptureManager.swift
│   ├── CaptureOverlayWindow.swift
│   ├── CaptureOverlayView.swift
│   ├── ThumbnailWindowController.swift
│   ├── AnnotationWindowController.swift
│   ├── Info.plist
│   └── Assets.xcassets/
├── .gitignore
└── README.md
```

---

## Technical notes

- **Coordinate systems:** The overlay view is **flipped** (origin top-left). Before capture, the selection is converted to **global AppKit screen coordinates** for `ScreenCaptureManager`, which then converts to **display-local** space with Y flipped for `SCStreamConfiguration.sourceRect`.
- **Retina:** Capture width/height use the screen’s **`backingScaleFactor`** so bitmaps match physical pixels.
- **Overlay vs. capture:** A small **delay (~60 ms)** after dismissing the overlay avoids capturing the dimmer window in the shot.
- **Cursor:** `showsCursor = false` on the stream configuration so the pointer is not baked into the image.
- **Security / privacy:** Only standard AppKit pasteboard APIs are used; images are not sent to any server (fully local app).

---

## Contributing

Issues and pull requests are welcome. When changing capture or permission-related code, test on a **clean user** or after resetting Screen Recording consent to ensure you do not reintroduce repeated system prompts.

---

## License

SnapFloat is released under the **[MIT License](LICENSE)**.

In short: you may **use**, **modify**, **copy**, and **distribute** the software (including commercially) **free of charge**, as long as you keep the copyright and permission notice in copies. The software is provided **as is**, without warranty.

See the [`LICENSE`](LICENSE) file for the full legal text.
