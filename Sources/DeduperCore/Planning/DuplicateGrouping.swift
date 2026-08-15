import Foundation

/// Duplicate sets, with every copy present and the surviving one marked.
///
/// Duplicates previously listed only the redundant copies. That hid the copy the app
/// intends to keep, which made the question that actually matters before a delete — *which
/// one survives?* — impossible to answer inside the app, and left no way to compare a
/// file's metadata against its twin.
///
/// Showing every copy risks the opposite problem: a hundred groups becoming a hundred
/// decisions. Grouping is what avoids that. The copies sit next to each other under a
/// header, and the delete selection still defaults to exactly the redundant ones, so the
/// common case stays "review the groups, press Delete" while the detail is there when
/// wanted.
public enum DuplicateGrouping {
    public struct Member: Equatable, Sendable {
        public let file: DeviceMediaFile
        /// True for the one copy the plan keeps. Exactly one member of a group is kept.
        public let isKept: Bool

        public init(file: DeviceMediaFile, isKept: Bool) {
            self.file = file
            self.isKept = isKept
        }
    }

    public struct Group: Equatable, Sendable, Identifiable {
        /// The rule key shared by every member, which is stable for a given catalog and rule.
        public let id: String
        public let members: [Member]

        public init(id: String, members: [Member]) {
            self.id = id
            self.members = members
        }

        public var keptFile: DeviceMediaFile? {
            members.first(where: \.isKept)?.file
        }

        public var redundantFiles: [DeviceMediaFile] {
            members.filter { !$0.isKept }.map(\.file)
        }

        /// Header text, so one group can be told from the next while scrolling.
        public var title: String {
            let name = members.first?.file.name ?? "Unknown"
            return "\(name) — \(members.count) copies"
        }
    }

    /// Groups of two or more files that the rule considers the same.
    ///
    /// Ordered by each group's first appearance in `files`, and members within a group keep
    /// their catalog order, so the flattened sequence is stable and a group's members are
    /// always adjacent. A file with no twin is excluded: Duplicates is a review list, not a
    /// second All Media.
    public static func groups(
        files: [DeviceMediaFile],
        definition: DuplicateRuleDefinition
    ) -> [Group] {
        var order: [String] = []
        var byKey: [String: [DeviceMediaFile]] = [:]

        for file in files {
            // A file missing any field the rule needs is never grouped, so two absent
            // timestamps cannot match each other.
            guard let key = definition.key(for: file) else { continue }
            if byKey[key] == nil {
                byKey[key] = []
                order.append(key)
            }
            byKey[key]?.append(file)
        }

        return order.compactMap { key in
            guard let members = byKey[key], members.count > 1 else { return nil }
            return Group(
                id: key,
                // The first occurrence is the keeper, matching `DuplicatePlanner`, so the
                // group view and the delete plan cannot disagree about which copy survives.
                members: members.enumerated().map { index, file in
                    Member(file: file, isKept: index == 0)
                }
            )
        }
    }

    /// The redundant copies across every group: what Delete acts on unless the user changes
    /// it. Never includes a keeper.
    public static func defaultSelection(in groups: [Group]) -> Set<String> {
        Set(groups.flatMap { $0.redundantFiles.map(\.id) })
    }

    /// Every file shown in the grouped view, in display order.
    public static func flattened(_ groups: [Group]) -> [DeviceMediaFile] {
        groups.flatMap { $0.members.map(\.file) }
    }
}
