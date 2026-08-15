import Foundation

/// What to do when a download would land on a filename that already exists.
///
/// Downloading a duplicate group makes this the normal case rather than an edge case: the
/// copies share a name by definition, so the second one always collides with the first. The
/// old behaviour — refuse and report a POSIX error — left the user stuck exactly where the
/// app is meant to help.
///
/// Deliberately excludes a silent default. Overwriting is destructive and skipping loses
/// data the user asked for, so the choice belongs to them; `keepBoth` is merely the option
/// that discards nothing.
public enum ImportConflictResolution: String, Codable, Sendable, CaseIterable {
    /// Write alongside, giving the new file a numbered name.
    case keepBoth
    /// Replace the file already at the destination.
    case replace
    /// Leave the destination file alone and drop this copy.
    case skip

    public var title: String {
        switch self {
        case .keepBoth: return "Keep Both"
        case .replace: return "Replace"
        case .skip: return "Skip"
        }
    }

    /// Whether choosing this can destroy something already on disk.
    public var isDestructive: Bool { self == .replace }
}

/// Builds a non-colliding filename by appending a counter, the way Finder does.
///
/// `IMG_0001.HEIC` becomes `IMG_0001 2.HEIC`, then `IMG_0001 3.HEIC`. The suffix goes before
/// the extension so the file keeps its type, and therefore keeps opening in the right app.
public enum ImportFilenameDisambiguator {
    /// - Parameter isTaken: whether a candidate name is already in use. Passed in so this
    ///   stays a pure function, testable without touching a filesystem.
    public static func uniqueFilename(
        for filename: String,
        isTaken: (String) -> Bool
    ) -> String {
        guard isTaken(filename) else { return filename }

        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var counter = 2

        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !isTaken(candidate) { return candidate }
            counter += 1
            // A destination holding thousands of same-named files is not a real situation,
            // but an unbounded loop would hang the import if it ever were.
            if counter > 10_000 {
                return ext.isEmpty
                    ? "\(base) \(UUID().uuidString)"
                    : "\(base) \(UUID().uuidString).\(ext)"
            }
        }
    }
}
