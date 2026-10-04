import Foundation

/// The one-line index source, data/ssm-descriptions.yaml. Entries are `  /path: "text"` under a single
/// `descriptions:` key. An edit touches one line and is refused unless every other line is unchanged.
public enum Descriptions {
    /// SSM refuses a Description past this length.
    public static let maxLength = 1024

    private static let entry = try! NSRegularExpression(pattern: #"^  (/\S+?): (".*")\s*$"#)

    private static func key(of line: Substring) -> String? {
        let text = String(line)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = entry.firstMatch(in: text, range: range), let swiftRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func value(of line: Substring) -> String? {
        let text = String(line)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = entry.firstMatch(in: text, range: range), let swiftRange = Range(match.range(at: 2), in: text),
              let data = String(text[swiftRange]).data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { return nil }
        return decoded
    }

    public static func parse(_ text: String) -> [String: String] {
        var found: [String: String] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let name = key(of: line), let description = value(of: line) { found[name] = description }
        }
        return found
    }

    /// A description is one line and never a place for a secret, so collapse whitespace and refuse empty.
    public static func clean(_ description: String) -> String? {
        let collapsed = description.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func line(_ name: String, _ description: String) -> String {
        let encoded = (try? JSONSerialization.data(withJSONObject: description, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return "  \(name): \(encoded)"
    }

    /// Set one entry. Returns the new text, or nil when the edit would touch any other line.
    public static func set(_ text: String, name: String, description: String) -> String? {
        guard ParameterName.isValid(name), let clean = clean(description) else { return nil }
        var lines = text.components(separatedBy: "\n")
        let trailing = lines.last == "" ? lines.removeLast() : nil
        let others = lines.filter { key(of: $0[...]) != name }
        if let at = lines.firstIndex(where: { key(of: $0[...]) == name }) {
            lines[at] = line(name, clean)
        } else {
            let group = "/" + (name.split(separator: "/").first.map(String.init) ?? "") + "/"
            let near = lines.lastIndex { key(of: $0[...])?.hasPrefix(group) == true }
            lines.insert(line(name, clean), at: near.map { $0 + 1 } ?? lines.count)
        }
        guard lines.filter({ key(of: $0[...]) != name }) == others else { return nil }
        return (trailing == nil ? lines : lines + [""]).joined(separator: "\n")
    }

    /// Remove one entry. Returns the new text, or nil when the name is absent or another line would change.
    public static func remove(_ text: String, name: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let at = lines.firstIndex(where: { key(of: $0[...]) == name }) else { return nil }
        let before = lines
        lines.remove(at: at)
        var expected = before
        expected.remove(at: at)
        return lines == expected ? lines.joined(separator: "\n") : nil
    }
}
