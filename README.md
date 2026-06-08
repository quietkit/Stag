<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Sources/Cropit/Resources/icon_256x256@2x.png">
  <img src="Sources/Cropit/Resources/icon_256x256@2x.png" width="128" alt="Cropit">
</picture>

# Cropit

> A powerful macOS screenshot and screen recording app — built for speed, flexibility, and polish.

[![Swift](https://img.shields.io/badge/swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue.svg)](https://developer.apple.com/macos)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## Features

### Capture
| | |
|---|---|
| **Area** | Select any region with a crosshair overlay |
| **Window** | Capture a specific window with shadow |
| **Fullscreen** | Capture all displays at once |
| **Scrolling** | Auto-scroll + stitch tall content (web pages, docs) |
| **Self-Timer** | 3s / 5s / 10s countdown before capture |
| **Freeze Screen** | Capture with frozen desktop background |
| **Hide Desktop Icons** | Toggle before capture for clean screenshots |

### Recording
| | |
|---|---|
| **Screen Recording** | System audio + optional microphone, with hardware-accelerated encoding |
| **GIF Recording** | High-quality dithered GIFs (Floyd-Steinberg, 216-color palette, up to 50 fps) |
| **Webcam PiP** | Picture-in-picture overlay in any corner (rounded rect + shadow) |
| **Mouse Clicks** | Visual ripple animation on click |
| **Video Trimming** | In-app trimmer with preview after recording |
| **Do Not Disturb** | Auto-enable DND during recordings |

### Editor
| Shape Tools | Drawing Tools | Effects | Special |
|---|---|---|---|
| Arrow | Freehand | Blur | Emoji |
| Curved Arrow | Highlight | Mosaic | Ruler |
| Rectangle | Smart Highlight | Remove Background | Spotlight |
| Circle / Ellipse | Eraser | Step Number | Magnifier Callout |

| Action | |
|---|---|
| **Zoom & Pan** | Pinch, ⌘+/⌘-, ⌘0 |
| **Rotate** | ±90° (preserves annotations) |
| **OCR** | Extract text via Vision framework |
| **Resize** | W×H with aspect lock |
| **Color Contrast Checker** | Pixel-luminance analysis + rating |
| **Cloud Upload** | POST to configurable URL |
| **Undo / Redo** | Full stack for annotations + image edits |
| **Layer Ordering** | ⌘]/⌘[ — bring forward, send backward |

### History Browser
- Thumbnail grid with search (OCR, filename, date)
- Type filter chips (Screenshot / Recording / GIF)
- Context menu: open, reveal in Finder, copy OCR, delete

### Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘⇧1 | Capture Area |
| ⌘⇧2 | Capture Window |
| ⌘⇧3 | Capture Fullscreen |
| ⌘⇧4 | Scrolling Capture |
| ⌘⇧5 | Record Screen |
| ⌘⇧6 | Record GIF |

*(All shortcuts configurable in Settings)*

### URL Scheme

Trigger captures and actions via `cropit://` URLs — great for Raycast, Alfred, scripts, or browser bookmarks:

```
cropit://capture                        # Default area capture
cropit://capture?type=area              # Area capture
cropit://capture?type=window            # Window capture
cropit://capture?type=fullscreen        # Fullscreen capture
cropit://capture?type=scrolling         # Scrolling capture
cropit://capture?type=recording         # Screen recording
cropit://capture?type=gif               # GIF recording
cropit://capture?delay=5                # 5-second self-timer
cropit://preferences                    # Open Settings
cropit://history                        # Open History Browser
```

---

## Installation

### Manual Build

```bash
git clone https://github.com/your-username/cropit.git
cd cropit
./build.sh
```

The built app will open automatically. Drag `build/Cropit.app` to Applications if desired.

> **Note:** Screen recording permission requires manual approval in **System Settings → Privacy & Security → Screen Recording** on first run.

### Homebrew (coming soon)

```bash
brew install cropit
```

---

## Development

### Requirements
- macOS 14+ (Sonoma)
- Xcode 15+ or Command Line Tools
- Swift 5.9

### Build

```bash
./build.sh              # Debug build
./build.sh release      # Release build
```

The build script:
1. Runs `swift build`
2. Creates a `.app` bundle
3. Codesigns with "Cropit Code Signing" identity (or ad-hoc fallback)
4. Opens the app

### Project Structure

```
Sources/Cropit/
├── CropitApp.swift              # @main entry
├── AppDelegate.swift            # Menu bar, hotkeys, URL scheme
├── CaptureManager.swift         # Capture orchestration
├── URLSchemeHandler.swift       # cropit:// URL parsing
├── Capture/                     # Capture sources (area, window, etc.)
├── Recording/                   # ScreenRecorder, GIFRecorder, webcam, mic, compositor
├── Views/                       # Editor, preferences, history, overlays
├── Models/                      # Preferences, AppStore, history store
└── Resources/                   # Icons
```

---

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

Cropit is released under the [MIT License](LICENSE).
