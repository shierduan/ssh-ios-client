import Foundation
import Security

/// 轻量 Keychain 封装。所有密码、私钥、passphrase 一律存于此,绝不写入 SwiftData 或磁盘明文。
enum KeychainManager {

    private static let service = "com.example.SSHClient"

    /// 是否要求生物识别(Face ID / Touch ID)才能读取。
    static func save(_ value: String, tag: String, requireBiometry: Bool = false) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        // 先删后写,保证可更新
        _ = delete(tag: tag)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        if requireBiometry {
            if let access = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                nil
            ) {
                query[kSecAttrAccessControl as String] = access
            }
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load(tag: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(tag: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// 生成稳定且唯一的 tag,用于把某把密钥/某主机密码映射到 Keychain 条目。
    static func makeTag(prefix: String, id: UUID) -> String {
        "\(prefix).\(id.uuidString)"
    }
}
