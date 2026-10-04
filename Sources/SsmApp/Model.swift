import AppKit
import SsmCore
import SwiftUI

enum Sheet: Identifiable {
    case write(prefill: String?)
    case rotate(String)
    case delete(String)

    var id: String {
        switch self {
        case .write(let name): "write-\(name ?? "")"
        case .rotate(let name): "rotate-\(name)"
        case .delete(let name): "delete-\(name)"
        }
    }
}

enum SaveResult {
    case saved(version: Int, verified: Bool)
    case exists
    case failed(String)
}

struct PathGroup: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [String]
    @Published var profile: String {
        didSet { UserDefaults.standard.set(profile, forKey: "profile") }
    }
    @Published var identity: String?
    @Published var parameters: [ParameterInfo] = []
    /// What the list shows: the optional yaml overlay wins, else the parameter's own SSM Description.
    @Published var descriptions: [String: String] = [:]
    private var overlay: [String: String] = [:]
    @Published var group = "/coilysiren"
    @Published var search = ""
    @Published var selected: String?
    @Published var loading = false
    @Published var failure: AwsFailure?
    @Published var notice: String?
    @Published var sheet: Sheet?

    let executable: String?
    /// Set only when SSM_APP_REPO or the descriptionsRepo preference names a checkout holding data/ssm-descriptions.yaml.
    /// Nil is the ordinary installed state, and descriptions then live in SSM alone.
    let descriptionsURL: URL?

    init() {
        executable = AwsCli.locate()
        let configured = AwsProfiles.configured()
        profiles = configured
        let saved = UserDefaults.standard.string(forKey: "profile")
        let fromEnvironment = ProcessInfo.processInfo.environment["AWS_PROFILE"]
        profile = saved.flatMap { configured.contains($0) ? $0 : nil }
            ?? fromEnvironment
            ?? (configured.contains("default") ? "default" : configured.first ?? "")
        // The key is not the old `repoPath` that the aosk build wrote, so a leftover preference cannot turn the
        // installed app into overlay mode. The driver reads the environment only, so a check never reaches a real checkout.
        let environment = ProcessInfo.processInfo.environment
        let driving = environment["SSM_APP_DRIVE"] != nil
        let repo = environment["SSM_APP_REPO"] ?? (driving ? nil : UserDefaults.standard.string(forKey: "descriptionsRepo"))
        let file = repo.map { URL(fileURLWithPath: $0).appendingPathComponent("data/ssm-descriptions.yaml") }
        descriptionsURL = file.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    var cli: AwsCli? {
        executable.map { AwsCli(executable: $0, profile: profile.isEmpty ? nil : profile) }
    }

    var access: String? { identity.flatMap(AwsProfiles.access(of:)) }

    // MARK: Listing

    static func topSegment(of name: String) -> String {
        guard name.hasPrefix("/") else { return "(no path)" }
        return "/" + (name.dropFirst().split(separator: "/", maxSplits: 1).first.map(String.init) ?? "")
    }

    var groups: [PathGroup] {
        Dictionary(grouping: parameters, by: { Self.topSegment(of: $0.name) })
            .map { PathGroup(name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    var filtered: [ParameterInfo] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return parameters.filter { row in
            (group.isEmpty || Self.topSegment(of: row.name) == group)
                && (needle.isEmpty || row.name.lowercased().contains(needle) || (descriptions[row.name]?.lowercased().contains(needle) ?? false))
        }
    }

    var selectedParameter: ParameterInfo? {
        selected.flatMap { name in parameters.first { $0.name == name } }
    }

    // MARK: Work

    private func work<T: Sendable>(_ job: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(with: Result { try job() }) }
        }
    }

    func refresh() async {
        guard let cli else {
            failure = AwsFailure(kind: .other, message: "The aws CLI was not found. Install it, or set SSM_APP_AWS.")
            return
        }
        loading = true
        defer { loading = false }
        loadDescriptions()
        do {
            async let rows = work { try cli.describeAll() }
            async let arn = work { try cli.identity() }
            parameters = try await rows.sorted { $0.name < $1.name }
            mergeDescriptions()
            identity = try? await arn
            failure = nil
            if !group.isEmpty, !groups.contains(where: { $0.name == group }) { group = "" }
        } catch let error as AwsFailure {
            failure = error
            identity = nil
        } catch {
            failure = AwsFailure(kind: .other, message: "Something went wrong.")
        }
    }

    func loadDescriptions() {
        guard let url = descriptionsURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        overlay = Descriptions.parse(text)
        mergeDescriptions()
    }

    private func mergeDescriptions() {
        var merged: [String: String] = [:]
        for row in parameters { if let own = row.description, !own.isEmpty { merged[row.name] = own } }
        descriptions = merged.merging(overlay) { _, yaml in yaml }
    }

    @discardableResult
    private func editIndex(_ change: (String) -> String?) -> Bool {
        guard let url = descriptionsURL, let text = try? String(contentsOf: url, encoding: .utf8), let edited = change(text) else { return false }
        do { try edited.write(to: url, atomically: true, encoding: .utf8) } catch { return false }
        overlay = Descriptions.parse(edited)
        mergeDescriptions()
        return true
    }

    func say(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(9))
            if notice == message { notice = nil }
        }
    }

    // MARK: Reading

    func reveal(_ name: String) async throws -> String {
        guard let cli else { throw AwsFailure(kind: .other, message: "The aws CLI was not found.") }
        return try await work { try cli.reveal(name: name).value }
    }

    // MARK: Writing

    func save(name: String, value: String, type: String, overwrite: Bool, description: String, addToIndex: Bool) async -> SaveResult {
        guard let cli else { return .failed("The aws CLI was not found.") }
        let clean = Secrets.stripTrailingNewline(value)
        do {
            let existing = try await work { try cli.describe(name: name) }
            if existing != nil && !overwrite { return .exists }
            let replacing = existing != nil
            // An empty field keeps the description the parameter already has, so a value replace never blanks it.
            let kept = Descriptions.clean(description) ?? existing?.description
            let version = try await work { try cli.put(name: name, value: clean, type: type, overwrite: replacing, description: kept) }
            let verified = (try? await work { try cli.reveal(name: name).value == clean }) ?? false
            var wrote = false
            if addToIndex, !description.trimmingCharacters(in: .whitespaces).isEmpty {
                wrote = editIndex { Descriptions.set($0, name: name, description: description) }
            }
            await refresh()
            selected = name
            say(indexNote("Saved \(name) as version \(version)\(verified ? ", read back and matched" : ", but the read-back did not match").", name: name, wrote: wrote))
            return .saved(version: version, verified: verified)
        } catch let error as AwsFailure {
            return .failed(error.message)
        } catch {
            return .failed("Something went wrong.")
        }
    }

    func rotate(name: String, length: Int, alphabet: SecretAlphabet) async -> SaveResult {
        guard let cli, let value = Secrets.generate(length: length, alphabet: alphabet) else { return .failed("Bad length.") }
        do {
            guard let existing = try await work({ try cli.describe(name: name) }) else { return .failed("No such parameter.") }
            guard ["String", "SecureString"].contains(existing.type) else { return .failed("Only String and SecureString rotate.") }
            let type = existing.type
            let kept = existing.description
            let version = try await work { try cli.put(name: name, value: value, type: type, overwrite: true, description: kept) }
            let verified = (try? await work { try cli.reveal(name: name).value == value }) ?? false
            await refresh()
            say(indexNote("Rotated \(name) to version \(version)\(verified ? ", read back and matched" : ", but the read-back did not match").", name: name, wrote: false))
            return .saved(version: version, verified: verified)
        } catch let error as AwsFailure {
            return .failed(error.message)
        } catch {
            return .failed("Something went wrong.")
        }
    }

    func delete(name: String, removeDescription: Bool) async -> String? {
        guard let cli else { return "The aws CLI was not found." }
        do {
            try await work { try cli.delete(name: name) }
            let removed = removeDescription && overlay[name] != nil && editIndex { Descriptions.remove($0, name: name) }
            if selected == name { selected = nil }
            await refresh()
            say("Deleted \(name).\(removed ? " Its index line is removed." : descriptionsURL == nil ? "" : " Run just ssm-index to refresh the inventory.")")
            return nil
        } catch let error as AwsFailure {
            return error.message
        } catch {
            return "Something went wrong."
        }
    }

    private func indexNote(_ lead: String, name: String, wrote: Bool) -> String {
        if wrote { return lead + " Its description is in data/ssm-descriptions.yaml. Commit it on a branch." }
        if descriptions[name] != nil || descriptionsURL == nil { return lead }
        return lead + " The index has no entry for it, so add a description or run just ssm-index."
    }

    func signIn() {
        guard let executable else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["sso", "login"] + (profile.isEmpty ? [] : ["--profile", profile])
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        try? process.run()
    }
}

enum Clipboard {
    /// Copies a value, marks it concealed so clipboard managers skip it, and clears it after a delay
    /// unless something else has been copied since.
    static func copySecret(_ value: String, clearAfter seconds: Double = 30) {
        let board = NSPasteboard.general
        board.clearContents()
        board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        board.setString(value, forType: .string)
        let stamp = board.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if NSPasteboard.general.changeCount == stamp { NSPasteboard.general.clearContents() }
        }
    }
}
