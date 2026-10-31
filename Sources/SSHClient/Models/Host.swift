import Foundation
import SwiftData

/// 认证方式。inherited 表示沿用所属分组的凭据(参考 pockterm 的 nested groups 继承)。
enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password = "password"
    case publicKey = "publicKey"
    case keyboardInteractive = "keyboardInteractive"
    case inherited = "inherited"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .password: return "密码"
        case .publicKey: return "公钥"
        case .keyboardInteractive: return "键盘交互(2FA)"
        case .inherited: return "继承分组"
        }
    }
}

@Model
final class Host {
    var id: UUID
    var alias: String
    var hostname: String
    var port: Int
    var username: String
    var authMethodRaw: String
    /// 关联 SSHKey.id(UUID 字符串);仅保存引用,私钥存 Keychain
    var keyReference: String?
    var groupId: UUID?
    var terminalType: String
    var themeName: String
    var fontName: String
    var fontSize: Double
    var keepAlive: Bool
    var useInheritedCredentials: Bool
    var createdAt: Date
    var lastConnectedAt: Date?
    var notes: String

    var authMethod: AuthMethod {
        get { AuthMethod(rawValue: authMethodRaw) ?? .password }
        set { authMethodRaw = newValue.rawValue }
    }

    init(alias: String,
         hostname: String,
         port: Int = 22,
         username: String = "",
         authMethod: AuthMethod = .password,
         keyReference: String? = nil,
         groupId: UUID? = nil,
         terminalType: String = "xterm-256color",
         themeName: String = "Default",
         fontName: String = "Menlo",
         fontSize: Double = 13,
         keepAlive: Bool = true,
         notes: String = "") {
        self.id = UUID()
        self.alias = alias
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authMethodRaw = authMethod.rawValue
        self.keyReference = keyReference
        self.groupId = groupId
        self.terminalType = terminalType
        self.themeName = themeName
        self.fontName = fontName
        self.fontSize = fontSize
        self.keepAlive = keepAlive
        self.useInheritedCredentials = (authMethod == .inherited)
        self.createdAt = Date()
        self.notes = notes
    }
}
