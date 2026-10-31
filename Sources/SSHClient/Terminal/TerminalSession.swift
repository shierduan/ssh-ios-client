import SwiftUI
import SwiftTerm
import Combine

/// 一次终端会话:桥接 SwiftTerm(TerminalView)与 SSHClient。
/// 严格遵循 SwiftTerm 官方桥接范式:
///   用户输入 → send() → SSH 通道
///   SSH 输出 → feed() → 终端
///   尺寸变化 → sizeChanged() → requestPtyResize
final class TerminalSession: NSObject, ObservableObject {

    let id = UUID()
    let host: Host

    private(set) var ssh: SSHClient?
    private weak var terminalView: TerminalView?

    @Published var title: String = ""
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var showHostKeyAlert = false
    @Published var pendingFingerprint: String = ""
    private var hostKeyIdentifier: String = ""

    init(host: Host) { self.host = host }

    /// 由 UIViewRepresentable 在创建 TerminalView 后调用。
    func attach(_ view: TerminalView) {
        self.terminalView = view
        view.terminalDelegate = self
        applyTheme(TerminalTheme.named(host.themeName))
    }

    func applyTheme(_ theme: TerminalTheme) {
        terminalView?.backgroundColor = theme.background
        // SwiftTerm 的 ANSI 调色板可由 Terminal.setOptions 进一步定制(此处保留默认)
    }

    // MARK: - 连接入口

    func connect(hostname: String, port: Int, username: String, auth: SSHAuthMethod) async {
        hostKeyIdentifier = "\(hostname):\(port)"
        let client = NMSSHClient()
        client.delegate = self
        self.ssh = client
        do {
            try await client.connect(host: hostname, port: port, username: username)
            try await client.authenticate(auth)
            // 初始 80x24,布局完成后 sizeChanged 会同步真实尺寸
            let env = [
                "TERM": host.terminalType,
                "COLORTERM": "truecolor",
                "LC_ALL": "en_US.UTF-8",
                "LANG": "en_US.UTF-8"
            ]
            try await client.openShell(pty: host.terminalType, cols: 80, rows: 24, env: env)
            DispatchQueue.main.async { self.isConnected = true }
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
        }
    }

    func write(_ string: String) {
        ssh?.write(Data(string.utf8))
    }

    func disconnect() {
        ssh?.disconnect()
    }
}

// MARK: - SwiftTerm 终端代理

extension TerminalSession: TerminalViewDelegate {
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        ssh?.write(Data(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        ssh?.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        DispatchQueue.main.async { self.title = title }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // 可在 UI 中展示当前远端路径
    }
}

// MARK: - SSH 传输层代理

extension TerminalSession: SSHClientDelegate {
    func sshClientDidConnect(_ client: SSHClient) {}

    func sshClient(_ client: SSHClient, didReceive data: Data) {
        DispatchQueue.main.async { [weak self] in
            self?.terminalView?.feed(byteArray: ArraySlice<UInt8>(data))
        }
    }

    func sshClient(_ client: SSHClient, didChangeTitle title: String) {
        DispatchQueue.main.async { self.title = title }
    }

    func sshClientDidDisconnect(_ client: SSHClient, error: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            if let error = error { self.errorMessage = error.localizedDescription }
        }
    }

    func sshClient(_ client: SSHClient, hostKeyFingerprint: String, known: Bool) -> Bool {
        if known {
            return true
        }
        // 未知/不匹配:记录指纹并在 UI 中提示用户显式接受
        DispatchQueue.main.async {
            self.pendingFingerprint = hostKeyFingerprint
            self.showHostKeyAlert = true
        }
        return false
    }
}

// MARK: - SwiftUI 桥接

struct TerminalUIView: UIViewRepresentable {
    @ObservedObject var session: TerminalSession

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        session.attach(view)
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}
}
