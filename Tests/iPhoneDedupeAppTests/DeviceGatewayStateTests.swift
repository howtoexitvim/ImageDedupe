import DeduperCore
@preconcurrency import ImageCaptureCore
import XCTest
@testable import DeviceMediaKit

@MainActor
final class DeviceGatewayStateTests: XCTestCase {
    func testFrameworkCallbackBridgeHopsFromPrivateQueueToMainActor() async {
        let delivered = expectation(description: "callback delivered")
        var received: String?
        let callback: @Sendable (String?, Error?) -> Void = DeviceFrameworkCallbackBridge.hop(
            transform: { filename, error in
                filename ?? error?.localizedDescription ?? "missing"
            },
            deliver: { value in
                MainActor.preconditionIsolated()
                received = value
                delivered.fulfill()
            }
        )

        DispatchQueue(label: "test.image-capture-private-queue").async {
            callback("IMG_0001.HEIC", nil)
        }

        await fulfillment(of: [delivered], timeout: 1)
        XCTAssertEqual(received, "IMG_0001.HEIC")
    }

    func testCatalogIndexKeepsBothFilesSharingATokenWithoutTrapping() {
        let generation = UUID()
        let token = DeviceFileToken(
            generation: generation,
            objectHandle: 42,
            fingerprint: DeviceFileFingerprint(
                name: "IMG_0042.HEIC",
                kind: "HEIC",
                size: 100,
                timestamp: nil
            )
        )
        let first = DeviceCatalogFile(
            model: makeModel(id: "first", name: "IMG_0042.HEIC"),
            token: token
        )
        let repeated = DeviceCatalogFile(
            model: makeModel(id: "repeated", name: "IMG_0042.HEIC"),
            token: token
        )
        var index = DeviceCatalogIndex()

        // Both are kept. A shared token no longer implies one file reported twice: on a
        // device that assigns no object handles, a token degenerates to its fingerprint, so
        // two real duplicates share one. Dropping the second hid the very files this app
        // exists to find — 26 of them on the device reported on 2026-08-16.
        XCTAssertTrue(index.insert(first))
        XCTAssertTrue(index.insert(repeated))
        XCTAssertEqual(index.files.count, 2)
        XCTAssertEqual(Set(index.files.map(\.model.id)).count, 2, "Ids stay unique.")
        // The token still resolves to a filename for download and delete.
        XCTAssertEqual(index.filenamesByToken, [token: "IMG_0042.HEIC"])
    }

    func testTransientUnlockOpenErrorRetriesOnTheSameDevice() async {
        let gateway = ImageCaptureDeviceGateway(openSessionRetryDelay: .milliseconds(1))
        let camera = OpenSessionRecordingCameraDevice()
        gateway.deviceBrowser(ICDeviceBrowser(), didAdd: camera, moreComing: false)
        XCTAssertEqual(camera.openSessionRequestCount, 1)

        gateway.device(
            camera,
            didOpenSessionWithError: NSError(
                domain: "com.apple.ImageCaptureCore",
                code: -9943,
                userInfo: [NSLocalizedDescriptionKey: "Please unlock \"Test iPhone\""]
            )
        )

        await waitUntil { camera.openSessionRequestCount == 2 }
        XCTAssertEqual(camera.openSessionRequestCount, 2)
    }

    func testCatalogSnapshotContainsOnlyPureModelsAndTokens() throws {
        let generation = UUID()
        let model = makeModel(id: "device-42", name: "IMG_0042.HEIC")
        let token = DeviceFileToken(
            generation: generation,
            objectHandle: 42,
            fingerprint: DeviceFileFingerprint(
                name: model.name,
                kind: model.kind,
                size: model.size,
                timestamp: nil
            )
        )
        let snapshot = DeviceCatalogSnapshot(
            generation: generation,
            deviceName: "Test iPhone",
            files: [DeviceCatalogFile(model: model, token: token)]
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DeviceCatalogSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.files.first?.token.generation, decoded.generation)
    }

    func testOneShotCallbackAcceptsOnlyMatchingFirstCompletion() async throws {
        let callback = DeviceOneShotCallback<String>()
        var token: UUID?

        let valueTask = Task {
            try await callback.wait(timeout: .seconds(1)) { token = $0 }
        }
        await waitUntil { token != nil }
        let requestToken = try XCTUnwrap(token)

        callback.complete(token: UUID(), result: .success("wrong"))
        callback.complete(token: requestToken, result: .success("first"))
        callback.complete(token: requestToken, result: .success("late"))

        let value = try await valueTask.value
        XCTAssertEqual(value, "first")
    }

    func testOneShotCallbackTimeoutRunsAbortBeforeReturningAndIgnoresLateCompletion() async {
        let callback = DeviceOneShotCallback<String>()
        var token: UUID?
        var timeoutRequested = false
        var abortFinished = false

        let valueTask = Task {
            return try await callback.wait(
                timeout: .milliseconds(1),
                onTimeout: {
                    timeoutRequested = true
                    await Task.yield()
                    abortFinished = true
                }
            ) { token = $0 }
        }
        await waitUntil { token != nil }
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertTrue(timeoutRequested)
        XCTAssertTrue(abortFinished)

        do {
            _ = try await valueTask.value
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? DeviceCallbackError, .timedOut)
        }
        callback.complete(token: token!, result: .success("late framework completion"))
        XCTAssertFalse(callback.isPending)
    }

    func testOneShotTaskCancellationRunsAbortBeforeReturning() async {
        let callback = DeviceOneShotCallback<String>()
        var token: UUID?
        var cancellationRequested = false
        let valueTask = Task {
            return try await callback.wait(
                timeout: .seconds(1),
                onCancel: {
                    await Task.yield()
                    cancellationRequested = true
                }
            ) { token = $0 }
        }
        await waitUntil { token != nil }

        valueTask.cancel()
        await waitUntil { cancellationRequested }

        do {
            _ = try await valueTask.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? DeviceCallbackError, .canceled)
        }
        callback.complete(token: token!, result: .success("late framework completion"))
        XCTAssertFalse(callback.isPending)
    }

    private func makeModel(id: String, name: String) -> DeviceMediaFile {
        DeviceMediaFile(
            id: id,
            name: name,
            kind: "HEIC",
            size: 100,
            timestamp: nil,
            width: 100,
            height: 100
        )
    }

    private func waitUntil(
        attempts: Int = 1_000,
        condition: () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<attempts {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Condition was not satisfied", file: file, line: line)
    }
}

@MainActor
private final class OpenSessionRecordingCameraDevice: ICCameraDevice {
    nonisolated(unsafe) private(set) var openSessionRequestCount = 0

    override func requestOpenSession() {
        openSessionRequestCount += 1
    }
}
