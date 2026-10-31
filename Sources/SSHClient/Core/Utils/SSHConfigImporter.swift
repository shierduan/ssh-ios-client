import Foundation
import SwiftData

/// 从 OpenSSH 风格的 config 文本中解析主机(参考 pockterm 的 "Import from ~/.ssh/config")。
/// 支持的指令: Host, HostName, User, Port, IdentityFile, ProxyJump(跳板机)。
struct SSHConfigImporter {

    struct ParsedHost {
        let pattern: String
        let hostName: String?
        let user: String?
        let port: Int?
        let identityFile: String?
        let proxyJump: String?
    }

    /// 解析整段文本,返回每个 Host 块的信息。
    static func parse(_ text: String) -> [ParsedHost] {
        var results: [ParsedHost] = []
        var current: [String: String] = [:]
        var currentHostPatterns: [String] = []

        func flush() {
            guard !currentHostPatterns.isEmpty else { return }
            for pattern in currentHostPatterns {
                // 跳过通配模式(*, ?),这些通常不是可直接连接的主机
                guard !pattern.contains("*"), !pattern.contains("?") else { continue }
                results.append(ParsedHost(
                    pattern: pattern,
                    hostName: current["hostname"],
                    user: current["user"],
                    port: current["port"].flatMap(Int.init),
                    identityFile: current["identityfile"],
                    proxyJump: current["proxyjump"]
                ))
            }
            currentHostPatterns = []
            current = [:]
        }

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts.dropFirst().joined(separator: " ")

            if key == "host" {
                flush()
                currentHostPatterns = value.components(separatedBy: .whitespaces)
            } else {
                current[key] = value
            }
        }
        flush()
        return results
    }

    /// 把解析结果转换为可插入 SwiftData 的 Host 列表。
    static func toHosts(_ parsed: [ParsedHost]) -> [Host] {
        parsed.map { p in
            Host(
                alias: p.pattern,
                hostname: p.hostName ?? p.pattern,
                port: p.port ?? 22,
                username: p.user ?? "",
                authMethod: .publicKey,
                notes: p.proxyJump.map { "跳板机: \($0)" } ?? ""
            )
        }
    }
}
