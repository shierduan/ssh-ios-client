import Foundation

/// 主机密钥指纹管理:首次连接确认后记录,后续比对,若变化则告警(防中间人)。
/// 参考 pockterm 的 host-key verification 设计。
enum HostKeyVerifier {

    private static let defaults = UserDefaults.standard

    private static func key(for host: String) -> String {
        "ssh_known_hosts_\(host)"
    }

    /// 该主机是否已有记录的指纹。
    static func isKnown(host: String) -> Bool {
        defaults.string(forKey: key(for: host)) != nil
    }

    /// 取出已记录的指纹(若有)。
    static func knownFingerprint(host: String) -> String? {
        defaults.string(forKey: key(for: host))
    }

    /// 记录/更新指纹。
    static func remember(host: String, fingerprint: String) {
        defaults.set(fingerprint, forKey: key(for: host))
    }
}
