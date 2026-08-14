import Foundation

public struct MediaSearchQuery: Equatable, Sendable {
    private let tokens: [Token]

    public init(_ rawValue: String) {
        tokens = rawValue
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Token(rawValue: String($0)) }
    }

    public func matches(_ file: DeviceMediaFile) -> Bool {
        tokens.allSatisfy { $0.matches(file) }
    }
}

private enum Token: Equatable, Sendable {
    case plain(String)
    case field(Field, String)
    case size(Comparison<Int64>)
    case duration(Comparison<Double>)

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let field = Field(rawValue: String(parts[0]).lowercased()) else {
            self = .plain(trimmed)
            return
        }

        let value = String(parts[1])
        switch field {
        case .name, .kind:
            self = .field(field, value)
        case .size:
            guard let comparison = Comparison<Int64>.byteCount(value) else {
                return nil
            }
            self = .size(comparison)
        case .duration:
            guard let comparison = Comparison<Double>.seconds(value) else {
                return nil
            }
            self = .duration(comparison)
        }
    }

    func matches(_ file: DeviceMediaFile) -> Bool {
        switch self {
        case .plain(let value):
            return searchableText(for: file).localizedCaseInsensitiveContains(value)
        case .field(.name, let value):
            return file.name.localizedCaseInsensitiveContains(value)
        case .field(.kind, let value):
            return file.kind.localizedCaseInsensitiveContains(value)
        case .field(.size, _), .field(.duration, _):
            return true
        case .size(let comparison):
            return comparison.matches(file.size)
        case .duration(let comparison):
            guard let duration = file.duration else {
                return false
            }
            return comparison.matches(duration)
        }
    }

    private func searchableText(for file: DeviceMediaFile) -> String {
        [
            file.name,
            file.kind,
            file.timestamp,
            file.location,
            file.width.map(String.init),
            file.height.map(String.init),
            file.duration.map { String($0) },
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

private enum Field: String, Equatable, Sendable {
    case name
    case kind
    case size
    case duration
}

private enum ComparisonOperator: Equatable, Sendable {
    case lessThan
    case greaterThan
    case equal
}

private struct Comparison<Value: Comparable & Sendable>: Equatable, Sendable {
    let operation: ComparisonOperator
    let value: Value

    func matches(_ candidate: Value) -> Bool {
        switch operation {
        case .lessThan:
            return candidate < value
        case .greaterThan:
            return candidate > value
        case .equal:
            return candidate == value
        }
    }
}

private extension Comparison where Value == Int64 {
    static func byteCount(_ rawValue: String) -> Comparison? {
        let parsed = parseOperator(rawValue)
        guard let number = Double(parsed.value) else {
            return nil
        }
        let lowercased = parsed.suffix.lowercased()
        let multiplier: Double
        switch lowercased {
        case "", "b":
            multiplier = 1
        case "k", "kb":
            multiplier = 1_000
        case "m", "mb":
            multiplier = 1_000_000
        case "g", "gb":
            multiplier = 1_000_000_000
        default:
            return nil
        }
        return Comparison(operation: parsed.operation, value: Int64((number * multiplier).rounded()))
    }
}

private extension Comparison where Value == Double {
    static func seconds(_ rawValue: String) -> Comparison? {
        let parsed = parseOperator(rawValue)
        guard let number = Double(parsed.value) else {
            return nil
        }
        let lowercased = parsed.suffix.lowercased()
        let multiplier: Double
        switch lowercased {
        case "", "s", "sec", "secs":
            multiplier = 1
        case "m", "min", "mins":
            multiplier = 60
        case "h", "hr", "hrs":
            multiplier = 3600
        default:
            return nil
        }
        return Comparison(operation: parsed.operation, value: number * multiplier)
    }
}

private func parseOperator(_ rawValue: String) -> (operation: ComparisonOperator, value: String, suffix: String) {
    let operation: ComparisonOperator
    let valueAndSuffix: String
    if rawValue.hasPrefix(">") {
        operation = .greaterThan
        valueAndSuffix = String(rawValue.dropFirst())
    } else if rawValue.hasPrefix("<") {
        operation = .lessThan
        valueAndSuffix = String(rawValue.dropFirst())
    } else {
        operation = .equal
        valueAndSuffix = rawValue
    }

    let splitIndex = valueAndSuffix.firstIndex { !$0.isNumber && $0 != "." } ?? valueAndSuffix.endIndex
    let value = String(valueAndSuffix[..<splitIndex])
    let suffix = String(valueAndSuffix[splitIndex...])
    return (operation, value, suffix)
}
