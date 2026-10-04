import Foundation

public enum SecretAlphabet: String, CaseIterable, Identifiable, Sendable {
    case alphanumeric, hex, urlSafe

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alphanumeric: "Letters and digits"
        case .hex: "Hexadecimal"
        case .urlSafe: "URL safe"
        }
    }

    var characters: [Character] {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        let digits = Array("0123456789")
        switch self {
        case .alphanumeric: return letters + digits
        case .hex: return Array("0123456789abcdef")
        case .urlSafe: return letters + digits + ["-", "_"]
        }
    }
}

public enum Secrets {
    public static let lengths = 16...128

    /// SystemRandomNumberGenerator is the OS CSPRNG, so each character is a uniform, unpredictable pick.
    public static func generate(length: Int, alphabet: SecretAlphabet) -> String? {
        guard lengths.contains(length) else { return nil }
        let pool = alphabet.characters
        return String((0..<length).map { _ in pool.randomElement()! })
    }

    /// A value typed or pasted into a form usually carries one trailing newline from an editor.
    /// This is the same rule as `just ssm-stash`: strip exactly one.
    public static func stripTrailingNewline(_ value: String) -> String {
        // "\r\n" is one Character in Swift, so dropLast() removes the whole newline and never a value character.
        value.hasSuffix("\n") || value.hasSuffix("\r\n") ? String(value.dropLast()) : value
    }
}

public enum AwsProfiles {
    /// Profile names from ~/.aws/config. `[default]` and `[profile x]` count, `[sso-session x]` does not.
    public static func names(in config: String) -> [String] {
        var found: [String] = []
        for raw in config.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), line.hasSuffix("]") else { continue }
            let inner = line.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            if inner == "default" { found.append("default") }
            else if inner.hasPrefix("profile ") { found.append(inner.dropFirst("profile ".count).trimmingCharacters(in: .whitespaces)) }
        }
        return found
    }

    public static func configured() -> [String] {
        let path = ProcessInfo.processInfo.environment["AWS_CONFIG_FILE"] ?? NSHomeDirectory() + "/.aws/config"
        return (try? String(contentsOfFile: path, encoding: .utf8)).map(names) ?? []
    }

    /// An SSO role name tells a read-only session from an admin one. Unknown stays unknown.
    public static func access(of arn: String) -> String? {
        let lowered = arn.lowercased()
        if lowered.contains("readonly") { return "read-only" }
        if lowered.contains("administrator") || lowered.contains("admin") { return "admin" }
        return nil
    }
}
