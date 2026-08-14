# iphone-dedupe

This is a local macOS command-line helper that talks to iPhone media through Apple's ImageCaptureCore framework.

## Safety Defaults

By default it is dry-run only. It scans the connected iPhone and writes a CSV showing which files would be kept or deleted.

Actual deletion requires both flags:

```sh
--delete --i-understand-this-deletes-from-device
```

## Dry Run

```sh
.build/release/iphone-dedupe
```

Conservative duplicate rule:

```sh
.build/release/iphone-dedupe --rule name-kind-size
```

Timestamp-based duplicate rule:

```sh
.build/release/iphone-dedupe --rule timestamp-kind-size
```

## Delete

After checking the CSV:

```sh
.build/release/iphone-dedupe --rule name-kind-size --delete --i-understand-this-deletes-from-device
```

## Notes

- Keep the iPhone unlocked.
- Trust this Mac on the iPhone.
- Quit Image Capture if the tool cannot open a session.
- `name-kind-size` is safer.
- `timestamp-kind-size` is more aggressive and can catch renamed duplicates, but review the CSV first.
