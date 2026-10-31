import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SFTPBrowserView: View {
    let host: Host
    @Environment(\.modelContext) private var modelContext
    @Query private var groups: [HostGroup]

    @State private var browser: SFTPBrowser?
    @State private var showAuth = false
    @State private var errorMessage: String?
    @State private var showCreateDir = false
    @State private var newDirName = ""

    var body: some View {
        Group {
            if let browser {
                browserContent(browser)
            } else {
                ProgressView("连接中…")
            }
        }
        .navigationTitle("文件 · \(host.alias)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if browser == nil { showAuth = true } }
        .sheet(isPresented: $showAuth) {
            AuthFormView(host: host,
                         onSubmit: { auth in showAuth = false; connect(with: auth) },
                         onCancel: { showAuth = false })
        }
        .alert("错误", isPresented: Binding(get: { errorMessage != nil },
                                           set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .sheet(isPresented: $showCreateDir) {
            TextField("目录名", text: $newDirName)
                .padding()
            Button("创建") {
                if let b = browser { b.createDir(newDirName) }
                newDirName = ""; showCreateDir = false
            }
        }
    }

    private func browserContent(_ browser: SFTPBrowser) -> some View {
        List {
            if browser.currentPath != "/" {
                Button { browser.up() } label: { Label("..", systemImage: "arrow.up") }
            }
            ForEach(browser.items) { file in
                HStack {
                    Image(systemName: file.isDirectory ? "folder" : "doc")
                    VStack(alignment: .leading) {
                        Text(file.name).lineLimit(1)
                        Text("\(file.isDirectory ? "目录" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)) · \(file.permissions)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if file.isDirectory { browser.enter(file) }
                }
                .contextMenu {
                    if !file.isDirectory {
                        Button("下载到文件 App") {
                            let tmp = FileManager.default.temporaryDirectory
                                .appendingPathComponent(file.name)
                            browser.download(file, to: tmp)
                        }
                    }
                    Button("删除", role: .destructive) { browser.delete(file) }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCreateDir = true } label: { Label("新建目录", systemImage: "folder.badge.plus") }
                    Button {
                        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
                        picker.delegate = DocumentPickerDelegate { url in browser.upload(url) }
                        UIApplication.shared.windows.first?.rootViewController?
                            .present(picker, animated: true)
                    } label: { Label("上传文件", systemImage: "arrow.up.doc") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .refreshable { browser.load() }
        .overlay { if browser.isLoading { ProgressView() } }
    }

    private func connect(with auth: SSHAuthMethod) {
        Task {
            do {
                let client = try await SSHConnectionHelper.connectClient(host: host,
                                                                       groups: groups, auth: auth)
                guard let sftp = client.startSFTP() else {
                    throw SSHError.sftpFailed("SFTP 初始化失败")
                }
                let b = SFTPBrowser(client: sftp, initialPath: "/")
                await MainActor.run { self.browser = b; b.load() }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }
}

/// 简单的文档选择器回调封装。
final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let onPick: (URL) -> Void
    init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first { onPick(url) }
    }
}
