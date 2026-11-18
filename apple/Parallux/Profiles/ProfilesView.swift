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
                    Label("还没有配置", systemImage: "doc.text")
                } description: {
                    Text("新建一份本地配置，或者导入远程订阅。")
                } actions: {
                    addMenu
                }
            } else {
                List {
                    ForEach(store.profiles) { profile in
                        ProfileRow(profile: profile, isSelected: profile.id == store.selectedID,
                                   isUpdating: service.updating.contains(profile.id))
                            .contentShape(Rectangle())
                            .onTapGesture { run { try store.select(profile.id) } }
                            .contextMenu { menu(for: profile) }
                    }
                    .onMove { source, destination in run { try store.move(fromOffsets: source, toOffset: destination) } }
                }
            }
        }
        .navigationSubtitle("\(store.profiles.count) 份配置")
        .toolbar { ToolbarItem { addMenu } }
        .sheet(item: $adding) { kind in AddProfileSheet(kind: kind) }
        .sheet(item: $editing) { profile in ProfileEditor(profile: profile) }
        .sheet(item: $sharing) { profile in ShareProfileSheet(profile: profile) }
        .sheet(item: $editingInfo) { profile in ProfileInfoEditor(profile: profile) }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.json, UTType(filenameExtension: "bpf") ?? .data]) { result in
            Task { await runAsync { try await service.importFile(try result.get()) } }
        }
        .alert("从链接导入", isPresented: $linkPrompt) {
            TextField("sing-box://import-remote-profile?url=…", text: $link)
            Button("导入") { let value = link; Task { await runAsync { try await service.importLink(value) } } }
            Button("取消", role: .cancel) {}
        }
        .alert("出错了", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var addMenu: some View {
        Menu {
            Button("新建本地配置…") { adding = .local }
            Button("从文件导入…") { importingFile = true }
            Divider()
            Button("添加远程订阅…") { adding = .remote }
            Button("从链接导入…") { link = ""; linkPrompt = true }
            Divider()
            Button("使用 iCloud 云盘中的文件…") { adding = .icloud }
        } label: {
            Label("添加", systemImage: "plus")
        }
    }

    @ViewBuilder private func menu(for profile: Profile) -> some View {
        Button("使用此配置") { run { try store.select(profile.id) } }
        Button(profile.isReadOnly ? "查看 JSON…" : "编辑 JSON…") { editing = profile }
        Button("名称与更新…") { editingInfo = profile }
        Menu("导出") {
            Button("导出为 .bpf（与 SFM 互通）…") { Task { await export(profile, bpf: true) } }
            Button("导出为 JSON…") { Task { await export(profile, bpf: false) } }
        }
        if profile.kind == .remote {
            Button("立即更新") { Task { await runAsync { try await service.update(profile) } } }
            Button("分享…") { sharing = profile }
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

private struct ProfileRow: View {
    let profile: Profile
    let isSelected: Bool
    let isUpdating: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.headline)
                Text(ProfileDescription.detail(profile, now: Date())).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isUpdating { ProgressView().controlSize(.small) }
            Text(profile.kind.title).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
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
                TextField("订阅地址", text: $url, prompt: Text("https://"))
                Toggle("自动更新", isOn: $autoUpdate)
                Picker("更新间隔", selection: $interval) {
                    ForEach(ProfileDescription.intervalChoices, id: \.self) { Text(ProfileDescription.interval($0)).tag($0) }
                }
                .disabled(!autoUpdate)
            case .icloud:
                LabeledContent("文件") {
                    Button(icloudFile?.lastPathComponent ?? "选择…") { pickingFile = true }
                }
            case .local:
                Text("从一份空白配置开始，保存后可以在编辑器里修改。").foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(busy ? "正在添加…" : "添加") { Task { await add() } }.disabled(busy || !canAdd)
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
                Label("远程配置只读：每次更新都会覆盖本地内容。要修改，请导出为 JSON 后作为本地配置导入。", systemImage: "lock")
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
                TextField("订阅地址", text: $url)
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
                            error = "订阅地址要以 http:// 或 https:// 开头"
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
            Text("分享「\(profile.name)」").font(.headline)
            if let image = Self.qrCode(link) {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 220, height: 220)
            }
            Text(link).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
            HStack {
                Button("拷贝链接") {
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

