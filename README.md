<div align="center">

# Image Dedupe

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Photo%20Dedupe-2563eb)
![Local First](https://img.shields.io/badge/architecture-local--first-059669)

</div>

Image Dedupe is a Mac app for cleaning up the photos and videos on your iPhone.

Plug the phone in, scan it, and see everything in one window — a sortable list or a grid of thumbnails, with previews and metadata beside it. Search for what you want, download it, and delete what you no longer need.

It talks to the iPhone over the cable using Apple's own ImageCaptureCore. No account, no cloud, no analytics, no network client. Nothing leaves your Mac.

And nothing is ever deleted for you. The app proposes; you decide.

## Why Image Dedupe

- 🔒 **Everything stays local**: no sign-in, no upload, no telemetry. Just your Mac and the cable.
- 🧊 **Conservative by design**: duplicates are candidates for you to review, never an automatic deletion.
- 🔍 **Find anything fast**: search by filename, or narrow with `name:`, `kind:`, `size:`, and `duration:` filters.
- 🖼️ **Look before you act**: List or Grid, sortable columns, and an Inspector with previews and real EXIF metadata.
- ⬇️ **Download what you pick**: live progress, cancel any time, destination preflight, and no silent overwrites.
- 🗑️ **Deletion you have to mean**: an explicit in-app confirmation, an audit record, and an automatic rescan afterwards.
- 🆓 **Free and MIT licensed**.

## Screenshots

<div align="center">
  <img src="assets/duplicates-review.png" width="88%" alt="Image Dedupe duplicate review: a group header reading QVKQ5385.JPG — 2 copies with both copies listed, one marked as the keeper, and an Inspector showing the preview and EXIF metadata" />
</div>

<br/>

<table>
	<tr>
		<td align="center" colspan="2"><strong>Scanned 4189 items. Conservative duplicates: 1.</strong><br/>That status line is the whole philosophy. It only proposes what it is sure about.</td>
	</tr>
	<tr>
		<td align="center"><strong>Plug in and scan</strong></td>
		<td align="center"><strong>List view with Inspector</strong></td>
	</tr>
	<tr>
		<td align="center"><img src="assets/scan-empty.png" alt="Image Dedupe waiting for an iPhone, with the Scan iPhone button in the empty state" /></td>
		<td align="center"><img src="assets/all-media-list.png" alt="Image Dedupe list browser showing Name, Kind, Date and File Size columns with checkbox selection, the search field, and the Inspector pane" /></td>
	</tr>
	<tr>
		<td align="center"><strong>Grid view</strong></td>
		<td align="center"><strong>Duplicates, ready for review</strong></td>
	</tr>
	<tr>
		<td align="center"><img src="assets/all-media-grid.png" alt="Image Dedupe grid browser showing the same library as thumbnails" /></td>
		<td align="center"><img src="assets/duplicates-review.png" alt="Image Dedupe duplicate group with two copies of the same file and one marked as the keeper" /></td>
	</tr>
</table>

## Install

Download the DMG from the [releases page](https://github.com/howtoexitvim/ImageDedupe/releases) — the current release is `ImageDedupe-v1.0` (version 1.0.0) — and drag **Image Dedupe** to your Applications folder.

The build is ad-hoc signed and not notarized yet, so macOS blocks it until you clear the download flag. Run this once in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Image Dedupe.app"
```

Then open the app normally.

**You will need:** macOS 14 or later on an Apple silicon Mac, an unlocked iPhone that trusts this Mac on a data-capable cable, and Image Capture and Photos closed while you scan.

## Building from source

Requires macOS 14 or later and the Swift 6.2 toolchain.

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/Image Dedupe.app"
swift test
```

## Still to come

Developer ID signing and Apple notarization are not done yet — that is why the quarantine step above exists. A universal build is on the list too. (The app was formerly named iPhone Dedupe; your existing history and preferences carry across automatically.)

## License

[MIT](LICENSE)
