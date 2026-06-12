# Contributing to Stag

We welcome contributions! Here's how to get started.

## Code of Conduct

Be respectful, constructive, and inclusive. Harassment or toxic behavior will not be tolerated.

## How to Contribute

### Reporting Bugs

1. Check existing issues to avoid duplicates.
2. Open a [bug report](.github/ISSUE_TEMPLATE/bug_report.md) with:
   - macOS version
   - Build method (self-built / Homebrew)
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots if applicable

### Suggesting Features

Open a [feature request](.github/ISSUE_TEMPLATE/feature_request.md) with:
- Clear use case
- How it improves the app
- Mockups or examples if applicable

### Pull Requests

1. **Fork** the repo and create a branch from `main`.
2. **Match code style**: No semicolons, 4-space indentation, follow existing patterns.
3. **One feature per PR** — keep changes focused.
4. **Test your changes** — verify `swift build` succeeds with zero warnings.
5. **Update docs** if you add or change user-facing features.
6. **Write a clear commit message** following [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   feat: add webcam PiP support
   fix: correct blur export crop rect
   refactor: extract RecordingTargetSelector
   ```

## Development Setup

```bash
# Clone and build
git clone https://github.com/your-username/stag.git
cd stag
./build.sh

# Run tests (if available)
swift test
```

## Code Signing

The build script prefers the "Stag Code Signing" identity. To create it:

```bash
security create-keychain -p temp stag-build.keychain
security import dev/certificate.p12 -k ~/Library/Keychains/stag-build.keychain
```

Or use ad-hoc signing (the build script falls back automatically).

## Architecture Notes

- `.accessory` activation policy (no dock icon, menu bar only)
- No Swift Package Manager dependencies — pure AppKit + SwiftUI
- `CaptureRecorder` protocol + `MediaCaptureSource` generic eliminates duplication
- iOS 18+ / macOS 15+ APIs used where appropriate with availability checks
- Preference storage uses `UserDefaults` with `@Published` wrappers
