# iPhone Dedupe

Mac-native iPhone media cleanup app built on Apple's ImageCaptureCore framework.

The current product direction is app-first: connect an iPhone, scan the device media catalog, browse it visually, smart-search/sort/preview files, import selected media, and delete selected media only after explicit confirmation.

## Open In Xcode

Open this folder in Xcode:

```sh
open /Users/shuqi/Desktop/shuqiwhat/02_Work/iPhone_Dedupe_2608-Present/Package.swift
```

Xcode can open Swift packages directly. The package contains:

- `DeduperCore`: duplicate planning logic.
- `DeviceMediaKit`: ImageCaptureCore device scanning, media mapping, thumbnails, import, and delete execution.
- `iPhoneDedupeApp`: SwiftUI macOS app.
- `DeduperCoreTests`: unit tests.
- `iPhoneDedupeAppTests`: AppKit search binding and list layout regression tests.
- `docs/`: product log, architecture notes, and product spec.

## Build And Test

```sh
cd /Users/shuqi/Desktop/shuqiwhat/02_Work/iPhone_Dedupe_2608-Present
swift test
swift build
```

Build the standard local debug app bundle:

```sh
./scripts/build-debug-app.sh
open ".build/debug/iPhone Dedupe.app"
```

Use the `.app` bundle for UI testing. Opening the raw SwiftPM executable bypasses normal macOS app registration and can break text focus and accessibility behavior.

## Notes

- The original unlock failure was ImageCaptureCore returning `com.apple.ImageCaptureCore Code=-9943`.
- The current version retries that specific unlock/access-restricted error until the timeout expires.
- Quit Image Capture before scanning, because it can hold the same device session.
- Device deletion is available only through explicit user selection plus a destructive confirmation dialog.
