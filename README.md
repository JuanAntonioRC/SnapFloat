# SnapFloat

A lightweight screenshot tool. Select a region, get a floating preview, copy or save — all without leaving your workflow. Native on **macOS** (menu bar) and **Linux** (tray icon, Ubuntu/GNOME first).

[![Buy Me A Coffee](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/juanantoniorc)

![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Linux](https://img.shields.io/badge/Linux-Ubuntu%2FGNOME-orange)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)



**[Download the latest release](https://github.com/JuanAntonioRC/SnapFloat/releases/latest)**

> macOS requires **macOS 13 (Ventura)** or later. Linux is built from source (see [below](#linux-ubuntugnome)) — there's no packaged release yet.

---

## Install (macOS)

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

## Build from source (macOS)

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

## Linux (Ubuntu/GNOME)

A separate, from-scratch Linux build living alongside the macOS app — same repo, same MIT license, no shared code with the AppKit target (see [Architecture](#architecture-for-contributors)). Built with GTK4 and tested on Ubuntu (GNOME/Wayland); other GTK4 desktops should mostly work too, but Ubuntu/GNOME is the tested target.

**Current feature set:** region capture (auto copy/save per Settings, exactly like the mac version), a global keyboard shortcut (shown next to Capture Area in the tray menu, kept in sync if you rebind it in GNOME Settings), a floating preview sized to the capture's aspect ratio with copy/save, a click-to-annotate editor (pen/line/arrow/rect/oval/text, colors, stroke width, undo, resizable window with aspect-fit canvas), "Screenshot saved" notifications with a **Show in Files** button (the mac version's "Show in Finder"), a tray icon with a Capture/Settings/Quit menu, and a Settings window (shortcut, on-capture action, preview duration, save location, launch at login).

Capture quality is already maximal by default — the XDG portal always returns the display's native-resolution screenshot; there's no separate quality setting to toggle (unlike macOS's Retina option, which exists because ScreenCaptureKit lets you choose 1× vs 2× — the portal doesn't expose that knob at all).

### Three deliberate differences from macOS

1. **No custom selection overlay.** Wayland doesn't let an app draw its own crosshair-and-dimmer overlay over other windows for security reasons. SnapFloat calls the standard `org.freedesktop.portal.Screenshot` D-Bus portal with `interactive: true`, which shows **GNOME's own** region/window/screen picker (the same one Flameshot and other Linux screenshot tools use) — SnapFloat picks up the resulting image once you finish.
2. **The floating preview isn't pinned to a corner.** Wayland also doesn't let apps set an absolute on-screen position for their own windows, and GNOME/Mutter doesn't support the `wlr-layer-shell` protocol some other compositors use for this. The preview window appears wherever Mutter's default placement puts it, rather than snapping to the bottom-right corner like on macOS.
3. **The shortcut's key combination is assigned in GNOME's own Settings, not SnapFloat's.** SnapFloat registers a named shortcut ("Capture Area") via `org.freedesktop.portal.GlobalShortcuts`; GNOME shows a one-time permission prompt on first launch, and the actual physical keys are picked in **Settings → Keyboard → View and Customize Shortcuts → SnapFloat** — the Settings window has an "Open Keyboard Shortcuts…" button that jumps straight there. This mirrors how the region picker above is also delegated to GNOME's own UI rather than reimplemented.

### Install

No packaged build yet — build from source:

```bash
git clone https://github.com/JuanAntonioRC/SnapFloat.git
cd SnapFloat
./scripts/setup-linux-deps.sh   # installs build tooling — see note below
./scripts/build-linux.sh        # swift build -c release
./scripts/install-linux.sh      # copies into ~/.local/{bin,share}
```

Then launch **SnapFloat** from your application menu, or run `~/.local/bin/snapfloat-linux` directly.

`setup-linux-deps.sh` installs `build-essential pkg-config libgtk-4-dev libglib2.0-dev` plus a Swift toolchain:

- **With `sudo`**: does a normal `apt-get install` + installs Swift via [swiftly](https://swiftlang.github.io/swiftly/).
- **Without `sudo`** (e.g. a managed machine): downloads the needed `-dev` packages with `apt-get download` (no root required) and extracts them with `dpkg -x` into a local sysroot at `~/.cache/snapfloat-sysroot`, and installs the Swift toolchain tarball into `~/.local/swift`. Nothing outside your home directory is touched. If you went this route, `source scripts/linux-env.sh` before `swift build`/`build-linux.sh` so the vendored toolchain and headers are found — `build-linux.sh` does this automatically.

### Build manually

```bash
source scripts/linux-env.sh   # only needed for the no-sudo path above
swift build -c release
./.build/release/snapfloat-linux
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

<details>
<summary><strong>Linux architecture (for contributors)</strong></summary>

### Layout

```
Package.swift                # SPM manifest — Linux-only, doesn't affect the Xcode/macOS build at all
Sources/
  SnapFloatCore/              # Pure Swift (Foundation only) — settings store, capture-action enum,
                               # filename formatting. A separate copy from the mac SettingsManager,
                               # not shared — see the note in Sources/SnapFloatCore/CaptureAction.swift.
  CGtk4Shim/                  # A `module.modulemap` + one-line shim.h (#include <gtk/gtk.h> + <gio/gio.h>).
                               # No binding generator (no gir2swift) — Swift's Clang importer exposes the
                               # C API directly; Sources/SnapFloatLinux/GtkInterop.swift wraps the handful
                               # of raw-pointer/signal patterns used elsewhere.
  SnapFloatLinux/
    main.swift                 # GtkApplication setup + run loop
    AppController.swift        # Coordinator: D-Bus connection, tray, shortcut, capture flow
    GtkInterop.swift            # Signal-connect helper, GObject pointer casts, GVariant builders,
                                 # the shared portalRequest() request/response helper
    PortalScreenshot.swift      # org.freedesktop.portal.Screenshot via portalRequest()
    GlobalShortcut.swift        # org.freedesktop.portal.GlobalShortcuts via portalRequest();
                                 # tracks rebinds via the ShortcutsChanged signal
    TrayIndicator.swift         # Hand-rolled org.kde.StatusNotifierItem + com.canonical.dbusmenu
                                 # (see the note at the top of the file for why not libayatana-appindicator3)
    CaptureActions.swift        # Shared copy/save primitives (auto on-capture action, manual buttons,
                                 # annotation editor's Copy/Save all call into this)
    PreviewWindow.swift         # Floating thumbnail, Copy/Save, click-to-annotate, auto-dismiss timer
    AnnotationWindow.swift      # GtkDrawingArea + Cairo canvas: pen/line/arrow/rect/oval/text, undo.
                                 # Shapes live in image coordinates; the resizable window aspect-fits
                                 # the canvas, so Copy/Save composite 1:1 with no upscaling.
    SettingsWindow.swift        # Preferences window
    LinuxNotifications.swift    # GNotification for "Screenshot saved" + its "Show in Files" button
                                 # (org.freedesktop.FileManager1.ShowItems)
    LinuxAutostart.swift        # ~/.config/autostart/*.desktop toggle
data/                          # .desktop entry + hicolor SVG icon
scripts/
  setup-linux-deps.sh          # apt install, or a no-root fallback (see README above)
  linux-env.sh                 # sourced by build-linux.sh for the no-root fallback's vendored toolchain
  build-linux.sh, install-linux.sh
```

### Technical notes

- **GVariant/GDBusConnection/GtkLabel/GtkComboBoxText/GtkFileDialog import as bare `OpaquePointer`**, not a named typed pointer the way `GtkWindow`/`GtkButton`/`GtkComboBox` do — an inconsistency in how Swift's ClangImporter surfaces this GTK4 version's types. Functions taking one of the "opaque" ones as their first argument import that parameter as `OpaquePointer` too, so the pattern throughout is: use the typed pointer where the compiler accepts it, fall back to `OpaquePointer(...)` where it doesn't. See the comment atop `SettingsWindow.swift`.
- **GVariant construction avoids GLib's varargs APIs** (`g_variant_new(format, ...)`, `g_variant_lookup(...)`) entirely, in favor of fixed-signature builder calls (`g_variant_builder_new`/`add_value`, `g_variant_new_dict_entry`, ...) — see the helpers in `GtkInterop.swift`. This sidesteps any risk of C-varargs/Swift calling-convention mismatches.
- **The tray menu is a hand-rolled `com.canonical.dbusmenu` server**, not a real GTK menu widget — the shell (GNOME's AppIndicator extension) renders it from the `GetLayout` D-Bus reply, not from any widget tree on our side.
- **`swift build`/`swift run` only ever touch the Linux target** — nothing under `SnapFloat/` or `SnapFloat.xcodeproj/` is read or written by the SPM build.

</details>
