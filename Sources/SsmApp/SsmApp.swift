import AppKit
import SwiftUI

@main
struct SsmAppMain: App {
    @StateObject private var model = AppModel()

    init() {
        // A bare executable has no bundle to say it is a regular app, so say it here.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("SSM") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .defaultSize(width: 1240, height: 760)
        .windowToolbarStyle(.unified)
    }
}

/// `SSM_APP_DRIVE=1` runs the model's flows against the backend in the environment and quits with the result.
/// `just ssm-app-check` points it at a fake aws, with and without a descriptions overlay checkout, never at AWS.
@MainActor
enum Drive {
    static var failures = 0

    static func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        print(ok ? "PASS" : "FAIL", name, ok ? "" : "- " + detail())
        if !ok { failures += 1 }
    }

    static func stateField(_ name: String, _ field: String) -> String? {
        guard let path = ProcessInfo.processInfo.environment["FAKE_AWS_STATE"], let data = FileManager.default.contents(atPath: path),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return nil }
        return state[name]?[field] as? String
    }

    static func stateValue(_ name: String) -> String? { stateField(name, "Value") }

    /// Every argument of every aws call, with stdin left out: a value belongs on stdin and nowhere else.
    static func argvLog() -> String {
        let text = ProcessInfo.processInfo.environment["FAKE_AWS_LOG"].flatMap { try? String(contentsOfFile: $0, encoding: .utf8) } ?? ""
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["argv"] as? [String]
        }.map { $0.joined(separator: " ") }.joined(separator: "\n")
    }

    static func runIfAsked(_ model: AppModel) async {
        guard ProcessInfo.processInfo.environment["SSM_APP_DRIVE"] != nil else { return }
        let name = "/coilysiren/zz-driver-test"
        let secret = "DRIVER-SECRET-" + UUID().uuidString.prefix(8)
        let indexURL = model.descriptionsURL
        let original = indexURL.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""

        check("the list loads every fake parameter", model.parameters.count == 7, "\(model.parameters.count)")
        check("groups split by first path segment", model.groups.map(\.name) == ["/authelia", "/coilysiren", "/sirens-deep", "/zulip"], "\(model.groups.map(\.name))")
        model.group = "/coilysiren"
        check("a group filter narrows the list", model.filtered.count == 4, "\(model.filtered.count)")
        model.search = "slack"
        check("search matches names", model.filtered.map(\.name) == ["/coilysiren/slack/refresh-token"])
        model.search = ""
        check("the identity is read and recognised as admin", model.access == "admin", "\(model.access ?? "nil")")
        let environment = ProcessInfo.processInfo.environment
        let overlayMode = indexURL != nil
        check("the overlay is on exactly when SSM_APP_REPO holds the yaml", overlayMode == FileManager.default.fileExists(atPath: (environment["SSM_APP_REPO"] ?? "/nonexistent") + "/data/ssm-descriptions.yaml"))
        print("MODE", overlayMode ? "overlay" : "ssm-only")
        check("a parameter's own SSM description is shown, and the overlay wins when it names one", model.descriptions["/zulip/secret-key"] == (overlayMode ? "Overlay wins" : "Zulip secret key from SSM"), model.descriptions["/zulip/secret-key"] ?? "nil")
        check("an overlay-only entry shows only with the overlay", model.descriptions["/authelia/jwt-secret"] == (overlayMode ? "From the overlay" : nil), model.descriptions["/authelia/jwt-secret"] ?? "nil")

        let first = await model.save(name: name, value: secret + "\n", type: "SecureString", overwrite: false, description: "Driver test parameter", addToIndex: true)
        if case .saved(let version, let verified) = first { check("a new parameter saves at version 1 and reads back", version == 1 && verified) } else { check("a new parameter saves", false, "\(first)") }
        check("the trailing newline was stripped before it was written", stateValue(name) == secret, stateValue(name) ?? "nil")
        check("the description reached the list model", model.descriptions[name] == "Driver test parameter")
        check("the description was written to the SSM Description field", stateField(name, "Description") == "Driver test parameter", stateField(name, "Description") ?? "nil")
        let edited = indexURL.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
        check("the overlay file gained one line, and without the overlay no file is touched", edited.components(separatedBy: "\n").count == original.components(separatedBy: "\n").count + (overlayMode ? 1 : 0))
        check("the new parameter is selected and listed", model.selected == name && model.parameters.contains { $0.name == name })

        let again = await model.save(name: name, value: secret + "-2", type: "SecureString", overwrite: false, description: "", addToIndex: false)
        if case .exists = again { check("saving over an existing name asks first", true) } else { check("saving over an existing name asks first", false, "\(again)") }
        let replaced = await model.save(name: name, value: secret + "-2", type: "SecureString", overwrite: true, description: "", addToIndex: false)
        if case .saved(let version, _) = replaced { check("an overwrite writes version 2", version == 2) } else { check("an overwrite writes version 2", false, "\(replaced)") }
        check("a replace with an empty description keeps the SSM one", stateField(name, "Description") == "Driver test parameter", stateField(name, "Description") ?? "nil")

        let before = stateValue(name)
        let rotated = await model.rotate(name: name, length: 40, alphabet: .alphanumeric)
        if case .saved(let version, let verified) = rotated { check("rotation writes version 3 and reads back", version == 3 && verified) } else { check("rotation writes version 3", false, "\(rotated)") }
        let after = stateValue(name) ?? ""
        check("rotation changed the value", after != before && after.count == 40 && after.allSatisfy { $0.isLetter || $0.isNumber }, after.count.description)
        check("rotation kept the type", model.parameters.first { $0.name == name }?.type == "SecureString")
        check("rotation kept the description", stateField(name, "Description") == "Driver test parameter" && model.descriptions[name] == "Driver test parameter")
        check("reveal returns what is stored", (try? await model.reveal(name)) == after)
        let missing = await model.rotate(name: "/coilysiren/does-not-exist", length: 40, alphabet: .hex)
        if case .failed = missing { check("rotating a missing parameter fails cleanly", true) } else { check("rotating a missing parameter fails cleanly", false) }

        let log = argvLog()
        check("the log has calls to read", log.contains("put-parameter") && log.contains("get-parameter"))
        check("no secret ever reached a command line", !log.contains(secret) && !log.contains(after) && !log.contains(before ?? "#"))

        let deleted = await model.delete(name: name, removeDescription: true)
        check("delete succeeds", deleted == nil, deleted ?? "")
        check("the parameter is gone", stateValue(name) == nil && !model.parameters.contains { $0.name == name })
        let restored = indexURL.flatMap { try? String(contentsOfFile: $0.path, encoding: .utf8) } ?? ""
        check("add then delete leaves the overlay file byte for byte as it was", restored == original)

        print(failures == 0 ? "DRIVER PASSED" : "\(failures) DRIVER CHECK(S) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
