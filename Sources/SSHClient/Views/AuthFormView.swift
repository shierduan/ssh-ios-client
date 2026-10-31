import SwiftUI
import SwiftData

/// 复用的认证表单:收集密码/密钥后构造 SSHAuthMethod。
/// 被终端、SFTP、端口转发三处共用,避免重复逻辑。
struct AuthFormView: View {
    let host: Host
    @Query private var keys: [SSHKey]

    @State private var method: AuthMethod = .password
    @State private var password = ""
    @State private var selectedKeyID: UUID?
    @State private var passphrase = ""

    let onSubmit: (SSHAuthMethod) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("认证方式") {
                    Picker("方式", selection: $method) {
                        ForEach([AuthMethod.password, .publicKey, .keyboardInteractive], id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if method == .password {
                    SecureField("密码", text: $password)
                }
                if method == .publicKey {
                    Picker("密钥", selection: $selectedKeyID) {
                        Text("选择密钥").tag(UUID?.none)
                        ForEach(keys) { k in Text(k.name).tag(Optional(k.id)) }
                    }
                    SecureField("Passphrase(可选)", text: $passphrase)
                }
                if method == .keyboardInteractive {
                    Text("服务器将提示输入验证码/密码。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("连接 \(host.alias)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("连接") {
                        if let auth = CredentialResolver.buildAuth(method: method,
                                                                  password: password,
                                                                  keyID: selectedKeyID,
                                                                  passphrase: passphrase,
                                                                  keys: keys) {
                            onSubmit(auth)
                        }
                    }
                    .disabled(method == .publicKey && selectedKeyID == nil)
                }
            }
        }
    }
}
