import Foundation
import SwiftData

enum SSHKeyType: String, Codable, CaseIterable, Identifiable {
    case ed25519 = "ed25519"
    case rsa = "rsa"
    case ecdsa = "ecdsa"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ed25519: return "Ed25519"
        case .rsa: return "RSA"
        case .ecdsa: return "ECDSA"
        }
    }
}

/// SSH 密钥元数据。私钥本身只存于 Keychain,此处仅保留引用(tag)与公钥文本。
@Model
final class SSHKey {
    var id: UUID
    var name: String
    var keyType: String
    var publicKey: String
    /// Keychain 中检索私钥所用的 tag
    var keychainTag: String
    var passphraseProtected: Bool
    var createdAt: Date

    var type: SSHKeyType {
        SSHKeyType(rawValue: keyType) ?? .ed25519
    }

    init(name: String,
         keyType: SSHKeyType,
         publicKey: String,
         keychainTag: String,
         passphraseProtected: Bool = false) {
        self.id = UUID()
        self.name = name
        self.keyType = keyType.rawValue
        self.publicKey = publicKey
        self.keychainTag = keychainTag
        self.passphraseProtected = passphraseProtected
        self.createdAt = Date()
    }
}
