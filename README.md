<div align="center">

# Image Dedupe

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Photo%20Dedupe-2563eb)
![Local First](https://img.shields.io/badge/architecture-local--first-059669)

</div>

Image Dedupe is a Mac-native app for reviewing media on a connected iPhone, downloading the files you pick, spotting conservative duplicate candidates, and deleting reviewed device items on purpose.

It is built on Apple's ImageCaptureCore framework. There is no account, no cloud backend, no analytics, no catalog upload, and no network client — everything stays on your Mac.

Nothing is ever deleted for you. The app proposes; you decide.

Formerly named iPhone Dedupe. The rename carries existing operation history and preferences across automatically; the old name is kept only where an identifier had to stay stable.

## Install

Download the DMG from the [releases page](https://github.com/howtoexitvim/ImageDedupe/releases) — the current release is `ImageDedupe-v1.0` (version 1.0.0) — drag the app to Applications, then clear the download quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/Image Dedupe.app"
```

The build is ad-hoc signed and **not** notarized, so Gatekeeper blocks it until you do this. macOS 14 or later, Apple silicon (arm64) only. If you would rather not run an unnotarized binary, build from source — see below.

Before scanning, unlock the iPhone and trust the Mac, and quit Image Capture, Photos, and anything else that may hold the device session exclusively.

## Safety

Safety is the point of this project, not a feature of it.

- Duplicate detection is deliberately conservative: it produces *candidates* for you to review, never an automatic deletion.
- Device deletion always requires explicit in-app confirmation, writes a persisted audit record, and triggers an automatic rescan afterwards; retries are verification-only.
- Automated or development-harness deletion additionally requires fresh user approval naming the exact fixture files. Old approval is never reusable.
- Downloads stage into a private location and commit with descriptor-relative, no-overwrite semantics, so an existing file is never silently replaced.
- No account, no cloud, no analytics, no network client.
- Hardened Runtime is enforced by the local build gate, and the app ships a no-tracking privacy manifest.

## Capabilities

- native List and Grid browsers with shared focus and explicit checkbox selection;
- filename search plus `name:`, `kind:`, `size:`, and `duration:` filters;
- sortable and persistent List columns;
- progressive static Inspector previews, capped at 2048 pixels with bounded memory caching;
- conservative duplicate candidates — never automatic deletion;
- download progress, current-file status, cancellation, destination preflight, and collision blocking;
- explicit device-delete confirmation, persisted audit, automatic rescan, and verification-only retry;
- persistent partial-failure and cancellation Results history;
- Full Keyboard Access and VoiceOver semantics for the primary workflow.

## Requirements

- macOS 14 or later, Apple silicon (arm64);
- Swift 6.2 toolchain (to build);
- an unlocked, trusted iPhone connected with a data-capable cable;
- Image Capture, Photos, and other apps that may exclusively hold the device session closed while scanning.

## Build and Run

Build the normal local Debug app bundle:

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/Image Dedupe.app"
```

Use the `.app` bundle for UI and accessibility testing. Running the raw SwiftPM executable bypasses normal macOS app registration and is not the acceptance path.

Run the complete test suites:

```sh
swift test
swift test -c release
```

The latest verified baseline is 650 XCTest tests plus 22 Swift Testing tests, in both Debug and Release configurations.

The bundle scripts refuse to replace or re-sign their target while that exact app is running. Quit the app before rebuilding; this prevents macOS from terminating a live process with `Code Signature Invalid`.

## Release Candidate

An explicitly local, non-distributable ad-hoc Hardened Runtime candidate:

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/build-release-candidate.sh
```

For a distributable candidate, supply a Developer ID Application identity owned by the caller:

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
  ./scripts/build-release-candidate.sh
```

After configuring a caller-owned `notarytool` keychain profile:

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
IMAGE_DEDUPE_NOTARY_PROFILE="profile-name" \
  ./scripts/notarize-release.sh "/path/to/Image Dedupe.app"
```

The release scripts fail closed when required signing or notarization inputs are absent. No credential is stored in this repository.

## Disk Image

`scripts/package-dmg.sh` wraps an already-built candidate into `dist/Image-Dedupe-<version>.dmg` with the usual drag-to-Applications layout. It deliberately does not build: it packages the bundle `build-release-candidate.sh` produced, so the artifact that ships is the one that passed verification rather than a second build that resembles it.

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/package-dmg.sh
```

It re-runs `verify-release.sh` on the bundle before wrapping it, and refuses ad-hoc signatures unless `IMAGE_DEDUPE_ALLOW_ADHOC=1` is set explicitly — a disk image is where an unverified bundle stops being a local mistake and becomes a download. With `IMAGE_DEDUPE_SIGNING_IDENTITY` set, the image itself is signed too; notarize the `.app` before packaging, since stapling applies to the bundle.

`dist/` is ignored and never committed.

## Project Layout

- `Sources/DeduperCore`: pure models, search/sort, duplicate policy, presentation, and retry policy;
- `Sources/DeviceMediaKit`: serialized ImageCaptureCore gateway and secure filesystem boundary;
- `Sources/ImageDedupeApp`: SwiftUI/AppKit application, state, persistence, and views;
- `Sources/ImageDedupeVerifier`: development-only real-device harness;
- `Tests`: unit, integration, renderer, operation, persistence, and security regressions;
- `Packaging`: app Info.plist and privacy manifest;
- `scripts`: Debug/Release bundle, verification, and notarization tooling.

## Status

The app has been exercised against a connected iPhone and loaded 3,961 of 3,961 media items. The source and the local Hardened Runtime build gate are complete.

Some work is honestly still open: Developer ID signing, Apple notarization and stapling, clean-Mac Gatekeeper validation, a universal build, and the App Sandbox decision. Until those land, the shipped DMG needs the quarantine step above.

## License

[MIT](LICENSE)
