# iPhone Dedupe

iPhone Dedupe is a private, local, Mac-native app for reviewing media on a connected iPhone, downloading selected files, identifying conservative duplicate candidates, and explicitly deleting reviewed device items.

It uses Apple's ImageCaptureCore framework. There is no account, cloud backend, analytics, catalog upload, or network client.

## Current Status

Phases 0–8 are merged into `main`. The current Debug app has been exercised against a connected iPhone and loaded 3,961/3,961 media items.

The source and local Hardened Runtime build gate are complete. Public distribution is not complete: Developer ID signing, Apple notarization/stapling, clean-Mac Gatekeeper validation, and the App Sandbox decision remain open. See [docs/roadmap.md](docs/roadmap.md) for the authoritative remaining-work list.

## Requirements

- macOS 14 or later;
- Swift 6.2 toolchain;
- an unlocked, trusted iPhone connected with a data-capable cable;
- Image Capture, Photos, and other apps that may exclusively hold the device session must be closed while scanning.

## Core Capabilities

- native List and Grid browsers with shared focus and explicit checkbox selection;
- filename search plus `name:`, `kind:`, `size:`, and `duration:` filters;
- sortable and persistent List columns;
- progressive static Inspector previews, capped at 2048 pixels with bounded memory caching;
- conservative duplicate candidates—never automatic deletion;
- Download progress, current-file status, cancellation, destination preflight, and collision blocking;
- explicit device-delete confirmation, persisted audit, automatic rescan, and verification-only retry;
- persistent partial-failure/cancellation Results history;
- Full Keyboard Access and VoiceOver semantics for the primary workflow;
- private staging, descriptor-relative no-overwrite commits, Hardened Runtime, and a no-tracking privacy manifest.

## Build And Run

Build the normal local Debug app bundle:

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/iPhone Dedupe.app"
```

Use the `.app` bundle for UI and accessibility testing. Running the raw SwiftPM executable bypasses normal macOS app registration and is not the acceptance path.

Run the complete test suites:

```sh
swift test
swift test -c release
```

The latest verified baseline is 433 XCTest tests plus 22 Swift Testing tests in both Debug and Release configurations.

The bundle scripts refuse to replace or re-sign their target while that exact app is running. Quit the app before rebuilding; this prevents macOS from terminating a live process with `Code Signature Invalid`.

## Local Release Candidate

An explicitly local, non-distributable ad-hoc Hardened Runtime candidate can be built with:

```sh
IPHONE_DEDUPE_ALLOW_ADHOC=1 ./scripts/build-release-candidate.sh
```

For a distributable candidate, supply a Developer ID Application identity owned by the caller:

```sh
IPHONE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
  ./scripts/build-release-candidate.sh
```

After configuring a caller-owned `notarytool` keychain profile:

```sh
IPHONE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
IPHONE_DEDUPE_NOTARY_PROFILE="profile-name" \
  ./scripts/notarize-release.sh "/path/to/iPhone Dedupe.app"
```

The release scripts fail closed when required signing or notarization inputs are absent. No credential is stored in this repository.

## Project Layout

- `Sources/DeduperCore`: pure models, search/sort, duplicate policy, presentation, and retry policy;
- `Sources/DeviceMediaKit`: serialized ImageCaptureCore gateway and secure filesystem boundary;
- `Sources/iPhoneDedupeApp`: SwiftUI/AppKit application, state, persistence, and views;
- `Sources/iPhoneDedupeVerifier`: development-only real-device harness;
- `Tests`: unit, integration, renderer, operation, persistence, and security regressions;
- `Packaging`: app Info.plist and privacy manifest;
- `scripts`: Debug/Release bundle, verification, and notarization tooling.

## Documentation

- [Product specification](docs/spec.md)
- [Architecture and security boundaries](docs/architecture.md)
- [Roadmap and remaining work](docs/roadmap.md)
- [Current handoff and manual validation](docs/handoff.md)
- [Project log](docs/log.md)

## Destructive-Action Rule

Device deletion always requires explicit in-app confirmation. Automated or development-harness deletion additionally requires fresh user approval naming the exact fixture files; old approval is never reusable.
