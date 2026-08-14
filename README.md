# iPhone Dedupe Project

Swift Package for scanning and deleting duplicate iPhone media through Apple's ImageCaptureCore framework.

## Open In Xcode

Open this folder in Xcode:

```sh
open /Users/shuqi/Desktop/shuqiwhat/02_Work/iPhoneDedupeProject-2026-08-15-0024/Package.swift
```

Xcode can open Swift packages directly. The package contains:

- `DeduperCore`: duplicate planning logic.
- `iphone-dedupe`: command-line executable that talks to ImageCaptureCore.
- `DeduperCoreTests`: unit tests.
- `docs/`: product log and product spec for the macOS app direction.

## Build And Test

```sh
cd /Users/shuqi/Desktop/shuqiwhat/02_Work/iPhoneDedupeProject-2026-08-15-0024
swift test
swift build -c release
```

The release binary will be generated at `.build/release/iphone-dedupe`.

## Dry Run

```sh
.build/release/iphone-dedupe --rule name-kind-size --timeout 180 --csv ./iphone-dedupe-dry-run.csv
```

## Delete From Device

Review the CSV first. Then keep the iPhone unlocked, keep the screen awake, and approve Trust This Mac if prompted.

```sh
.build/release/iphone-dedupe --rule name-kind-size --delete --i-understand-this-deletes-from-device --timeout 180 --csv ./iphone-dedupe-delete.csv
```

## Notes

- The original unlock failure was ImageCaptureCore returning `com.apple.ImageCaptureCore Code=-9943`.
- The current version retries that specific unlock/access-restricted error until the timeout expires.
- Quit Image Capture before running the CLI, because it can hold the same device session.
