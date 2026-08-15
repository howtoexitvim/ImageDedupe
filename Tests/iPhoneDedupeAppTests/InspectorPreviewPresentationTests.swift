import AppKit
import DeduperCore
import ImageCaptureCore
import XCTest
@testable import iPhoneDedupeApp

@MainActor
final class InspectorPreviewPresentationTests: XCTestCase {
    private func item(_ id: String, kind: String = "HEIC") -> MediaBrowserViewModel.MediaItem {
        MediaBrowserViewModel.MediaItem(
            model: DeviceMediaFile(
                id: id,
                name: "\(id).\(kind.lowercased())",
                kind: kind,
                size: 1_000,
                timestamp: nil,
                width: 4_032,
                height: 3_024
            ),
            token: .fixture()
        )
    }

    private func image(side: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!)
        return image
    }

    func testInspectorImagePrefersHighQualityAfterCompletion() async {
        var completion: (@Sendable (NSImage?) -> Void)?
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { _, _, callback in
            completion = callback
        })
        let item = item("photo")
        let thumbnail = image(side: 120)
        let highQuality = image(side: 1_600)
        viewModel.thumbnailCache[item.id] = thumbnail

        XCTAssertTrue(viewModel.inspectorPreviewImage(for: item) === thumbnail)
        viewModel.loadInspectorPreview(for: item)
        completion?(highQuality)
        await Task.yield()

        XCTAssertTrue(viewModel.inspectorPreviewImage(for: item) === highQuality)
    }

    func testVideoUsesTheSameStaticImagePresentation() async {
        var completion: (@Sendable (NSImage?) -> Void)?
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { _, _, callback in
            completion = callback
        })
        let video = item("video", kind: "MOV")
        let poster = image(side: 1_600)

        viewModel.loadInspectorPreview(for: video)
        completion?(poster)
        await Task.yield()

        XCTAssertTrue(viewModel.inspectorPreviewImage(for: video) === poster)
    }
}
