# NotchLyrics 🎵

> Dynamic Island for macOS with synced lyrics

NotchLyrics turns the MacBook notch into a music player with track information, playback controls, and synchronized lyrics.


## Requirements

- macOS 14.0 (Sonoma) or later
- A MacBook with a display notch
- Xcode 15+

## Quick Start

### Option 1: Use Swift Package Manager and Xcode

```bash
# Clone / download project
cd NotchLyrics

# Open the package in Xcode
open Package.swift
```

In Xcode:

1. Select the `NotchLyrics` scheme and the **My Mac** destination.
2. Open **Signing & Capabilities**.
   - Select your development team.
   - Enable **Disable Library Validation** for the private framework.
   - This option is under **Hardened Runtime**.
3. **Build & Run** (⌘R)

### Option 2: Create an Xcode project

If you have trouble opening `Package.swift`, create a project manually:

1. In Xcode, choose **File → New → Project**.
2. Select **macOS → App**.
3. Product Name: `NotchLyrics`
4. Interface: **SwiftUI**, Language: **Swift**
5. Drag the source files from `Sources/NotchLyrics/` into the project.
6. Configure `Info.plist`.
   - Set `LSUIElement` to `YES` to hide the Dock icon.
7. Build & Run

### Option 3: Run from the command line

```bash
swift build
.build/debug/NotchLyrics
```

> Build and run the app on macOS.

## Permissions

The app uses the following permissions:

- **Accessibility** — global keyboard shortcuts (System Settings → Privacy & Security → Accessibility)
- **Notifications** — optional notification delivery

## Usage

After launching the app:

| Action | Result |
|--------|---------|
| Play a song in Apple Music or Spotify | The notch displays track information. |
| Hover over the compact notch | The notch enlarges slightly. Click the artwork to open the player. |
| Move the pointer away from the expanded notch | The player collapses. |
| Choose **Lyrics on Lock Screen** in the menu bar | Toggle lyrics on the lock screen. |
| ⌘+Shift+L | Toggle lyrics |
| ⌘+Shift+N | Toggle expand |

## Architecture

```
Sources/NotchLyrics/
├── App/                    # Entry point, AppDelegate, global state
├── Core/Media/             # MediaRemote bridge, Now Playing engine
├── Presentation/
│   ├── Window/             # NSPanel, positioning
│   ├── Views/              # SwiftUI views (Compact, Expanded, Lyrics)
│   └── Components/         # Reusable UI components
└── Utilities/              # HotKey, ColorExtractor
```

## Roadmap

- [x] **Phase 1** — NotchWindow + MediaEngine + Controls (current)
- [ ] **Phase 2** — Synced lyrics (LRCLIB + Musixmatch)
- [ ] **Phase 3** — Polish (animations, multi-monitor, accent colors)
- [ ] **Phase 4** — Lock screen, notifications, settings
- [ ] **Phase 5** — License system + launch

## Tech Notes

### Private API: MediaRemote.framework

The app loads `MediaRemote.framework` dynamically using `dlopen` and `dlsym`.
MediaRemote is a private Apple framework without public API documentation.
Open-source references include LyricsX, Boring Notch, and Carol.

**Limitations**
- The app uses private APIs and is intended for distribution outside the Mac App Store.
- Test each macOS release because the API may change.

### Distribution

Options for distributing the app outside the Mac App Store include:
- **Gumroad** — one-time purchases with developer-managed licensing
- **Paddle** — subscriptions or one-time purchases with VAT handling
- **Setapp** — a subscription bundle with an established user base

### Code signing for distribution

```bash
# Create a Developer ID Application certificate in your Apple Developer account.
# Sign and notarize the app.
codesign --force --deep --sign "Developer ID Application: YOUR NAME" NotchLyrics.app
xcrun notarytool submit NotchLyrics.zip --apple-id YOUR_ID --password APP_PASSWORD --team-id TEAM_ID
xcrun stapler staple NotchLyrics.app
```

## License

MIT — you may use and modify the software under the terms of the MIT License.
