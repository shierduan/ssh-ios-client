import Foundation
import NMSSH

/// 建立并认证一个独立 SSH 连接的辅助(用于 SFTP / 端口转发等需要独立会话的场景)。
enum SSHConnectionHelper {
    static func connectClient(host: Host,
                              groups: [HostGroup],
                              auth: SSHAuthMethod) async throws -> NMSSHClient {
        let resolved = CredentialResolver.resolve(host: host, groups: groups)
        let client = NMSSHClient()
        try await client.connect(host: host.hostname, port: host.port, username: resolved.username)
        try await client.authenticate(auth)
        return client
    }
}
