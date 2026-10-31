import Foundation

// MARK: - 认证方式

/// 抽象认证方式,使 UI 与具体传输实现解耦。
enum SSHAuthMethod: Equatable {
    case password(String)
    case publicKey(privateKeyPEM: String, publicKeyPath: String?, passphrase: String?)
    case keyboardInteractive(answersProvider: () -> [String])
}

// MARK: - SFTP 抽象

struct SFTPFile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let size: Int64
    let isDirectory: Bool
    let permissions: String
    let owner: String
    let group: String
    let modified: Date
}

/// SFTP 客户端抽象(实现见 NMSSHClient / 未来的 libssh2 直连)。
protocol SFTPClient {
    func listDirectory(path: String) throws -> [SFTPFile]
    func download(remotePath: String, to localURL: URL) throws
    func upload(localURL: URL, to remotePath: String) throws
    func createDirectory(path: String) throws
    func remove(path: String) throws
    func move(from: String, to: String) throws
}

// MARK: - 端口转发抽象

/// 一个已建立的端口转发,stop() 即关闭。
protocol PortForward: AnyObject {
    var localPort: UInt16 { get }
    func stop()
}

// MARK: - 传输层回调

protocol SSHClientDelegate: AnyObject {
    func sshClientDidConnect(_ client: SSHClient)
    /// 收到远端数据,应喂给终端。
    func sshClient(_ client: SSHClient, didReceive data: Data)
    func sshClient(_ client: SSHClient, didChangeTitle title: String)
    func sshClientDidDisconnect(_ client: SSHClient, error: Error?)
    /// 返回 true 表示接受该主机密钥(用于首次确认与变更告警)。
    func sshClient(_ client: SSHClient, hostKeyFingerprint: String, known: Bool) -> Bool
}

// MARK: - 传输层协议

/// SSH 传输层统一接口。默认实现为 NMSSHClient(封装 libssh2)。
/// 协议化便于未来切换到 libssh2 直连或 swift-nio-ssh(参考 rootshell/iOSSH 的可插拔后端思路)。
protocol SSHClient: AnyObject {
    var delegate: SSHClientDelegate? { get set }
    var isConnected: Bool { get }

    func connect(host: String, port: Int, username: String) async throws
    func authenticate(_ method: SSHAuthMethod) async throws
    func openShell(pty: String, cols: Int, rows: Int, env: [String: String]) async throws
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    func startSFTP() -> SFTPClient?
    func startLocalForward(bindPort: UInt16, targetHost: String, targetPort: Int) throws -> PortForward
    func startDynamicForward(bindPort: UInt16) throws -> PortForward
    func disconnect()
}

// MARK: - 后台执行辅助

extension SSHClient {
    /// 把阻塞式的 libssh2/NMSSH 调用放到后台队列,避免卡住主线程。
    func runOnBackground<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try work()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}
