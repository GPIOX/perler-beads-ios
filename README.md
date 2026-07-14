# 拼豆图纸 for iPhone and iPad

A native, offline SwiftUI application that converts images into editable bead
patterns. It supports five color-number systems, local project documents,
manual editing, focus guidance, and PNG/CSV export. Images and compatible CSV
files can also be opened directly from Files; the app creates a separate
`.beadpattern` project and leaves the source untouched.

## Requirements

- Xcode 16 or later (also verified with Xcode 26)
- iOS/iPadOS 17 or later
- Swift 6

## Open and run

1. Open `BeadPattern.xcodeproj`.
2. Select the `BeadPatternApp` scheme and an iPhone or iPad simulator.
3. Build and run. Automatic signing is disabled for simulator builds; select
   your own Development Team before installing on a physical device.

Generated projects include a `preview.png` image and a registered document
icon for Files. PNG exports can be saved directly to Photos, or shared to Files
and other apps; CSV exports use the system share sheet.

The image-processing package can be tested independently:

```bash
cd Packages/BeadPatternCore
swift test
```

## Privacy

Images and project documents are processed locally. The app has no account,
analytics, advertising, payment, tracking, or server component.

## License

GNU AGPL-3.0. See `LICENSE` and `NOTICE.md`.
