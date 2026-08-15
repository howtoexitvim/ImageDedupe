import Darwin
import Foundation

public enum DestinationCommitError: Error, Equatable, LocalizedError, Sendable {
    case unsafeFilename
    case destinationUnavailable
    case destinationChanged
    case stagingChanged
    case stagedFileInvalid
    case insufficientSpace(requiredBytes: Int64, availableBytes: Int64)
    case collision
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeFilename:
            return "The device returned an unsafe filename."
        case .destinationUnavailable:
            return "The selected destination is not an available real directory."
        case .destinationChanged:
            return "The selected destination changed after preflight."
        case .stagingChanged:
            return "The private staging directory changed before the download could be committed."
        case .stagedFileInvalid:
            return "The staged download is missing, a symbolic link, or not a regular file."
        case .insufficientSpace(let requiredBytes, let availableBytes):
            return "The destination no longer has enough free space (needs \(requiredBytes) bytes, has \(availableBytes) bytes)."
        case .collision:
            return "A file with this name already exists. Nothing was overwritten."
        case .io(let message):
            return message
        }
    }
}

public struct StagedFileIdentity: Equatable, Codable, Sendable {
    let volumeNumber: UInt64
    let fileNumber: UInt64
    let size: Int64

    public static func capture(
        filename: String,
        stagingDirectory: URL,
        stagingIdentity: ImportDestinationIdentity
    ) throws -> StagedFileIdentity {
        guard DestinationCommitter.isSafeLastPathComponent(filename) else {
            throw DestinationCommitError.unsafeFilename
        }
        let directoryFD = open(stagingDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw DestinationCommitError.stagedFileInvalid }
        defer { close(directoryFD) }
        do {
            try stagingIdentity.validate(fileDescriptor: directoryFD)
        } catch {
            throw DestinationCommitError.stagingChanged
        }
        let fileFD = filename.withCString { openat(directoryFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fileFD >= 0 else { throw DestinationCommitError.stagedFileInvalid }
        defer { close(fileFD) }
        var fileStatus = stat()
        guard fstat(fileFD, &fileStatus) == 0, (fileStatus.st_mode & S_IFMT) == S_IFREG else {
            throw DestinationCommitError.stagedFileInvalid
        }
        return StagedFileIdentity(
            volumeNumber: UInt64(fileStatus.st_dev),
            fileNumber: UInt64(fileStatus.st_ino),
            size: Int64(fileStatus.st_size)
        )
    }

    func validate(fileDescriptor: Int32) throws {
        var fileStatus = stat()
        guard fstat(fileDescriptor, &fileStatus) == 0,
              (fileStatus.st_mode & S_IFMT) == S_IFREG,
              UInt64(fileStatus.st_dev) == volumeNumber,
              UInt64(fileStatus.st_ino) == fileNumber,
              Int64(fileStatus.st_size) == size else {
            throw DestinationCommitError.stagedFileInvalid
        }
    }
}

public enum DestinationCommitter {
    public static func commit(
        stagedFilename: String,
        stagingDirectory: URL,
        stagingIdentity: ImportDestinationIdentity,
        stagedIdentity: StagedFileIdentity,
        filename: String,
        destination: URL,
        destinationIdentity: ImportDestinationIdentity
    ) throws -> URL {
        guard isSafeLastPathComponent(stagedFilename), isSafeLastPathComponent(filename) else {
            throw DestinationCommitError.unsafeFilename
        }

        let stagingFD = open(stagingDirectory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard stagingFD >= 0 else {
            throw DestinationCommitError.stagedFileInvalid
        }
        defer { close(stagingFD) }
        do {
            try stagingIdentity.validate(fileDescriptor: stagingFD)
        } catch {
            throw DestinationCommitError.stagingChanged
        }

        let destinationFD = open(destination.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard destinationFD >= 0 else {
            throw DestinationCommitError.destinationUnavailable
        }
        defer { close(destinationFD) }
        do {
            try destinationIdentity.validate(fileDescriptor: destinationFD)
        } catch {
            throw DestinationCommitError.destinationChanged
        }

        let sourceFD = stagedFilename.withCString {
            openat(stagingFD, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard sourceFD >= 0 else {
            throw DestinationCommitError.stagedFileInvalid
        }
        defer { close(sourceFD) }
        var sourceStat = stat()
        guard fstat(sourceFD, &sourceStat) == 0, (sourceStat.st_mode & S_IFMT) == S_IFREG else {
            throw DestinationCommitError.stagedFileInvalid
        }
        try stagedIdentity.validate(fileDescriptor: sourceFD)
        var filesystem = statfs()
        guard fstatfs(destinationFD, &filesystem) == 0 else {
            throw posixError(defaultError: .destinationUnavailable)
        }
        let availableBlocks = UInt64(filesystem.f_bavail)
        let blockSize = UInt64(filesystem.f_bsize)
        let multiplied = availableBlocks.multipliedReportingOverflow(by: blockSize)
        let availableBytes = multiplied.overflow
            ? Int64.max
            : Int64(clamping: multiplied.partialValue)
        let requiredBytes = Int64(sourceStat.st_size)
        guard hasSufficientCapacity(requiredBytes: requiredBytes, availableBytes: availableBytes) else {
            throw DestinationCommitError.insufficientSpace(
                requiredBytes: requiredBytes,
                availableBytes: availableBytes
            )
        }

        let temporaryName = ".iphone-dedupe-commit-\(UUID().uuidString)"
        let temporaryFD = temporaryName.withCString {
            openat(destinationFD, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        }
        guard temporaryFD >= 0 else {
            throw posixError(defaultError: .destinationUnavailable)
        }
        var temporaryExists = true
        defer {
            close(temporaryFD)
            if temporaryExists {
                temporaryName.withCString { _ = unlinkat(destinationFD, $0, 0) }
            }
        }

        try copyAll(from: sourceFD, to: temporaryFD)
        guard fsync(temporaryFD) == 0 else {
            throw posixError(defaultError: .io("Could not flush the staged download."))
        }

        let renameResult = temporaryName.withCString { temporaryPointer in
            filename.withCString { filenamePointer in
                renameatx_np(
                    destinationFD,
                    temporaryPointer,
                    destinationFD,
                    filenamePointer,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            throw posixError(defaultError: .io("Could not publish the downloaded file."))
        }
        temporaryExists = false
        guard fsync(destinationFD) == 0 else {
            throw posixError(defaultError: .io("Could not flush the destination directory."))
        }

        let unlinkResult = stagedFilename.withCString { unlinkat(stagingFD, $0, 0) }
        guard unlinkResult == 0 else {
            throw posixError(defaultError: .io("The download was committed but staging cleanup failed."))
        }
        return destination.appendingPathComponent(filename, isDirectory: false)
    }

    private static func copyAll(from sourceFD: Int32, to destinationFD: Int32) throws {
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let bytesRead = read(sourceFD, &buffer, buffer.count)
            if bytesRead == 0 { return }
            guard bytesRead > 0 else {
                if errno == EINTR { continue }
                throw posixError(defaultError: .io("Could not read the staged download."))
            }
            var written = 0
            while written < bytesRead {
                let result = buffer.withUnsafeBytes { bytes in
                    write(destinationFD, bytes.baseAddress!.advanced(by: written), bytesRead - written)
                }
                guard result >= 0 else {
                    if errno == EINTR { continue }
                    throw posixError(defaultError: .io("Could not write the destination file."))
                }
                written += result
            }
        }
    }

    static func hasSufficientCapacity(requiredBytes: Int64, availableBytes: Int64) -> Bool {
        requiredBytes >= 0 && availableBytes >= requiredBytes
    }

    static func isSafeLastPathComponent(_ filename: String) -> Bool {
        !filename.isEmpty
            && filename != "."
            && filename != ".."
            && !filename.hasPrefix("/")
            && !filename.contains("/")
            && !filename.contains("\\")
            && filename.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && URL(fileURLWithPath: filename).lastPathComponent == filename
    }

    private static func posixError(defaultError: DestinationCommitError) -> DestinationCommitError {
        if errno == EEXIST { return .collision }
        if errno == ELOOP { return .destinationUnavailable }
        let message = String(cString: strerror(errno))
        if case .io(let context) = defaultError {
            return .io("\(context) \(message)")
        }
        return defaultError
    }
}
