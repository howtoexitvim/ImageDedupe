import AppKit
import DeduperCore
import DeviceMediaKit
import XCTest
@testable import ImageDedupeApp

@MainActor
final class InspectorPreviewPipelineTests: XCTestCase {
    private struct PendingRequest {
        let token: DeviceFileToken
        let maxPixelSize: Int
        let completion: @Sendable (NSImage?) -> Void
    }

    private func item(
        _ id: String,
        width: Int? = 4_032,
        height: Int? = 3_024,
        kind: String = "HEIC"
    ) -> MediaBrowserViewModel.MediaItem {
        MediaBrowserViewModel.MediaItem(
            model: DeviceMediaFile(
                id: id,
                name: "\(id).\(kind.lowercased())",
                kind: kind,
                size: 1_000,
                timestamp: nil,
                width: width,
                height: height
            ),
            token: .fixture(name: "\(id).\(kind.lowercased())", kind: kind)
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

    func testRapidSelectionRunsAThenOnlyTheLatestC() async {
        var requests: [PendingRequest] = []
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { file, size, completion in
            requests.append(PendingRequest(token: file, maxPixelSize: size, completion: completion))
        })
        let a = item("a")
        let b = item("b")
        let c = item("c")
        viewModel.loadInspectorPreview(for: a)
        viewModel.loadInspectorPreview(for: b)
        viewModel.loadInspectorPreview(for: c)
        XCTAssertEqual(requests.count, 1)

        requests[0].completion(image(side: 1_000))
        await Task.yield()

        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].token, c.token)
        XCTAssertNotNil(viewModel.inspectorPreviewCache["a"])
        XCTAssertNil(viewModel.inspectorPreviewCache["b"])
    }

    func testReturningToCachedItemDoesNotRequestAgain() async {
        var requests: [PendingRequest] = []
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { file, size, completion in
            requests.append(PendingRequest(token: file, maxPixelSize: size, completion: completion))
        })
        let a = item("a")
        viewModel.loadInspectorPreview(for: a)
        requests[0].completion(image(side: 1_000))
        await Task.yield()

        viewModel.loadInspectorPreview(for: item("b"))
        viewModel.loadInspectorPreview(for: a)

        XCTAssertEqual(requests.count, 2)
    }

    func testOldScanGenerationCannotPublish() async {
        var completion: (@Sendable (NSImage?) -> Void)?
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { _, _, callback in
            completion = callback
        })
        viewModel.loadInspectorPreview(for: item("old"))
        XCTAssertTrue(viewModel.beginOperationForTesting(.scanning))

        completion?(image(side: 1_000))
        await Task.yield()

        XCTAssertNil(viewModel.inspectorPreviewCache["old"])
    }

    func testFailureRetriesOnlyAfterSelectionLeavesAndReturns() async {
        var requests: [PendingRequest] = []
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { file, size, completion in
            requests.append(PendingRequest(token: file, maxPixelSize: size, completion: completion))
        })
        let a = item("a")
        viewModel.loadInspectorPreview(for: a)
        requests[0].completion(nil)
        await Task.yield()
        viewModel.loadInspectorPreview(for: a)
        XCTAssertEqual(requests.count, 1)

        viewModel.loadInspectorPreview(for: item("b"))
        viewModel.loadInspectorPreview(for: a)
        XCTAssertEqual(requests.count, 2)
        requests[1].completion(nil)
        await Task.yield()

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[2].token, a.token)
    }

    func testVideoUsesTheSameStaticPreviewRequest() {
        var requestedToken: DeviceFileToken?
        let video = item("video", kind: "MOV")
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { file, _, _ in
            requestedToken = file
        })

        viewModel.loadInspectorPreview(for: video)

        XCTAssertEqual(requestedToken, video.token)
    }

    func testNineSuccessfulPreviewsEvictTheLeastRecentlyUsedID() async {
        var completions: [@Sendable (NSImage?) -> Void] = []
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { _, _, completion in
            completions.append(completion)
        })
        for index in 0..<9 {
            viewModel.loadInspectorPreview(for: item("id-\(index)", width: 100, height: 100))
            completions[index](image(side: 100))
            await Task.yield()
        }

        XCTAssertEqual(viewModel.inspectorPreviewCache.count, 8)
        XCTAssertNil(viewModel.inspectorPreviewCache["id-0"])
    }

    func testDecodedCostEvictsBeforeTheCountLimit() async {
        var completions: [@Sendable (NSImage?) -> Void] = []
        let viewModel = MediaBrowserViewModel(inspectorPreviewRequest: { _, _, completion in
            completions.append(completion)
        })
        for index in 0..<7 {
            viewModel.loadInspectorPreview(for: item("large-\(index)"))
            completions[index](image(side: 2_048))
            await Task.yield()
        }

        XCTAssertLessThan(viewModel.inspectorPreviewCache.count, 7)
        XCTAssertNil(viewModel.inspectorPreviewCache["large-0"])
    }

    func testTimeoutReleasesTheSlotAndKeepsThumbnailFallback() async throws {
        var requestCount = 0
        let viewModel = MediaBrowserViewModel(
            inspectorPreviewTimeout: .milliseconds(10),
            inspectorPreviewRequest: { _, _, _ in requestCount += 1 }
        )
        let a = item("a")
        let b = item("b")
        viewModel.thumbnailCache[a.id] = image(side: 120)
        viewModel.loadInspectorPreview(for: a)
        viewModel.loadInspectorPreview(for: b)

        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(requestCount, 2)
        XCTAssertNotNil(viewModel.inspectorPreviewImage(for: a))
    }
}
