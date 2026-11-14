# NotchLyrics 🎵

> Dynamic Island for macOS with synced lyrics

แอป macOS ที่เปลี่ยน notch ของ MacBook ให้เป็น Dynamic Island
แสดงข้อมูลเพลง + controls + synced lyrics

## Requirements

- macOS 14.0 (Sonoma) ขึ้นไป
- MacBook ที่มี notch (M1 Pro/Max/M2/M3/M4 series)
- Xcode 15+

## Quick Start

### วิธีที่ 1: ใช้ SPM + Xcode

```bash
# Clone / download project
cd NotchLyrics

# เปิดใน Xcode
open Package.swift
```

เมื่อเปิดใน Xcode:

1. เลือก target `NotchLyrics` → My Mac
2. ไปที่ **Signing & Capabilities**:
   - เลือก Team ของคุณ
   - ติ๊ก **Disable Library Validation** (เพราะใช้ private framework)
   - เพิ่ม **Hardened Runtime** → Disable Library Validation
3. **Build & Run** (⌘R)

### วิธีที่ 2: สร้าง Xcode Project ใหม่

ถ้าเปิด Package.swift แล้วมีปัญหา:

1. เปิด Xcode → File → New → Project
2. เลือก **macOS → App**
3. Product Name: `NotchLyrics`
4. Interface: **SwiftUI**, Language: **Swift**
5. ลาก source files ทั้งหมดจาก `Sources/NotchLyrics/` เข้า project
6. ตั้งค่า Info.plist:
   - เพิ่ม `LSUIElement` = `YES` (ซ่อน dock icon)
7. Build & Run

### วิธีที่ 3: Command line (ไม่แนะนำ)

```bash
swift build
.build/debug/NotchLyrics
```

> ⚠️ ต้องรันบน macOS เท่านั้น — ไม่สามารถ build บน Linux ได้

## Permissions

แอปต้องการ permissions ต่อไปนี้:

- **Accessibility** — สำหรับ global hotkeys (System Settings → Privacy → Accessibility)
- **Notifications** — สำหรับแสดง notification (optional)

## Usage

เมื่อเปิดแอป:

| Action | ผลลัพธ์ |
|--------|---------|
| เปิดเพลงใน Apple Music / Spotify | notch แสดงชื่อเพลง |
| Hover ที่ notch | ขยายแสดง player |
| Mouse ออกจาก notch | ยุบกลับ |
| คลิก "Show lyrics" | แสดงเนื้อเพลง (Phase 2) |
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

แอปใช้ `MediaRemote.framework` ผ่าน `dlopen` / `dlsym`
เป็น private framework ของ Apple — ไม่มี documentation อย่างเป็นทางการ
อ้างอิงจาก open source projects: LyricsX, Boring Notch, Carol

**ข้อจำกัด:**
- ลง Mac App Store ไม่ได้ (Apple ไม่อนุญาต private API)
- API อาจเปลี่ยนเมื่อ macOS อัปเดต (ต้อง test ทุกเวอร์ชัน)

### Distribution

เนื่องจากใช้ private API จึงต้องขายนอก App Store:
- **Gumroad** — จ่ายครั้งเดียว, จัดการ license เอง
- **Paddle** — subscription/one-time, จัดการ VAT ให้
- **Setapp** — subscription bundle, มี user base ใหญ่

### Code signing สำหรับ distribution

```bash
# สร้าง Developer ID certificate ใน Apple Developer account
# แล้ว sign + notarize:
codesign --force --deep --sign "Developer ID Application: YOUR NAME" NotchLyrics.app
xcrun notarytool submit NotchLyrics.zip --apple-id YOUR_ID --password APP_PASSWORD --team-id TEAM_ID
xcrun stapler staple NotchLyrics.app
```

## License

MIT — ใช้ได้อิสระ แก้ไขได้ตามสบาย
