import SwiftUI
import SwiftData

struct TerminalView: View {
    let host: Host

    @StateObject private var session: TerminalSession
    @Environment(\.modelContext) private var modelContext
    @Query private var groups: [HostGroup]

    @State private var showAuth = false
    @State private var errorMessage: String?

    init(host: Host) {
        self.host = host
        _session = StateObject(wrappedValue: TerminalSession(host: host))
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalUIView(session: session)
                .ignoresSafeArea(edges: .bottom)
            if session.isConnected {
                KeyboardAccessoryBar(
                    onInput: { session.write($0) },
                    onKey: { session.write($0.rawValue) }
                )
            }
        }
        .navigationTitle(session.title.isEmpty ? host.alias : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { showAuth = true }
        .sheet(isPresented: $showAuth) {
            AuthFormView(
                host: host,
                onSubmit: { auth in
                    showAuth = false
                    startConnect(with: auth)
                },
                onCancel: { showAuth = false }
            )
        }
        .alert("连接错误", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("未知主机密钥", isPresented: $session.showHostKeyAlert) {
            Button("取消", role: .cancel) {}
            Button("接受并继续") { acceptHostKey() }
        } message: {
            Text("指纹:\n\(session.pendingFingerprint)\n首次连接该主机,请确认指纹无误后继续。")
        }
    }

    private func startConnect(with auth: SSHAuthMethod) {
        let resolved = CredentialResolver.resolve(host: host, groups: groups)
        let username = resolved.username.isEmpty ? host.username : resolved.username
        Task {
            await session.connect(hostname: host.hostname, port: host.port,
                                  username: username, auth: auth)
            await MainActor.run {
                if session.isConnected { host.lastConnectedAt = Date() }
            }
        }
    }

    private func acceptHostKey() {
        HostKeyVerifier.remember(host: session.hostKeyIdentifier,
                                 fingerprint: session.pendingFingerprint)
        // 重新走一次连接(本次会用已记录的指纹通过校验)
        showAuth = true
    }
}
