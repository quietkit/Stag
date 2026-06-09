# Cropit Feature Gap & Growth Plan (Token‑Efficient Summary)

## What Shottr & CleanShot X have that Cropit lacks
- Floating toolbar that appears right after a capture for quick shape/blur/eyedropper actions.
- Live preview while adjusting blur or pixelate size.
- Dedicated color picker/eyedropper with HEX/RGB copy.
- Instant one‑click sharing (Imgur, custom URL, Markdown link).
- PDF export (single & multi‑page).
- Advanced shortcut manager with conflict detection, import/export.
- Cursor‑highlight option for video recordings.
- Batch capture mode with auto‑grid collage export.
- Explicit multi‑monitor selector UI.
- Secure‑field ignore toggle for screenshots.
- Performance benchmark & low‑CPU mode.
- Persistent snipping window (always‑on‑top).

## High‑impact features to add to attract those users
| Priority | Feature | Reason |
|---|---|---|
| **P1** | Floating toolbar after selection (quick‑add shapes, blur, color picker) | Matches core UX of both competitors; reduces mouse travel. |
| **P1** | Live blur/pixelate preview | Designers need visual feedback; easy win. |
| **P1** | Eyedropper with clipboard copy | High‑value for UI designers. |
| **P2** | PDF export (single & multi‑page) | Opens corporate/education market. |
| **P2** | Instant sharing (Imgur, custom URL, Markdown link) | One‑click workflow that users love. |
| **P2** | Shortcut manager with conflict detection, import/export | Power‑user migration path. |
| **P3** | Cursor highlight/fade for recordings | Completes video feature parity. |
| **P3** | Batch capture + auto‑grid collage | Rapid documentation workflow. |
| **P3** | Multi‑monitor selector UI | Improves discoverability on multi‑display setups. |
| **P4** | Secure‑field ignore toggle | Needed for docs containing passwords. |
| **P4** | Low‑CPU/performance mode + benchmark | Competes with Shottr’s <25 ms latency claim. |
| **P5** | Persistent snipping window (always‑on‑top) | Mimics Windows Snipping Tool style. |

## 12‑week rollout roadmap (high‑level)
1‑2 w: Add latency instrumentation, baseline performance tests.
2‑4 w: Implement floating toolbar, live blur preview, eyedropper.
5‑7 w: PDF exporter, Imgur/Multi‑URL sharing, shortcut manager UI.
8‑10 w: Cursor highlight, batch capture + collage, monitor selector.
11‑12 w: Secure‑field toggle, low‑CPU mode, final QA, beta release.

## Success metrics (post‑release)
- 30 % of new downloads cite “Shottr/CleanShot alternative”.
- 80 % retention of users who enable floating toolbar after 30 d.
- 90 % of hot‑key→overlay ≤ 25 ms.
- > 5 k Imgur uploads in first month.
- 25 % increase in donations/open‑source contributions.

## Risks & mitigations
- UI bloat → keep toolbar minimal, hide rarely used tools under a “More…” pop‑over.
- Imgur quota → allow custom upload endpoint, size limits, opt‑out.
- Performance regression → profile each feature, provide low‑CPU toggle.
- Multi‑monitor stitching errors → add DPI sanity checks, fallback option.

## Positioning copy (for marketing)
> **Cropit – The free, open‑source alternative to Shottr & CleanShot X**
> - Instant capture + floating toolbar for on‑the‑fly annotations.
> - Live blur/pixelate preview, built‑in color picker.
> - Export to PNG, GIF, Video, **PDF**.
> - One‑click sharing to Imgur or any custom URL with Markdown link copy.
> - Webcam‑PiP, mouse‑click visualizer, auto‑DND, scrolling capture.
> - Forever free, no watermarks.

---
*Use this file to refresh your context without re‑reading the full analysis.*

## System Overview (Token‑Efficient Summary)
- **Architecture**: macOS AppKit + SwiftUI hybrid (NSWindow + NSHostingView).
- **Capture stack**: ScreenCaptureKit for video/GIF, ImageIO for GIF encoding (patches GIF87a → GIF89a), Vision for OCR (Arabic support via `automaticallyDetectsLanguage=true`, `usesLanguageCorrection=false`).
- **Window lifecycle**: `WindowLifecycle` enum implements Shottr‑style activation policy – app launches as `.accessory`, switches to `.regular` when Editor/Settings/History open, returns to `.accessory` when all close.
- **Preferences defaults**: auto‑copy, open‑in‑editor action, thumbnail disabled, save path `~/Desktop/Cropit Screenshots`, file prefix `Cropit_` (editable).
- **UI utilities**: custom `ToastWindow` (auto‑dismiss, non‑intrusive), thumbnail positioning based on screen visible frame, `FloatingThumbnailWindow`, `HistoryBrowserWindow`.
- **GIF handling**: logical size × backingScaleFactor for retina, post‑encode byte‑patch for GIF89a compliance.
- **Audio**: `MicrophoneCaptureManager` mixes system and mic audio via DSP normalization.
- **Hot‑keys**: global monitors, configurable shortcuts, conflict‑aware manager.
- **Recent changes**: unified `WindowLifecycle` usage, default save folder creation, OCR improvements, GIF89a patch, toast notifications, updated defaults.
