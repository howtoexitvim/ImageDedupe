import DeduperCore
import Foundation
import XCTest

@testable import DeviceMediaKit

/// The app talks to the device helper over newline-delimited JSON on a pipe. Pipes split
/// wherever they like, so the framing has to survive partial lines, several lines in one
/// read, and empty lines — and the messages have to round-trip exactly, because a token
/// that decodes even slightly differently resolves to a different file.
final class HelperProtocolTests: XCTestCase {
    private func makeToken(name: String = "IMG_0001.HEIC", handle: UInt32 = 7) -> DeviceFileToken {
        DeviceFileToken(
            generation: UUID(),
            objectHandle: handle,
            fingerprint: DeviceFileFingerprint(
                name: name,
                kind: "HEIC",
                size: 2_048,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }

    // MARK: - Framing

    func testSplitsCompleteLinesAndKeepsTheRemainder() {
        var buffer = Data("one\ntwo\npartial".utf8)
        let lines = HelperCodec.lines(from: &buffer)

        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["one", "two"])
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "partial")
    }

    /// A pipe may deliver a message in pieces. Prepending the remainder must reassemble it.
    func testReassemblesAMessageSplitAcrossTwoReads() {
        var buffer = Data("firs".utf8)
        XCTAssertTrue(HelperCodec.lines(from: &buffer).isEmpty)

        buffer.append(Data("t\nsecond\n".utf8))
        let lines = HelperCodec.lines(from: &buffer)

        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["first", "second"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testSkipsEmptyLinesRatherThanEmittingUndecodableBlanks() {
        var buffer = Data("a\n\n\nb\n".utf8)
        let lines = HelperCodec.lines(from: &buffer)
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["a", "b"])
    }

    func testEncodedMessagesAreExactlyOneLineEach() throws {
        let encoded = try HelperCodec.encode(HelperRequest.cancel)
        XCTAssertEqual(encoded.last, 0x0A)
        XCTAssertEqual(encoded.filter { $0 == 0x0A }.count, 1)
    }

    // MARK: - Round trips

    /// The token is the part that must survive byte-exactly: it is what the helper uses to
    /// resolve an `ICCameraFile`, and a delete resolving the wrong file is unrecoverable.
    func testTokenSurvivesARoundTripExactly() throws {
        let token = makeToken()
        let request = HelperRequest.delete(tokens: [token], confirmed: true, timeoutSeconds: 30)

        var buffer = try HelperCodec.encode(request)
        let line = try XCTUnwrap(HelperCodec.lines(from: &buffer).first)
        let decoded = try HelperCodec.decode(HelperRequest.self, from: line)

        guard case let .delete(tokens, confirmed, timeout) = decoded else {
            return XCTFail("Expected a delete request, got \(decoded)")
        }
        XCTAssertEqual(tokens, [token])
        XCTAssertTrue(confirmed)
        XCTAssertEqual(timeout, 30)
    }

    func testDeleteSummaryCarriesObservedRemovalEvidenceSeparately() throws {
        let deleted = makeToken(name: "IMG_0001.HEIC", handle: 7)
        let summary = DeviceGatewayDeleteSummary(successful: [deleted])

        var buffer = try HelperCodec.encode(
            HelperResponse.deleted(summary: summary, observedRemovedHandles: [7, 9])
        )
        let line = try XCTUnwrap(HelperCodec.lines(from: &buffer).first)
        let decoded = try HelperCodec.decode(HelperResponse.self, from: line)

        guard case let .deleted(roundTripped, handles) = decoded else {
            return XCTFail("Expected a deleted response, got \(decoded)")
        }
        XCTAssertEqual(roundTripped.successful, [deleted])
        // Framework success and device-observed removal stay distinguishable across the
        // wire; collapsing them would let an unverified delete read as confirmed. The
        // delete completion callback has been seen claiming success for a file that a
        // fresh scan showed still present, so the reconciler needs both, separately.
        XCTAssertEqual(handles, [7, 9])
    }

    func testCatalogSnapshotSurvivesARoundTrip() throws {
        let token = makeToken()
        let snapshot = DeviceCatalogSnapshot(
            generation: token.generation,
            deviceName: "shuqi's iPhone",
            deviceIdentityHash: "abc123",
            files: [DeviceCatalogFile(
                model: DeviceMediaFile(
                    id: "1",
                    name: "IMG_0001.HEIC",
                    kind: "HEIC",
                    size: 2_048,
                    timestamp: "2026-08-15T00:00:00.000Z",
                    width: 4_032,
                    height: 3_024
                ),
                token: token
            )]
        )

        var buffer = try HelperCodec.encode(HelperResponse.scanned(snapshot: snapshot))
        let line = try XCTUnwrap(HelperCodec.lines(from: &buffer).first)
        let decoded = try HelperCodec.decode(HelperResponse.self, from: line)

        guard case let .scanned(roundTripped) = decoded else {
            return XCTFail("Expected a scanned response, got \(decoded)")
        }
        XCTAssertEqual(roundTripped, snapshot)
    }

    // MARK: - Correlation

    /// The defect behind two reports on 2026-08-15: Import failing with "the device helper
    /// sent an unexpected response", and a tile showing another tile's picture.
    ///
    /// The app issues many requests at once on one pipe — a thumbnail per visible tile, the
    /// inspector preview, metadata, sometimes a download. Every waiter took the *next*
    /// response to arrive, so replies were matched to whichever request happened to be
    /// waiting rather than to the one that asked. An envelope id makes a reply belong to
    /// exactly one request.
    func testResponsesCarryTheIdOfTheRequestTheyAnswer() throws {
        let thumbnailID = UUID()
        let downloadID = UUID()

        var buffer = Data()
        buffer.append(try HelperCodec.encode(HelperResponseEnvelope(
            id: downloadID,
            payload: .downloaded(summary: DeviceGatewayImportSummary())
        )))
        buffer.append(try HelperCodec.encode(HelperResponseEnvelope(
            id: thumbnailID,
            payload: .thumbnail(data: Data([0x01, 0x02]))
        )))

        let decoded = try HelperCodec.lines(from: &buffer).map {
            try HelperCodec.decode(HelperResponseEnvelope.self, from: $0)
        }

        // The download's reply arrives first even though the thumbnail may have been
        // requested first. Each is still attributable to its own request.
        XCTAssertEqual(decoded[0].id, downloadID)
        XCTAssertEqual(decoded[1].id, thumbnailID)
        guard case .thumbnail = decoded[1].payload else {
            return XCTFail("The thumbnail reply lost its payload")
        }
    }

    func testRequestEnvelopePreservesItsPayloadExactly() throws {
        let id = UUID()
        let token = makeToken()
        var buffer = try HelperCodec.encode(HelperRequestEnvelope(
            id: id,
            payload: .thumbnail(token: token, maxPixelSize: 512, timeoutSeconds: 6)
        ))

        let line = try XCTUnwrap(HelperCodec.lines(from: &buffer).first)
        let decoded = try HelperCodec.decode(HelperRequestEnvelope.self, from: line)

        XCTAssertEqual(decoded.id, id)
        guard case let .thumbnail(decodedToken, maxPixelSize, _) = decoded.payload else {
            return XCTFail("Expected a thumbnail request, got \(decoded.payload)")
        }
        XCTAssertEqual(decodedToken, token)
        XCTAssertEqual(maxPixelSize, 512)
    }

    /// A cancellation must stay distinguishable from a genuine failure: one is the user's
    /// own doing and is retryable, the other needs reporting.
    func testCancellationIsDistinguishableFromFailure() throws {
        var buffer = try HelperCodec.encode(
            HelperResponse.failed(message: "canceled", isCancellation: true)
        )
        let line = try XCTUnwrap(HelperCodec.lines(from: &buffer).first)
        let decoded = try HelperCodec.decode(HelperResponse.self, from: line)

        guard case let .failed(_, isCancellation) = decoded else {
            return XCTFail("Expected a failed response, got \(decoded)")
        }
        XCTAssertTrue(isCancellation)
    }

    // MARK: - Packaging

    /// Both bundle scripts must ship the helper, and sign it before the app that encloses it.
    ///
    /// Found on 2026-08-16: `build-debug-app.sh` was updated when the helper was introduced
    /// and `build-release-candidate.sh` was not, so a release bundle contained only
    /// `iPhoneDedupeApp`. Every scan in that build would fail, because scanning *is* a helper
    /// process — and nothing in the test suite would have noticed, since the tests exercise
    /// the source rather than the packaged bundle.
    func testBothBundleScriptsShipAndSignTheHelper() throws {
        let scripts = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts")

        for name in ["build-debug-app.sh", "build-release-candidate.sh"] {
            let text = try String(
                contentsOf: scripts.appendingPathComponent(name),
                encoding: .utf8
            )

            XCTAssertTrue(
                text.contains("iPhoneDedupeHelper"),
                "\(name) must copy the helper, or every scan in that bundle fails."
            )

            // Nested code has to be signed first: signing the outer bundle seals the
            // helper's signature, so the reverse order invalidates the app.
            guard let helperSigning = text.range(of: "codesign")
                .flatMap({ _ in text.range(of: "MacOS/iPhoneDedupeHelper\"", options: .backwards) })
            else {
                return XCTFail("\(name) must sign the helper explicitly.")
            }
            let outerSigning = try XCTUnwrap(
                text.range(of: "\"$app_path\"", options: .backwards),
                "\(name) must sign the app bundle."
            )
            XCTAssertLessThan(
                helperSigning.lowerBound,
                outerSigning.lowerBound,
                "\(name) must sign the helper before the enclosing bundle."
            )
        }
    }
}
