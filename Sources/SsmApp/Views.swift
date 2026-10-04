import SsmCore
import SwiftUI

// MARK: Shell

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } content: {
            ParameterTable()
                .navigationSplitViewColumnWidth(min: 460, ideal: 600)
        } detail: {
            DetailView()
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search names and descriptions")
        .toolbar { Toolbar() }
        .overlay(alignment: .bottom) { NoticeBanner() }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .write(let prefill): WriterSheet(prefill: prefill)
            case .rotate(let name): RotateSheet(name: name)
            case .delete(let name): DeleteSheet(name: name)
            }
        }
        .modifier(WindowMaterial())
        .task {
            await model.refresh()
            await Drive.runIfAsked(model)
        }
    }
}

struct WindowMaterial: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.containerBackground(.thinMaterial, for: .window)
        } else {
            content
        }
    }
}

struct Toolbar: ToolbarContent {
    @EnvironmentObject var model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Picker("Profile", selection: $model.profile) {
                ForEach(model.profiles, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .help("The AWS profile. A write needs the admin profile.")
            .onChange(of: model.profile) { _, _ in Task { await model.refresh() } }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if model.access != nil || model.identity != nil {
                IdentityChip()
            }
            Button { Task { await model.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .help("Reload the parameter list")
                .disabled(model.loading)
            Button { model.sheet = .write(prefill: nil) } label: { Label("New Parameter", systemImage: "plus") }
                .help("Write a new parameter")
        }
    }
}

struct IdentityChip: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let access = model.access
        Label(access ?? "signed in", systemImage: access == "admin" ? "lock.open.fill" : "lock.fill")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .foregroundStyle(access == "admin" ? Color.orange : Color.secondary)
            .help(model.identity ?? "")
    }
}

struct NoticeBanner: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let notice = model.notice {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true)
                Button { model.notice = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.bottom, 18).padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: Lister

struct Sidebar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List(selection: $model.group) {
            Section("Parameter Store") {
                Label("All Parameters", systemImage: "tray.full").tag("")
                    .badge(model.parameters.count)
            }
            Section("Paths") {
                ForEach(model.groups) { group in
                    Label(group.name, systemImage: "folder").tag(group.name).badge(group.count)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct ParameterTable: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let failure = model.failure, model.parameters.isEmpty {
                ContentUnavailableView {
                    Label("Can't reach Parameter Store", systemImage: "exclamationmark.lock")
                } description: {
                    Text(failure.message)
                } actions: {
                    if failure.kind == .noSession { Button("Sign In") { model.signIn() }.buttonStyle(.borderedProminent) }
                    Button("Try Again") { Task { await model.refresh() } }
                }
            } else if model.loading && model.parameters.isEmpty {
                ProgressView("Loading parameters").controlSize(.large)
            } else {
                Table(model.filtered, selection: $model.selected) {
                    TableColumn("Name") { row in
                        Label(row.name, systemImage: row.type == "SecureString" ? "lock.fill" : "doc.text")
                            .labelStyle(.titleAndIcon).lineLimit(1).truncationMode(.middle)
                    }.width(min: 260, ideal: 360)
                    TableColumn("Ver") { row in Text("\(row.version)").monospacedDigit().foregroundStyle(.secondary) }.width(36)
                    TableColumn("Modified") { row in
                        Text(row.modifiedDate?.formatted(date: .abbreviated, time: .omitted) ?? "").foregroundStyle(.secondary)
                    }.width(min: 84, ideal: 96)
                    TableColumn("Info") { row in
                        Image(systemName: model.descriptions[row.name] != nil ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(model.descriptions[row.name] != nil ? Color.green : Color.secondary)
                            .help(model.descriptions[row.name] ?? "No description")
                    }.width(44)
                }
                .overlay { if model.filtered.isEmpty && !model.loading { ContentUnavailableView.search(text: model.search) } }
            }
        }
        .navigationTitle(model.group.isEmpty ? "All Parameters" : model.group)
        .navigationSubtitle("\(model.filtered.count) parameters")
    }
}

// MARK: Reader

struct DetailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let parameter = model.selectedParameter {
                ParameterDetail(parameter: parameter).id(parameter.name)
            } else {
                ContentUnavailableView("Select a Parameter", systemImage: "key.fill", description: Text("Pick one from the list to read its details, replace, rotate, or delete it."))
            }
        }
        .background(alignment: .top) {
            LinearGradient(colors: [Color.accentColor.opacity(0.20), Color.accentColor.opacity(0.0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260).ignoresSafeArea()
        }
    }
}

struct ParameterDetail: View {
    @EnvironmentObject var model: AppModel
    let parameter: ParameterInfo
    @State private var value: String?
    @State private var loadingValue = false
    @State private var problem: String?
    @State private var remaining = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                metadata
                indexCard
                valueCard
                actions
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .onDisappear { value = nil }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: parameter.type == "SecureString" ? "key.fill" : "doc.text.fill")
                .font(.title2).foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.accentColor.opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(parameter.name).font(.title3.weight(.semibold)).textSelection(.enabled)
                Text(parameter.type).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private var metadata: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            GridRow { Text("Version").foregroundStyle(.secondary); Text("\(parameter.version)").monospacedDigit() }
            GridRow {
                Text("Modified").foregroundStyle(.secondary)
                Text(parameter.modifiedDate?.formatted(date: .long, time: .shortened) ?? "Unknown")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var indexCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Description", systemImage: "list.bullet.rectangle").font(.subheadline.weight(.semibold))
            if let description = model.descriptions[parameter.name] {
                Text(description).textSelection(.enabled)
                Text("Descriptions can lag reality, so check before you rotate.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No description is set. Anything that reads this path is unknown.").foregroundStyle(.secondary)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Value", systemImage: "eye").font(.subheadline.weight(.semibold))
            if let value {
                Text(value.isEmpty ? "(empty)" : value)
                    .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack {
                    Button { Clipboard.copySecret(value) } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .help("Copies, then clears the clipboard after 30 seconds")
                    Button { self.value = nil } label: { Label("Hide", systemImage: "eye.slash") }
                    Spacer()
                    Text("Hides in \(remaining)s").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            } else {
                Text("Hidden. It is decrypted only when you ask.").foregroundStyle(.secondary)
                Button { Task { await reveal() } } label: {
                    if loadingValue { ProgressView().controlSize(.small) } else { Label("Reveal", systemImage: "eye") }
                }
                .disabled(loadingValue)
            }
            if let problem { Text(problem).font(.callout).foregroundStyle(.red) }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .task(id: value != nil) {
            guard value != nil else { return }
            remaining = 30
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
            if !Task.isCancelled { value = nil }
        }
    }

    private var actions: some View {
        HStack {
            Button { model.sheet = .write(prefill: parameter.name) } label: { Label("Replace Value", systemImage: "square.and.pencil") }
            Button { model.sheet = .rotate(parameter.name) } label: { Label("Rotate", systemImage: "arrow.triangle.2.circlepath") }
            Spacer()
            Button(role: .destructive) { model.sheet = .delete(parameter.name) } label: { Label("Delete", systemImage: "trash") }
        }
        .controlSize(.large)
    }

    private func reveal() async {
        loadingValue = true
        problem = nil
        do { value = try await model.reveal(parameter.name) } catch let error as AwsFailure { problem = error.message } catch { problem = "Something went wrong." }
        loadingValue = false
    }
}

// MARK: Writer

struct WriterSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let prefill: String?
    @State private var name = ""
    @State private var type = "SecureString"
    @State private var value = ""
    @State private var showValue = false
    @State private var description = ""
    @State private var addToIndex = true
    @State private var saving = false
    @State private var problem: String?
    @State private var confirmOverwrite = false

    private var canSave: Bool {
        ParameterName.isValid(name) && !value.isEmpty && !saving
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Parameter") {
                    TextField("Name", text: $name, prompt: Text("/coilysiren/example/token"))
                        .disabled(prefill != nil)
                    Picker("Type", selection: $type) {
                        Text("SecureString").tag("SecureString")
                        Text("String").tag("String")
                    }.pickerStyle(.segmented)
                }
                Section {
                    if showValue {
                        TextField("Value", text: $value, axis: .vertical).lineLimit(1...8).font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("Value", text: $value)
                    }
                    Toggle("Show value", isOn: $showValue)
                } header: {
                    Text("Value")
                } footer: {
                    Text("It goes to the aws CLI on stdin, never on a command line. One trailing newline is stripped, since editors append one, and the value is read back to check it.")
                }
                Section {
                    TextField("Description", text: $description, prompt: Text("One line: what it is and what consumes it"))
                    if model.descriptionsURL != nil { Toggle("Also add to data/ssm-descriptions.yaml", isOn: $addToIndex) }
                } header: {
                    Text("Description")
                } footer: {
                    Text("Stored in the parameter's own Description field, up to \(Descriptions.maxLength) characters. Left empty, an existing description is kept. Never put a secret in a description.")
                }
                if let problem { Section { Text(problem).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button(prefill == nil ? "Save" : "Replace Value") { Task { await save(overwrite: false) } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canSave)
            }.padding(16)
        }
        .frame(width: 540)
        .background(.regularMaterial)
        .onAppear {
            if let prefill {
                name = prefill
                if let existing = model.parameters.first(where: { $0.name == prefill }) { type = existing.type }
                description = model.descriptions[prefill] ?? ""
                addToIndex = model.descriptions[prefill] == nil
            }
        }
        .confirmationDialog("Replace the value of \(name)?", isPresented: $confirmOverwrite, titleVisibility: .visible) {
            Button("Replace", role: .destructive) { Task { await save(overwrite: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This writes a new version. Anything reading the path gets the new value.")
        }
    }

    private func save(overwrite: Bool) async {
        saving = true
        problem = nil
        let result = await model.save(name: name, value: value, type: type, overwrite: overwrite, description: description, addToIndex: addToIndex)
        saving = false
        switch result {
        case .saved: value = ""; dismiss()
        case .exists: confirmOverwrite = true
        case .failed(let message): problem = message
        }
    }
}

// MARK: Rotate and delete

struct RotateSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let name: String
    @State private var length = 40.0
    @State private var alphabet = SecretAlphabet.alphanumeric
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    LabeledContent("Parameter", value: name)
                    Picker("Characters", selection: $alphabet) { ForEach(SecretAlphabet.allCases) { Text($0.title).tag($0) } }
                    LabeledContent("Length") {
                        HStack { Slider(value: $length, in: 16...128, step: 1); Text("\(Int(length))").monospacedDigit().frame(width: 34) }
                    }
                } footer: {
                    Text("A random value is generated here, written as a new version, and read back. It is not shown. Reveal it afterwards if you need it.")
                }
                Section("What consumes it") {
                    if let description = model.descriptions[name] { Text(description) } else { Text("No description is set, so what reads this path is unknown.").foregroundStyle(.secondary) }
                }
                if let problem { Section { Text(problem).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Rotate") { Task { await rotate() } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(working)
            }.padding(16)
        }
        .frame(width: 500).background(.regularMaterial)
    }

    private func rotate() async {
        working = true
        problem = nil
        let result = await model.rotate(name: name, length: Int(length), alphabet: alphabet)
        working = false
        if case .failed(let message) = result { problem = message } else { dismiss() }
    }
}

struct DeleteSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let name: String
    @State private var typed = ""
    @State private var removeDescription = true
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("Delete \(name)? This cannot be undone, and anything that reads it will stop finding it.")
                    TextField("Type the exact name to confirm", text: $typed)
                    if model.descriptionsURL != nil, model.descriptions[name] != nil { Toggle("Also remove its line from data/ssm-descriptions.yaml", isOn: $removeDescription) }
                }
                if let problem { Section { Text(problem).foregroundStyle(.red) } }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Delete", role: .destructive) { Task { await delete() } }
                    .buttonStyle(.borderedProminent).tint(.red).disabled(typed != name || working)
            }.padding(16)
        }
        .frame(width: 500).background(.regularMaterial)
    }

    private func delete() async {
        working = true
        if let message = await model.delete(name: name, removeDescription: removeDescription) { problem = message; working = false } else { dismiss() }
    }
}
