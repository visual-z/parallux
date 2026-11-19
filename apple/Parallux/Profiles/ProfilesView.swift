import AppKit
import CoreImage.CIFilterBuiltins
import ParalluxKit
import SwiftUI
import UniformTypeIdentifiers

/// 主窗口「配置」页：列表、新建与导入、编辑 JSON、分享、立即更新。
struct ProfilesView: View {
    @Environment(ProfileService.self) private var service
    @State private var adding: ProfileKind?
    @State private var editing: Profile?
    @State private var sharing: Profile?
    @State private var editingInfo: Profile?
    @State private var importingFile = false
    @State private var linkPrompt = false
    @State private var link = ""
    @State private var error: String?

    private var store: ProfileStore { service.store }

    var body: some View {
        Group {
            if store.profiles.isEmpty {
                ContentUnavailableView {
                    Label("无配置", systemImage: "doc.text")
                } actions: {
                    Button("新建配置") { adding = .local }.buttonStyle(.borderedProminent)
                    Button("导入远程配置") { adding = .remote }
                }
            } else {
                // Design v0.2, profiles page: the list card. The content opens
                // from a row's menu (查看内容 / 编辑内容), never by itself: a
                // subscription can be megabytes (docs/tasks/fix-ui-details.md).
                DesignPage {
                    DesignList(items: store.profiles, id: { $0.id.uuidString }, move: { dragged, target in
                        guard let move = ListReorder.offsets(moving: dragged, onto: target, in: store.profiles.map { $0.id.uuidString }) else { return }
                        run { try store.move(fromOffsets: [move.from], toOffset: move.to) }
                    }) { profile in
                        ProfileRowView(
                            symbol: Self.symbol(profile.kind), name: profile.name, inUse: profile.id == store.selectedID,
                            detail: ProfileDescription.detail(profile, now: Date()),
                            isUpdating: service.updating.contains(profile.id),
                            update: profile.kind == .remote ? { Task { await runAsync { try await service.update(profile) } } } : nil
                        ) { menu(for: profile) }
                        // A click anywhere on the row uses that configuration.
                        .onTapGesture { run { try store.select(profile.id) } }
                        .contextMenu { menu(for: profile) }
                    }
                }
            }
        }
        .navigationSubtitle(store.selected?.name ?? "")
        .toolbar { ToolbarItem { addMenu } }
        .sheet(item: $adding) { kind in AddProfileSheet(kind: kind) }
        .sheet(item: $editing) { profile in ProfileEditor(profile: profile) }
        .sheet(item: $sharing) { profile in ShareProfileSheet(profile: profile) }
        .sheet(item: $editingInfo) { profile in ProfileInfoEditor(profile: profile) }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json, UTType(filenameExtension: "bpf") ?? .data]) { result in
            Task { await runAsync { try await service.importFile(try result.get()) } }
        }
        .alert("导入远程配置", isPresented: $linkPrompt) {
            TextField("sing-box://import-remote-profile?url=…", text: $link)
            Button("导入") { let value = link; Task { await runAsync { try await service.importLink(value) } } }
            Button("取消", role: .cancel) {}
        }
        .alert("错误", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("完成") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    static func symbol(_ kind: ProfileKind) -> String {
        switch kind {
        case .local: "doc.text"
        case .icloud: "icloud"
        case .remote: "link"
        }
    }

    private var addMenu: some View {
        Menu {
            Button("手动创建") { adding = .local }
            Button("从文件导入") { importingFile = true }
            Divider()
            Button("导入远程配置") { adding = .remote }
            Button("从链接导入") { link = ""; linkPrompt = true }
            Divider()
            Button("iCloud") { adding = .icloud }
        } label: {
            Label("新建配置", systemImage: "plus")
        }
        .help("新建配置")
    }

    @ViewBuilder private func menu(for profile: Profile) -> some View {
        Button(profile.isReadOnly ? "查看内容" : "编辑内容") { editing = profile }
        Button("编辑配置") { editingInfo = profile }
        Menu("分享") {
            Button("分享文件") { Task { await export(profile, bpf: true) } }
            Button("保存内容 JSON") { Task { await export(profile, bpf: false) } }
            if profile.kind == .remote { Button("通过二维码分享 URL") { sharing = profile } }
        }
        if profile.kind == .remote {
            Button("更新") { Task { await runAsync { try await service.update(profile) } } }
        }
        Divider()
        Button("删除", role: .destructive) { run { try store.delete(profile.id) } }
    }

    private func export(_ profile: Profile, bpf: Bool) async {
        await runAsync {
            let data = bpf ? try await service.exportBPF(profile) : Data(try await service.content(of: profile).utf8)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = profile.name + (bpf ? ".bpf" : ".json")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
        }
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { self.error = error.localizedDescription }
    }

    private func runAsync(_ body: () async throws -> Void) async {
        do { try await body() } catch { self.error = error.localizedDescription }
    }
}

/// 新建：本地（空白模板）、远程订阅、iCloud 云盘文件。
private struct AddProfileSheet: View {
    let kind: ProfileKind
    @Environment(ProfileService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var autoUpdate = true
    @State private var interval = RemoteUpdate.defaultInterval
    @State private var icloudFile: URL?
    @State private var pickingFile = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Form {
            TextField("名称", text: $name)
            switch kind {
            case .remote:
                TextField("URL", text: $url, prompt: Text("https://"))
                Toggle("自动更新", isOn: $autoUpdate)
                Picker("更新间隔", selection: $interval) {
                    ForEach(ProfileDescription.intervalChoices, id: \.self) { Text(ProfileDescription.interval($0)).tag($0) }
                }
                .disabled(!autoUpdate)
            case .icloud:
                LabeledContent("文件") {
                    Button(icloudFile?.lastPathComponent ?? "打开") { pickingFile = true }
                }
            case .local:
                EmptyView()
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("创建") { Task { await add() } }.disabled(busy || !canAdd)
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.json]) { result in
            icloudFile = try? result.get()
            if name.isEmpty, let file = icloudFile { name = file.deletingPathExtension().lastPathComponent }
        }
    }

    private var canAdd: Bool {
        switch kind {
        case .local: !name.isEmpty
        case .remote: URL(string: url)?.scheme?.hasPrefix("http") == true
        case .icloud: icloudFile != nil && !name.isEmpty
        }
    }

    private func add() async {
        busy = true
        defer { busy = false }
        do {
            switch kind {
            case .local:
                try service.addLocal(name: name, content: ProfileDescription.blankTemplate)
            case .remote:
                let address = URL(string: url)!
                try await service.addRemote(name: name.isEmpty ? (address.host() ?? "远程配置") : name, url: address,
                                            autoUpdate: autoUpdate, interval: interval)
            case .icloud:
                try await service.addICloud(name: name, fileURL: icloudFile!)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// JSON 编辑器：保存前用 libbox 校验，无效时提示且不保存。
private struct ProfileEditor: View {
    let profile: Profile
    @Environment(ProfileService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if profile.isReadOnly {
                Label("无法在只读模式下编辑", systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .disabled(profile.isReadOnly)
                .frame(minWidth: 640, minHeight: 440)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout)
            }
        }
        .padding()
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem { Button("格式化") { do { text = try ProfileService.format(text); error = nil } catch { self.error = error.localizedDescription } }.disabled(profile.isReadOnly) }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task {
                        do {
                            try await service.save(text, for: profile)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .disabled(!loaded || profile.isReadOnly)
            }
        }
        .task {
            do {
                text = try await service.content(of: profile)
                loaded = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// 名称与（远程）更新设置。
private struct ProfileInfoEditor: View {
    @State var profile: Profile
    @Environment(ProfileService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("名称", text: $profile.name)
            if profile.kind == .remote {
                TextField("URL", text: $url)
                Toggle("自动更新", isOn: $profile.autoUpdate)
                Picker("更新间隔", selection: $profile.autoUpdateInterval) {
                    ForEach(ProfileDescription.intervalChoices, id: \.self) { Text(ProfileDescription.interval($0)).tag($0) }
                }
                .disabled(!profile.autoUpdate)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { url = profile.remoteURL?.absoluteString ?? "" }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if profile.kind == .remote {
                        guard let parsed = URL(string: url), parsed.scheme?.hasPrefix("http") == true else {
                            error = "只允许 HTTP 和 HTTPS URL"
                            return
                        }
                        profile.remoteURL = parsed
                        profile.autoUpdateInterval = RemoteUpdate.clamp(profile.autoUpdateInterval)
                    }
                    do {
                        try service.store.update(profile)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(profile.name.isEmpty)
            }
        }
    }
}

/// 分享远程订阅：导入链接与二维码。
private struct ShareProfileSheet: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let link = ProfileService.shareLink(for: profile) ?? ""
        VStack(spacing: 16) {
            Text(profile.name).font(.headline)
            if let image = Self.qrCode(link) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 220, height: 220)
            }
            Text(link).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
            HStack {
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                }
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    static func qrCode(_ text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

