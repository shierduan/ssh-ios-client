import Foundation
import CryptoKit
import Security

/// 在设备本地生成 SSH 密钥(RSA / Ed25519),私钥仅写入 Keychain。
/// Ed25519 使用 CryptoKit;RSA 使用 Security 框架并转换为 OpenSSH 格式。
enum KeyGenerator {

    struct GeneratedKey {
        let keyType: SSHKeyType
        let publicKeyOpenSSH: String      // 形如 "ssh-ed25519 AAAA... comment"
        let privateKeyPEM: String         // 可写入临时文件供 libssh2/NMSSH 使用的 PEM
        let privateKeyData: Data          // 存入 Keychain 的原始私钥材料
    }

    static func generate(_ type: SSHKeyType, comment: String) -> GeneratedKey {
        switch type {
        case .ed25519: return generateEd25519(comment: comment)
        case .rsa: return generateRSA(comment: comment)
        case .ecdsa: return generateECDSA(comment: comment)
        }
    }

    // MARK: - Ed25519

    private static func generateEd25519(comment: String) -> GeneratedKey {
        let key = Curve25519.Signing.PrivateKey()
        let pub = key.publicKey.rawRepresentation
        let priv = key.rawRepresentation

        var pubBlob = Data()
        pubBlob.append(sshString("ssh-ed25519".data(using: .ascii)!))
        pubBlob.append(sshString(pub))
        let publicOpenSSH = "ssh-ed25519 " + pubBlob.base64EncodedString() + " " + comment

        let pem = buildOpenSSHPrivateKey(pubBlob: pubBlob, priv: priv, comment: comment)
        return GeneratedKey(keyType: .ed25519, publicKeyOpenSSH: publicOpenSSH,
                            privateKeyPEM: pem, privateKeyData: priv)
    }

    // MARK: - RSA (2048)

    private static func generateRSA(comment: String) -> GeneratedKey {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let privateSec = SecKeyCreateRandomKey(attrs as CFDictionary, &error),
              let publicSec = SecKeyCopyPublicKey(privateSec) else {
            fatalError("RSA 生成失败: \(error?.takeRetainedValue().localizedDescription ?? "")")
        }

        // 公钥:解析 DER → OpenSSH "ssh-rsa"
        let pubDER = SecKeyCopyExternalRepresentation(publicSec, nil) as Data
        let (modulus, exponent) = parseRSAPublicDER(pubDER)
        var blob = Data()
        blob.append(sshString("ssh-rsa".data(using: .ascii)!))
        blob.append(sshString(exponent))
        blob.append(sshString(modulus))
        let publicOpenSSH = "ssh-rsa " + blob.base64EncodedString() + " " + comment

        // 私钥:PKCS#1 DER → PEM
        let privDER = SecKeyCopyExternalRepresentation(privateSec, nil) as Data
        let pem = derToPEM(privDER, header: "RSA PRIVATE KEY")

        return GeneratedKey(keyType: .rsa, publicKeyOpenSSH: publicOpenSSH,
                            privateKeyPEM: pem, privateKeyData: privDER)
    }

    // MARK: - ECDSA (P-256, 暂以 Ed25519/RSA 为主,此处给出占位实现)

    private static func generateECDSA(comment: String) -> GeneratedKey {
        // 设备上优先使用 Ed25519;ECDSA 如需可基于 CryptoKit P256 扩展点实现。
        // 为保持可用,降级为 Ed25519。
        return generateEd25519(comment: comment)
    }

    // MARK: - 编码辅助

    private static func sshString(_ data: Data) -> Data {
        var d = Data()
        d.append(UInt32(data.count).bigEndianData)
        d.append(data)
        return d
    }

    private static func derToPEM(_ der: Data, header: String) -> String {
        let b64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN \(header)-----\n\(b64)-----END \(header)-----\n"
    }

    /// 构造 OpenSSH 新版私钥格式(无加密),libssh2/NMSSH 可识别。
    private static func buildOpenSSHPrivateKey(pubBlob: Data, priv: Data, comment: String) -> String {
        var body = Data()
        body.append("openssh-key-v1\0".data(using: .ascii)!)
        body.append(sshString("none"))   // cipher
        body.append(sshString("none"))   // kdf
        body.append(sshString(Data()))   // kdf options
        body.append(UInt32(1).bigEndianData) // 密钥数量
        body.append(sshString(pubBlob))  // 公钥 blob

        var privSection = Data()
        let check: UInt32 = 0x1234_5678
        privSection.append(check.bigEndianData)
        privSection.append(check.bigEndianData)
        privSection.append(sshString(pubBlob))
        privSection.append(sshString(priv))
        privSection.append(sshString(comment.data(using: .utf8) ?? Data()))
        var pad: UInt8 = 1
        while privSection.count % 8 != 0 { privSection.append(pad); pad += 1 }
        body.append(sshString(privSection))

        let b64 = body.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN OPENSSH PRIVATE KEY-----\n\(b64)-----END OPENSSH PRIVATE KEY-----\n"
    }

    /// 解析 PKCS#1 RSAPublicKey ::= SEQUENCE { INTEGER n, INTEGER e }
    private static func parseRSAPublicDER(_ der: Data) -> (modulus: Data, exponent: Data) {
        var cursor = der.startIndex
        precondition(der[cursor] == 0x30, "期望 SEQUENCE")
        _ = readTLVLength(der, &cursor)            // 跳过外层 SEQUENCE
        precondition(der[cursor] == 0x02, "期望 INTEGER(n)")
        let n = readInteger(&cursor, der)
        precondition(der[cursor] == 0x02, "期望 INTEGER(e)")
        let e = readInteger(&cursor, der)
        // 去前导 0x00
        let modulus = n.first == 0 ? n.dropFirst() : n[...]
        return (Data(modulus), e)
    }

    private static func readTLVLength(_ der: Data, _ cursor: inout Int) -> Int {
        cursor += 1
        let first = der[cursor]; cursor += 1
        if first < 0x80 { return Int(first) }
        let bytes = Int(first) & 0x7F
        var len = 0
        for _ in 0..<bytes { len = (len << 8) | Int(der[cursor]); cursor += 1 }
        return len
    }

    private static func readInteger(_ cursor: inout Int, _ der: Data) -> Data {
        _ = readTLVLength(der, &cursor) // 跳过 INTEGER tag + length
        let len = readTLVLength(der, &cursor)
        let value = der[cursor..<cursor+len]; cursor += len
        return Data(value)
    }
}

extension UInt32 {
    var bigEndianData: Data {
        var v = self.bigEndian
        return Data(bytes: &v, count: MemoryLayout<UInt32>.size)
    }
}
