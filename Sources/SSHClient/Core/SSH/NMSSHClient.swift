import Foundation
import NMSSH

/// 基于 NMSSH(libssh2 封装)的 SSHClient 实现。
/// 覆盖:密码 / 公钥 / keyboard-interactive 认证、PTY Shell、SFTP、端口转发(经 libssh2 direct-tcpip)。
final class NMSSHClient: NSObject, SSHClient {

    weak var delegate: SSHClientDelegate?
    private var session: NMSSHSession?
    private var keyboardAnswers: (() -> [String])?
    private var answerIndex = 0

    var isConnected: Bool { session?.isConnected ?? false }

    // MARK: - 连接

    func connect(host: String, port: Int, username: String) async throws {
        let fpStore = "\(host):\(port)"
        let session = NMSSHSession(host: host, port: port, andUsername: username)
        self.session = session
        session.channel.delegate = self

        let connected = try await runOnBackground { session.connect() }
        guard connected else { throw SSHError.connectionFailed }

        // 主机密钥校验:与已记录指纹比对(首次为未知)
        let fingerprint = session.fingerprint(.md5) ?? ""
        let stored = HostKeyVerifier.knownFingerprint(host: fpStore)
        let trusted = (stored == fingerprint)
        let accepted = delegate?.sshClient(self, hostKeyFingerprint: fingerprint, known: trusted) ?? trusted
        guard accepted else {
            session.disconnect()
            throw SSHError.hostKeyRejected(fingerprint)
        }
        HostKeyVerifier.remember(host: fpStore, fingerprint: fingerprint)

        delegate?.sshClientDidConnect(self)
    }

    // MARK: - 认证

    func authenticate(_ method: SSHAuthMethod) async throws {
        guard let session = session else { throw SSHError.notConnected }
        switch method {
        case .password(let password):
            let ok = try await runOnBackground { session.authenticateByPassword(password) }
            guard ok else { throw SSHError.authenticationFailed }
        case .publicKey(let privateKeyPEM, _, let passphrase):
            // NMSSH 需要密钥文件,临时落盘后删除(不写入持久存储)
            let tmpDir = FileManager.default.temporaryDirectory
            let privURL = tmpDir.appendingPathComponent("id_\(UUID().uuidString)")
            try privateKeyPEM.write(to: privURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: privURL) }
            let ok = try await runOnBackground {
                session.authenticateByPublicKey(nil, privateKey: privURL.path, andPassword: passphrase)
            }
            guard ok else { throw SSHError.authenticationFailed }
        case .keyboardInteractive(let provider):
            self.keyboardAnswers = provider
            self.answerIndex = 0
            let ok = try await runOnBackground {
                session.authenticateByKeyboardInteractiveUsingBlock { [weak self] request in
                    guard let self else { return "" }
                    let answers = self.keyboardAnswers?() ?? []
                    let answer = self.answerIndex < answers.count ? answers[self.answerIndex] : ""
                    self.answerIndex += 1
                    return answer
                }
            }
            guard ok else { throw SSHError.authenticationFailed }
        }
        guard session.isAuthorized else { throw SSHError.authenticationFailed }
    }

    // MARK: - Shell

    func openShell(pty: String, cols: Int, rows: Int, env: [String: String]) async throws {
        guard let session = session else { throw SSHError.notConnected }
        session.channel.requestPty = true
        session.channel.ptyTerminalType = .xterm
        var vars = env
        vars["TERM"] = pty
        session.channel.environmentVariables = vars as NSDictionary
        let started = try await runOnBackground { session.channel.startShell(nil) }
        guard started else { throw SSHError.shellFailed }
        // 尺寸需在 startShell 之后设置
        session.channel.requestSizeWidth(UInt(cols), height: UInt(rows))
    }

    func write(_ data: Data) {
        _ = session?.channel.writeData(data, error: nil)
    }

    func resize(cols: Int, rows: Int) {
        session?.channel.requestSizeWidth(UInt(cols), height: UInt(rows))
    }

    // MARK: - SFTP

    func startSFTP() -> SFTPClient? {
        guard let session = session, session.isConnected else { return nil }
        let sftp = NMSFTP(session: session)
        sftp.connect()
        return NMSFTPClientWrapper(sftp: sftp)
    }

    // MARK: - 端口转发(经 libssh2 direct-tcpip)

    func startLocalForward(bindPort: UInt16, targetHost: String, targetPort: Int) throws -> PortForward {
        guard let session = session, let raw = session.rawSession else { throw SSHError.notConnected }
        return LocalPortForward(rawSession: OpaquePointer(raw), bindPort: bindPort,
                                targetHost: targetHost, targetPort: targetPort)
    }

    func startDynamicForward(bindPort: UInt16) throws -> PortForward {
        guard let session = session, let raw = session.rawSession else { throw SSHError.notConnected }
        return DynamicPortForward(rawSession: OpaquePointer(raw), bindPort: bindPort)
    }

    func disconnect() {
        session?.disconnect()
        delegate?.sshClientDidDisconnect(self, error: nil)
    }
}

// MARK: - 错误

enum SSHError: LocalizedError {
    case notConnected
    case connectionFailed
    case hostKeyRejected(String)
    case authenticationFailed
    case shellFailed
    case sftpFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "未建立连接"
        case .connectionFailed: return "连接失败"
        case .hostKeyRejected(let fp): return "主机密钥未被接受(\(fp))"
        case .authenticationFailed: return "认证失败"
        case .shellFailed: return "Shell 启动失败"
        case .sftpFailed(let m): return "SFTP 错误:\(m)"
        }
    }
}

// MARK: - NMSSH 通道回调 → 终端
// 注意:NMSSH 对每份数据会同时回调 didReadData(NSString) 与 didReadRawData(NSData),
// stderr 同理。为避免终端重复输出,这里只实现 raw 字节变体并直接喂给终端。

extension NMSSHClient: NMSSHChannelDelegate {
    func channel(_ channel: NMSSHChannel, didReadRawData data: Data) {
        delegate?.sshClient(self, didReceive: data)
    }

    func channel(_ channel: NMSSHChannel, didReadRawError error: Data) {
        delegate?.sshClient(self, didReceive: error)
    }

    func channelShellDidClose(_ channel: NMSSHChannel) {
        delegate?.sshClientDidDisconnect(self, error: nil)
    }
}

// MARK: - SFTP 包装(严格按 NMSFTP 真实 API)

final class NMSFTPClientWrapper: SFTPClient {
    private let sftp: NMSFTP

    init(sftp: NMSFTP) { self.sftp = sftp }

    func listDirectory(path: String) throws -> [SFTPFile] {
        guard let items = sftp.contentsOfDirectoryAtPath(path) else {
            throw SSHError.sftpFailed("无法列目录 \(path)")
        }
        return items.map { f in
            SFTPFile(
                name: f.filename,
                size: f.fileSize?.int64Value ?? 0,
                isDirectory: f.isDirectory,
                permissions: f.permissions ?? "",
                owner: "\(f.ownerUserID)",
                group: "\(f.ownerGroupID)",
                modified: f.modificationDate ?? Date()
            )
        }
    }

    func download(remotePath: String, to localURL: URL) throws {
        guard let data = sftp.contentsAtPath(remotePath) else {
            throw SSHError.sftpFailed("下载失败 \(remotePath)")
        }
        try data.write(to: localURL)
    }

    func upload(localURL: URL, to remotePath: String) throws {
        guard sftp.writeFileAtPath(localURL.path, toFileAtPath: remotePath) else {
            throw SSHError.sftpFailed("上传失败 \(remotePath)")
        }
    }

    func createDirectory(path: String) throws {
        guard sftp.createDirectoryAtPath(path) else {
            throw SSHError.sftpFailed("创建目录失败 \(path)")
        }
    }

    func remove(path: String) throws {
        let ok = sftp.fileExistsAtPath(path) ? sftp.removeFileAtPath(path)
                                            : sftp.removeDirectoryAtPath(path)
        guard ok else { throw SSHError.sftpFailed("删除失败 \(path)") }
    }

    func move(from: String, to: String) throws {
        guard sftp.moveItemAtPath(from, toPath: to) else {
            throw SSHError.sftpFailed("移动失败")
        }
    }
}
