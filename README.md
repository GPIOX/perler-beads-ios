# 拼豆图纸 for iPhone and iPad

A native, offline SwiftUI application that converts images into editable bead
patterns. It supports five color-number systems, local project documents,
manual editing, focus guidance, and PNG/CSV export.

## Requirements

- Xcode 26 or later
- iOS/iPadOS 17 or later
- Swift 6

## Open and run

1. Open `BeadPattern.xcodeproj`.
2. Select the `BeadPatternApp` scheme and an iPhone or iPad simulator.
3. Build and run. Automatic signing is disabled for simulator builds; select
   your own Development Team before installing on a physical device.

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
