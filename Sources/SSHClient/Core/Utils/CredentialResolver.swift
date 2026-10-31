import Foundation
import SwiftData

/// 凭据解析:沿父分组向上继承用户名/认证方式/密钥(参考 pockterm 的 nested groups 继承)。
enum CredentialResolver {

    static func resolve(host: Host, groups: [HostGroup]) -> (username: String, auth: AuthMethod, keyRef: String?) {
        var username = host.username
        var auth: AuthMethod = host.authMethod == .inherited
            ? AuthMethod(rawValue: inheritedAuthRaw(groups, host)) ?? .password
            : host.authMethod
        var keyRef = host.keyReference

        var group = groups.first { $0.id == host.groupId }
        while let g = group {
            if username.isEmpty { username = g.inheritedUsername ?? "" }
            if keyRef == nil, let k = g.inheritedKeyReference { keyRef = k }
            group = groups.first { $0.id == g.parentId }
        }
        return (username, auth, keyRef)
    }

    private static func inheritedAuthRaw(_ groups: [HostGroup], _ host: Host) -> String {
        var group = groups.first { $0.id == host.groupId }
        while let g = group {
            if let a = g.inheritedAuthRaw { return a }
            group = groups.first { $0.id == g.parentId }
        }
        return AuthMethod.password.rawValue
    }

    /// 把界面采集的认证输入构造为 SSHAuthMethod。
    static func buildAuth(method: AuthMethod,
                          password: String,
                          keyID: UUID?,
                          passphrase: String,
                          keys: [SSHKey]) -> SSHAuthMethod? {
        switch method {
        case .password:
            return .password(password)
        case .publicKey:
            guard let keyID,
                  let key = keys.first(where: { $0.id == keyID }),
                  let pem = KeychainManager.load(tag: key.keychainTag) else { return nil }
            return .publicKey(privateKeyPEM: pem,
                              publicKeyPath: nil,
                              passphrase: passphrase.isEmpty ? nil : passphrase)
        case .keyboardInteractive:
            return .keyboardInteractive(answersProvider: { [] })
        case .inherited:
            return nil
        }
    }
}
