import DeviceMediaKit
import Foundation

extension DeviceFileToken {
    static func fixture(
        generation: UUID = UUID(),
        objectHandle: UInt32 = 1,
        name: String = "fixture.heic",
        kind: String = "HEIC",
        size: Int64 = 1_000
    ) -> DeviceFileToken {
        DeviceFileToken(
            generation: generation,
            objectHandle: objectHandle,
            fingerprint: DeviceFileFingerprint(
                name: name,
                kind: kind,
                size: size,
                timestamp: nil
            )
        )
    }
}
