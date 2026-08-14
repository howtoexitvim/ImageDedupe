public enum DuplicatePlanner {
    public static func plan(files: [DeviceMediaFile], rule: DuplicateRule) -> DuplicatePlan {
        plan(files: files, definition: rule.definition)
    }

    public static func plan(files: [DeviceMediaFile], definition: DuplicateRuleDefinition) -> DuplicatePlan {
        var seen: [String: DeviceMediaFile] = [:]
        var keep: [DeviceMediaFile] = []
        var delete: [DeviceMediaFile] = []

        for file in files {
            guard let key = definition.key(for: file) else {
                keep.append(file)
                continue
            }

            if seen[key] != nil {
                delete.append(file)
            } else {
                seen[key] = file
                keep.append(file)
            }
        }

        return DuplicatePlan(keep: keep, delete: delete)
    }
}
