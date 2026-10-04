import Foundation

/// A classified AWS failure. The message is ours, never the CLI's, so it cannot carry a value.
public struct AwsFailure: Error, Equatable, Sendable {
    public enum Kind: Sendable { case notFound, exists, denied, noSession, other }
    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public static func classify(stderr: String) -> AwsFailure {
        let lowered = stderr.lowercased()
        if stderr.contains("(ParameterNotFound)") {
            return AwsFailure(kind: .notFound, message: "No such parameter.")
        }
        if stderr.contains("(ParameterAlreadyExists)") {
            return AwsFailure(kind: .exists, message: "That parameter already exists.")
        }
        if stderr.contains("(AccessDeniedException)") || stderr.contains("(UnauthorizedOperation)") {
            return AwsFailure(kind: .denied, message: "AWS denied this. A write needs the admin profile.")
        }
        if lowered.contains("expired") || lowered.contains("sso") || lowered.contains("unable to locate credentials")
            || lowered.contains("token has expired") {
            return AwsFailure(kind: .noSession, message: "No valid AWS session. Sign in, then retry.")
        }
        return AwsFailure(kind: .other, message: "The aws CLI failed.")
    }
}

public struct ParameterInfo: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    public let type: String
    public let version: Int
    public let modified: String?
    /// SSM's own Description field, so a description travels with the parameter and needs no checkout.
    public let description: String?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "Name", type = "Type", version = "Version", modified = "LastModifiedDate", description = "Description"
    }

    public init(name: String, type: String, version: Int, modified: String?, description: String? = nil) {
        self.name = name
        self.type = type
        self.version = version
        self.modified = modified
        self.description = description
    }

    public var modifiedDate: Date? {
        guard let modified else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: modified) ?? ISO8601DateFormatter().date(from: modified)
    }
}

public struct RevealedValue: Sendable {
    public let value: String
    public let type: String
    public let version: Int
}

/// The aws CLI under the caller's own profile. A value enters by stdin and leaves by stdout only,
/// so it never reaches argv, a log, or a file.
public struct AwsCli: Sendable {
    public var executable: String
    public var profile: String?
    public var region: String
    public var extraArguments: [String]
    public var environment: [String: String]

    public init(executable: String, profile: String? = nil, region: String = "us-east-1", extraArguments: [String] = [], environment: [String: String] = [:]) {
        self.executable = executable
        self.profile = profile
        self.region = region
        self.extraArguments = extraArguments
        self.environment = environment
    }

    /// A Finder-launched app has no shell PATH, so look where Homebrew and the installer put aws.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let candidates = [environment["SSM_APP_AWS"], "/opt/homebrew/bin/aws", "/usr/local/bin/aws", "/usr/local/aws-cli/aws"]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func run(_ arguments: [String], stdin: String? = nil) throws -> Data {
        var argv = arguments + ["--output", "json", "--region", region, "--no-cli-pager"] + extraArguments
        if let profile, !profile.isEmpty { argv += ["--profile", profile] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = argv
        var merged = ProcessInfo.processInfo.environment.merging(environment) { _, injected in injected }
        merged["AWS_PAGER"] = ""
        process.environment = merged
        let out = Pipe(), err = Pipe(), input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input
        do { try process.run() } catch { throw AwsFailure(kind: .other, message: "The aws CLI could not start.") }
        let stuck = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: stuck)
        if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? input.fileHandleForWriting.close()
        var stdout = Data(), stderr = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { stdout = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { stderr = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.wait()
        process.waitUntilExit()
        stuck.cancel()
        guard process.terminationStatus == 0 else {
            throw AwsFailure.classify(stderr: String(decoding: stderr, as: UTF8.self))
        }
        return stdout
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch {
            throw AwsFailure(kind: .other, message: "The aws CLI answered in a shape this app does not know.")
        }
    }

    public func identity() throws -> String {
        struct Identity: Decodable { let Arn: String }
        return try decode(Identity.self, run(["sts", "get-caller-identity"])).Arn
    }

    private static let query = "Parameters[].{Name:Name,Type:Type,Version:Version,LastModifiedDate:LastModifiedDate,Description:Description}"

    public func describeAll() throws -> [ParameterInfo] {
        try decode([ParameterInfo].self, run(["ssm", "describe-parameters", "--query", Self.query]))
    }

    public func describe(name: String) throws -> ParameterInfo? {
        let filter = "Key=Name,Option=Equals,Values=\(name)"
        let rows = try decode([ParameterInfo].self, run(["ssm", "describe-parameters", "--parameter-filters", filter, "--query", Self.query]))
        return rows.first
    }

    public func reveal(name: String) throws -> RevealedValue {
        struct Found: Decodable {
            let value: String, type: String, version: Int
            enum CodingKeys: String, CodingKey { case value = "Value", type = "Type", version = "Version" }
        }
        guard ParameterName.isValid(name) else { throw AwsFailure(kind: .other, message: "Bad name.") }
        let found = try decode(Found.self, run(["ssm", "get-parameter", "--name=\(name)", "--with-decryption", "--query", "Parameter"]))
        return RevealedValue(value: found.value, type: found.type, version: found.version)
    }

    /// The value goes to the CLI on stdin through `--value file:///dev/stdin`. A description is not a
    /// secret, so it rides in argv as `--description=<text>`, never as a separate word that could read as an option.
    @discardableResult
    public func put(name: String, value: String, type: String, overwrite: Bool, description: String? = nil) throws -> Int {
        struct Written: Decodable { let Version: Int }
        guard ParameterName.isValid(name), ["String", "SecureString"].contains(type) else {
            throw AwsFailure(kind: .other, message: "Bad name or type.")
        }
        var arguments = ["ssm", "put-parameter", "--name=\(name)", "--type=\(type)", overwrite ? "--overwrite" : "--no-overwrite", "--value", "file:///dev/stdin"]
        if let description, !description.isEmpty {
            guard description.count <= Descriptions.maxLength else { throw AwsFailure(kind: .other, message: "The description is over \(Descriptions.maxLength) characters.") }
            arguments.append("--description=\(description)")
        }
        return try decode(Written.self, run(arguments, stdin: value)).Version
    }

    public func delete(name: String) throws {
        guard ParameterName.isValid(name) else { throw AwsFailure(kind: .other, message: "Bad name.") }
        _ = try run(["ssm", "delete-parameter", "--name=\(name)"])
    }
}

public enum ParameterName {
    /// A name is passed as `--name=<name>`, so refuse anything that could read as an option.
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 1011, !name.hasPrefix("-") else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || "_.-/".unicodeScalars.contains(scalar)
        }
    }
}
