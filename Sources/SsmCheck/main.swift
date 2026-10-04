import Foundation
import SsmCore

// XCTest and Swift Testing do not load under Command Line Tools alone, so the checks are an executable:
// `just ssm-app-check`. They run the real AwsCli against a fake aws that records argv and stdin.

var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    print(ok ? "PASS" : "FAIL", name, ok ? "" : "- " + detail())
    if !ok { failures += 1 }
}

let sentinel = "SENTINEL-" + UUID().uuidString.prefix(8)
let work = FileManager.default.temporaryDirectory.appendingPathComponent("ssm-check-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

let fakeSource = #"""
#!/usr/bin/env python3
import json, os, sys
state_path, log_path = os.environ["FAKE_AWS_STATE"], os.environ["FAKE_AWS_LOG"]
argv = sys.argv[1:]
stdin = "" if sys.stdin.isatty() else sys.stdin.read()
with open(log_path, "a") as log:
    log.write(json.dumps({"argv": argv, "stdin": stdin}) + "\n")
state = json.load(open(state_path))
def fail(code, extra=""):
    sys.stderr.write("An error occurred (%s) when calling the operation: %s\n" % (code, extra))
    sys.exit(254)
forced = os.environ.get("FAKE_AWS_FAIL")
if forced:
    fail(forced, "echo " + stdin)
def arg(prefix):
    return next((a.split("=", 1)[1] for a in argv if a.startswith(prefix)), None)
def save():
    json.dump(state, open(state_path, "w"))
def row(name):
    p = state[name]
    return {"Name": name, "Type": p["Type"], "Version": p["Version"], "LastModifiedDate": "2026-10-02T04:41:44.651000-07:00", "Description": p.get("Description")}
if argv[:2] == ["sts", "get-caller-identity"]:
    print(json.dumps({"Arn": "arn:aws:sts::000000000000:assumed-role/AWSReservedSSO_AdministratorAccess_x/kai"}))
elif argv[:2] == ["ssm", "describe-parameters"]:
    flt = argv[argv.index("--parameter-filters") + 1] if "--parameter-filters" in argv else ""
    names = sorted(state)
    if flt.startswith("Key=Name"):
        want = flt.split("Values=", 1)[1]
        names = [n for n in names if n == want]
    print(json.dumps([row(n) for n in names]))
elif argv[:2] == ["ssm", "get-parameter"]:
    name = arg("--name=")
    if name not in state:
        fail("ParameterNotFound")
    p = state[name]
    print(json.dumps({"Value": p["Value"], "Type": p["Type"], "Version": p["Version"]}))
elif argv[:2] == ["ssm", "put-parameter"]:
    name = arg("--name=")
    if name in state and "--no-overwrite" in argv:
        fail("ParameterAlreadyExists", "value was " + stdin)
    # A real overwrite without --description keeps the old one, so the fake does too.
    old = state.get(name, {})
    state[name] = {"Value": stdin, "Type": arg("--type="), "Version": old.get("Version", 0) + 1, "Description": arg("--description=") or old.get("Description")}
    save()
    print(json.dumps({"Version": state[name]["Version"], "Tier": "Standard"}))
elif argv[:2] == ["ssm", "delete-parameter"]:
    name = arg("--name=")
    if name not in state:
        fail("ParameterNotFound")
    del state[name]
    save()
else:
    fail("UnknownOperation")
"""#

// `ssm-check --fake DIR` writes the fake aws and a demo state, so the app can run with no AWS at all.
if let flag = CommandLine.arguments.firstIndex(of: "--fake"), CommandLine.arguments.indices.contains(flag + 1) {
    let dir = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let script = dir.appendingPathComponent("aws")
    try fakeSource.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    let demo = #"{"/authelia/jwt-secret":{"Value":"demo-1","Type":"SecureString","Version":4},"/coilysiren/home/public-ip":{"Value":"192.0.2.10","Type":"String","Version":2},"/coilysiren/lunchmoney/api-token":{"Value":"demo-2","Type":"SecureString","Version":7},"/coilysiren/slack/refresh-token":{"Value":"demo-3","Type":"SecureString","Version":12},"/coilysiren/kai-server/tailnet-fqdn":{"Value":"demo.example.ts.net","Type":"String","Version":1},"/sirens-deep/discord-token":{"Value":"demo-4","Type":"SecureString","Version":3},"/zulip/secret-key":{"Value":"demo-5","Type":"SecureString","Version":2,"Description":"Zulip secret key from SSM"}}"#
    try demo.write(to: dir.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
    print("SSM_APP_AWS=\(script.path)")
    print("FAKE_AWS_STATE=\(dir.appendingPathComponent("state.json").path)")
    print("FAKE_AWS_LOG=\(dir.appendingPathComponent("calls.jsonl").path)")
    exit(0)
}

let fake = work.appendingPathComponent("aws").path
let statePath = work.appendingPathComponent("state.json").path
let logPath = work.appendingPathComponent("calls.jsonl").path
try fakeSource.write(toFile: fake, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake)
let seed = #"{"/coilysiren/one":{"Value":"existing","Type":"SecureString","Version":3},"/other/two":{"Value":"plain","Type":"String","Version":1}}"#
try seed.write(toFile: statePath, atomically: true, encoding: .utf8)
let fakeEnvironment = ["FAKE_AWS_STATE": statePath, "FAKE_AWS_LOG": logPath]
let cli = AwsCli(executable: fake, profile: "admin", environment: fakeEnvironment)

func calls() -> [(argv: [String], stdin: String)] {
    guard let text = try? String(contentsOfFile: logPath, encoding: .utf8) else { return [] }
    return text.split(separator: "\n").compactMap { line in
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let argv = object["argv"] as? [String], let stdin = object["stdin"] as? String else { return nil }
        return (argv, stdin)
    }
}

// Listing and reading.
let all = try cli.describeAll()
check("describeAll decodes every row", all.map(\.name) == ["/coilysiren/one", "/other/two"], "\(all.map(\.name))")
check("describeAll carries type, version, and a parsed date", all.first?.type == "SecureString" && all.first?.version == 3 && all.first?.modifiedDate != nil)
check("a profile reaches the CLI as --profile", calls().last.map { $0.argv.contains("--profile") && $0.argv.contains("admin") } == true)
check("identity returns the ARN", try cli.identity().contains("AdministratorAccess"))
check("access is read from the role name", AwsProfiles.access(of: try cli.identity()) == "admin" && AwsProfiles.access(of: "arn:...AWSReservedSSO_ReadOnlyAccess_x") == "read-only")
check("describe(name:) finds one and misses another", try cli.describe(name: "/coilysiren/one") != nil && (try cli.describe(name: "/coilysiren/absent")) == nil)
check("no list call asks for decryption", calls().allSatisfy { !$0.argv.contains("--with-decryption") })
let revealed = try cli.reveal(name: "/coilysiren/one")
check("reveal asks for decryption and returns the value", revealed.value == "existing" && calls().last?.argv.contains("--with-decryption") == true)

// Writing: the value never reaches argv.
let version = try cli.put(name: "/coilysiren/new", value: sentinel + "-write", type: "SecureString", overwrite: false)
let putCall = calls().last!
check("put returns the new version", version == 1)
check("put value is on stdin", putCall.stdin == sentinel + "-write")
check("put value is not in argv", !putCall.argv.joined(separator: " ").contains(sentinel))
check("put reads the value from stdin by file URL", putCall.argv.contains("file:///dev/stdin") && putCall.argv.contains("--no-overwrite"))
do {
    _ = try cli.put(name: "/coilysiren/new", value: sentinel + "-again", type: "SecureString", overwrite: false)
    check("put without overwrite refuses an existing name", false)
} catch let failure as AwsFailure {
    check("put without overwrite refuses an existing name", failure.kind == .exists)
    check("a refusal does not echo the value", !failure.message.contains(sentinel), failure.message)
}
check("put with overwrite bumps the version", try cli.put(name: "/coilysiren/new", value: sentinel + "-two", type: "SecureString", overwrite: true) == 2)
check("readback matches what was written", try cli.reveal(name: "/coilysiren/new").value == sentinel + "-two")
let described = try cli.put(name: "/coilysiren/described", value: sentinel + "-d", type: "String", overwrite: false, description: "What it is, in one line")
check("put sends a description as --description=<text>", described == 1 && calls().last?.argv.contains("--description=What it is, in one line") == true)
check("describeAll carries the SSM description", try cli.describe(name: "/coilysiren/described")?.description == "What it is, in one line")
check("a parameter with no description decodes as nil", try cli.describe(name: "/coilysiren/one")?.description == nil)
_ = try cli.put(name: "/coilysiren/described", value: sentinel + "-d2", type: "String", overwrite: true)
check("an overwrite without a description keeps the existing one", try cli.describe(name: "/coilysiren/described")?.description == "What it is, in one line")
check("an over-long description is refused before any call", { let before = calls().count; let refused = (try? cli.put(name: "/a/b", value: "v", type: "String", overwrite: true, description: String(repeating: "x", count: Descriptions.maxLength + 1))) == nil; return refused && calls().count == before }())
try cli.delete(name: "/coilysiren/described")
check("no call ever carried a value in argv", calls().allSatisfy { !$0.argv.joined(separator: " ").contains(sentinel) })
check("an unsupported type is refused before any call", { (try? cli.put(name: "/a/b", value: "v", type: "StringList", overwrite: true)) == nil }())

// Errors are classified, never echoed.
for (code, kind) in [("AccessDeniedException", AwsFailure.Kind.denied), ("ParameterNotFound", .notFound), ("ExpiredTokenException", .noSession)] {
    let failing = AwsCli(executable: fake, environment: fakeEnvironment.merging(["FAKE_AWS_FAIL": code]) { _, new in new })
    do { _ = try failing.put(name: "/a/b", value: sentinel + "-fail", type: "String", overwrite: true); check("\(code) fails", false) }
    catch let failure as AwsFailure { check("\(code) classifies as \(kind)", failure.kind == kind, "\(failure.kind)"); check("\(code) message is not the CLI's text", !failure.message.contains(sentinel) && !failure.message.contains("echo")) }
}
let missing = AwsCli(executable: "/nonexistent/aws")
do { _ = try missing.identity(); check("a missing aws binary fails", false) } catch let failure as AwsFailure { check("a missing aws binary is a clear failure", failure.kind == .other) }

// Deleting.
try cli.delete(name: "/coilysiren/new")
check("delete removes the parameter", try cli.describe(name: "/coilysiren/new") == nil)

// Names.
for bad in ["--endpoint-url", "", "/a b", "/a;rm", "/a\n", String(repeating: "x", count: 1012)] { check("bad name refused: \(bad.prefix(14).debugDescription)", !ParameterName.isValid(bad)) }
for good in ["/coilysiren/slack/refresh-token", "plain_name.v2", "/a/B/9"] { check("good name accepted: \(good)", ParameterName.isValid(good)) }
check("a bad name is refused before any CLI call", { let before = calls().count; _ = try? cli.reveal(name: "--evil"); return calls().count == before }())

// Newlines and rotation.
check("one trailing newline is stripped", Secrets.stripTrailingNewline("v\n") == "v")
check("a CRLF is stripped without eating the last character", Secrets.stripTrailingNewline("abc\r\n") == "abc", Secrets.stripTrailingNewline("abc\r\n"))
check("only one newline is stripped", Secrets.stripTrailingNewline("v\n\n") == "v\n")
check("an interior newline stays", Secrets.stripTrailingNewline("a\nb") == "a\nb")
for alphabet in SecretAlphabet.allCases {
    let one = Secrets.generate(length: 40, alphabet: alphabet)!
    let two = Secrets.generate(length: 40, alphabet: alphabet)!
    let allowed = Set(alphabet.rawValue == "hex" ? "0123456789abcdef" : alphabet.rawValue == "urlSafe" ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_" : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    check("\(alphabet.rawValue) rotation has 40 characters from its alphabet", one.count == 40 && Set(one).isSubset(of: allowed))
    check("\(alphabet.rawValue) rotations differ", one != two)
}
check("rotation length is bounded", Secrets.generate(length: 15, alphabet: .hex) == nil && Secrets.generate(length: 129, alphabet: .hex) == nil && Secrets.generate(length: 16, alphabet: .hex)?.count == 16)

// The descriptions source.
let yaml = "# header\ndescriptions:\n  /authelia/jwt-secret: \"Authelia JWT\"\n  /coilysiren/one: \"First\"\n  /coilysiren/two: \"Second\"\n  /zulip/key: \"Zulip\"\n"
check("parse reads every entry", Descriptions.parse(yaml).count == 4 && Descriptions.parse(yaml)["/coilysiren/two"] == "Second")
let added = Descriptions.set(yaml, name: "/coilysiren/zzz-new", description: "A \"quoted\" one-liner with a \\ and unicode é")!
check("a new entry lands after its group", added.components(separatedBy: "\n").firstIndex { $0.contains("zzz-new") } == yaml.components(separatedBy: "\n").firstIndex { $0.contains("/coilysiren/two") }! + 1)
check("a new entry parses back exactly", Descriptions.parse(added)["/coilysiren/zzz-new"] == "A \"quoted\" one-liner with a \\ and unicode é")
check("every other line is untouched by an add", Set(added.components(separatedBy: "\n")).subtracting(Set(yaml.components(separatedBy: "\n"))).count == 1)
check("an add keeps the trailing newline", added.hasSuffix("\n") && !added.hasSuffix("\n\n"))
let replaced = Descriptions.set(added, name: "/coilysiren/one", description: "Changed")!
check("a replace changes only its line", Descriptions.parse(replaced)["/coilysiren/one"] == "Changed" && Descriptions.parse(replaced).count == 5)
check("an unknown group appends at the end", Descriptions.set(yaml, name: "/newgroup/x", description: "Y")!.components(separatedBy: "\n").dropLast().last!.contains("/newgroup/x"))
check("a multi-line description collapses to one line", Descriptions.clean("one\ntwo\tthree  ") == "one two three")
check("an empty description is refused", Descriptions.set(yaml, name: "/a/b", description: "  \n ") == nil)
check("a bad name is refused", Descriptions.set(yaml, name: "--x", description: "d") == nil)
let removed = Descriptions.remove(added, name: "/coilysiren/zzz-new")!
check("add then remove restores the file byte for byte", removed == yaml)
check("removing an absent name does nothing", Descriptions.remove(yaml, name: "/nope/x") == nil)
check("a file with no final newline stays that way", !Descriptions.set(String(yaml.dropLast()), name: "/coilysiren/q", description: "d")!.hasSuffix("\n"))

// Profiles.
let config = "[default]\nregion = us-east-1\n\n[profile admin]\nsso_session = s\n[profile readonly]\n[sso-session s]\nsso_region = us-east-1\n"
check("profiles come from default and profile sections only", AwsProfiles.names(in: config) == ["default", "admin", "readonly"], "\(AwsProfiles.names(in: config))")

// The real CLI accepts a value on stdin. A dead endpoint means nothing leaves this machine, and
// "Could not connect" proves the input parsed. A rejected input would fail before it connected.
if let real = AwsCli.locate(environment: [:]) {
    let configPath = work.appendingPathComponent("config").path
    try "[default]\nregion = us-east-1\n".write(toFile: configPath, atomically: true, encoding: .utf8)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: real)
    process.arguments = ["ssm", "put-parameter", "--name=/x/y", "--type=SecureString", "--overwrite", "--value", "file:///dev/stdin",
                         "--output", "json", "--region", "us-east-1", "--no-cli-pager",
                         "--endpoint-url", "http://127.0.0.1:9", "--cli-connect-timeout", "2", "--cli-read-timeout", "2"]
    process.environment = ["PATH": "/usr/bin:/bin", "AWS_PAGER": "", "AWS_ACCESS_KEY_ID": "AKIAFAKEFAKEFAKEFAKE",
                           "AWS_SECRET_ACCESS_KEY": String(repeating: "f", count: 40), "AWS_CONFIG_FILE": configPath,
                           "AWS_SHARED_CREDENTIALS_FILE": work.appendingPathComponent("none").path]
    let input = Pipe(), err = Pipe()
    process.standardInput = input
    process.standardError = err
    process.standardOutput = Pipe()
    try process.run()
    input.fileHandleForWriting.write(Data((sentinel + "-live").utf8))
    try input.fileHandleForWriting.close()
    let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    check("real aws read the value from stdin and only failed to connect", stderr.contains("Could not connect"), stderr)
    check("real aws does not echo the value in its error", !stderr.contains(sentinel))
} else {
    print("SKIP real aws stdin check: no aws CLI found")
}

print(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
