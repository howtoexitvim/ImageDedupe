# iPhone Dedupe

Mac-native iPhone media cleanup app built on Apple's ImageCaptureCore framework.

The current product direction is app-first: connect an iPhone, scan the device media catalog, browse it visually, filter/sort/search, preview files, and review conservative duplicate candidates. Direct deletion from the app is intentionally deferred until the review and confirmation flow is trustworthy.

## Open In Xcode

Open this folder in Xcode:

```sh
open /Users/shuqi/Desktop/shuqiwhat/02_Work/iPhone_Dedupe_2608-Present/Package.swift
```

Xcode can open Swift packages directly. The package contains:

- `DeduperCore`: duplicate planning logic.
- `DeviceMediaKit`: ImageCaptureCore device scanning, media mapping, thumbnails, and future delete execution.
- `iPhoneDedupeApp`: SwiftUI macOS app.
- `DeduperCoreTests`: unit tests.
- `docs/`: product log, architecture notes, and product spec.

## Build And Test

```sh
cd /Users/shuqi/Desktop/shuqiwhat/02_Work/iPhone_Dedupe_2608-Present
swift test
swift build
```

Run the local debug app:

```sh
.build/debug/iPhoneDedupeApp
```

## Notes

- The original unlock failure was ImageCaptureCore returning `com.apple.ImageCaptureCore Code=-9943`.
- The current version retries that specific unlock/access-restricted error until the timeout expires.
- Quit Image Capture before scanning, because it can hold the same device session.
- v0.1 is read-only in the UI; deletion belongs to the next safe review phase.
