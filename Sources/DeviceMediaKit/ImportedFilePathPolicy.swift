import Foundation

public enum ImportedFilePathError: Error, Equatable, LocalizedError {
    case unsafeFilename
    case destinationUnavailable
    case destinationChanged
    case outputMissingOrNotRegular
    case symbolicLink
    case destinationEscape

    public var errorDescription: String? {
        switch self {
        case .unsafeFilename:
            return "The device returned an unsafe download filename."
        case .destinationUnavailable:
            return "The download destination is no longer an available folder."
        case .destinationChanged:
            return "The download destination changed after it was checked."
        case .outputMissingOrNotRegular:
            return "The downloaded item is missing or is not a regular file."
        case .symbolicLink:
            return "The downloaded item resolves through a symbolic link."
        case .destinationEscape:
            return "The downloaded item is outside the selected destination."
        }
    }
}

public struct ImportDestinationIdentity: Equatable, Sendable {
    private let canonicalPath: String
    private let volumeNumber: UInt64
    private let fileNumber: UInt64

    public static func capture(destination: URL) throws -> ImportDestinationIdentity {
        let canonical = destination.resolvingSymlinksInPath().standardizedFileURL
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: canonical.path)
        } catch {
            throw ImportedFilePathError.destinationUnavailable
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              let volumeNumber = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else {
            throw ImportedFilePathError.destinationUnavailable
        }
        return ImportDestinationIdentity(
            canonicalPath: canonical.path,
            volumeNumber: volumeNumber,
            fileNumber: fileNumber
        )
    }

    public func validate(destination: URL) throws {
        let current = try Self.capture(destination: destination)
        guard current == self else {
            throw ImportedFilePathError.destinationChanged
        }
    }

    func validate(fileDescriptor: Int32) throws {
        var status = stat()
        guard fstat(fileDescriptor, &status) == 0 else {
            throw ImportedFilePathError.destinationUnavailable
        }
        guard UInt64(status.st_dev) == volumeNumber,
              UInt64(status.st_ino) == fileNumber else {
            throw ImportedFilePathError.destinationChanged
        }
    }
}

public enum ImportedFilePathPolicy {
    public static func validateCompletedDownload(
        callbackFilename: String,
        destination: URL
    ) throws -> URL {
        guard isSafeLastPathComponent(callbackFilename) else {
            throw ImportedFilePathError.unsafeFilename
        }

        let destinationValues: URLResourceValues
        do {
            destinationValues = try destination.resourceValues(forKeys: [.isDirectoryKey])
        } catch {
            throw ImportedFilePathError.destinationUnavailable
        }
        guard destinationValues.isDirectory == true else {
            throw ImportedFilePathError.destinationUnavailable
        }

        let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL
        let output = canonicalDestination
            .appendingPathComponent(callbackFilename, isDirectory: false)
            .standardizedFileURL
        guard output.deletingLastPathComponent().path == canonicalDestination.path else {
            throw ImportedFilePathError.destinationEscape
        }

        let outputValues: URLResourceValues
        do {
            outputValues = try output.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            throw ImportedFilePathError.outputMissingOrNotRegular
        }
        guard outputValues.isSymbolicLink != true else {
            throw ImportedFilePathError.symbolicLink
        }
        guard outputValues.isRegularFile == true else {
            throw ImportedFilePathError.outputMissingOrNotRegular
        }

        let resolvedOutput = output.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedOutput.deletingLastPathComponent().path == canonicalDestination.path else {
            throw ImportedFilePathError.destinationEscape
        }
        return resolvedOutput
    }

    private static func isSafeLastPathComponent(_ filename: String) -> Bool {
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              !filename.hasPrefix("/"),
              !filename.contains("/"),
              !filename.contains("\\"),
              filename.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }
        return URL(fileURLWithPath: filename).lastPathComponent == filename
    }
}
