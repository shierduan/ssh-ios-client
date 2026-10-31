import SwiftUI
import SwiftData

struct PortForwardSetupView: View {
    let host: Host
    let kind: Kind
    enum Kind { case local, dynamic }

    @Environment(\.modelContext) private var modelContext
    @Query private var groups: [HostGroup]

    @State private var bindPort = "8080"
    @State private var targetHost = ""
    @State private var targetPort = "80"
    @State private var status = "未启动"
    @State private var isRunning = false
    @State private var showAuth = false
    @State private var client: NMSSHClient?
    @State private var forward: PortForward?
    @State private var errorMessage: String?

    private var title: String {
        kind == .local ? "本地端口转发 (-L)" : "动态 SOCKS 转发 (-D)"
    }

    var body: some View {
        Form {
            Section("监听端口") {
                TextField(kind == .local ? "本地端口" : "SOCKS 端口", text: $bindPort)
                    .keyboardType(.numberPad)
            }
            if kind == .local {
                Section("转发目标") {
                    TextField("目标主机", text: $targetHost)
                    TextField("目标端口", text: $targetPort).keyboardType(.numberPad)
                }
            }
            Section("状态") {
                Text(status).foregroundStyle(isRunning ? .green : .secondary)
            }
            Section {
                if isRunning {
                    Button("停止", role: .destructive) { stop() }
                } else {
                    Button("启动") { showAuth = true }
                }
            }
        }
        .navigationTitle(title)
        .sheet(isPresented: $showAuth) {
            AuthFormView(host: host,
                         onSubmit: { auth in showAuth = false; start(with: auth) },
                         onCancel: { showAuth = false })
        }
        .alert("错误", isPresented: Binding(get: { errorMessage != nil },
                                           set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func start(with auth: SSHAuthMethod) {
        Task {
            do {
                let c = try await SSHConnectionHelper.connectClient(host: host, groups: groups, auth: auth)
                let port = UInt16(bindPort) ?? 8080
                let f: PortForward
                if kind == .local {
                    f = try c.startLocalForward(bindPort: port,
                                                targetHost: targetHost.isEmpty ? "localhost" : targetHost,
                                                targetPort: Int(targetPort) ?? 80)
                } else {
                    f = try c.startDynamicForward(bindPort: port)
                }
                await MainActor.run {
                    self.client = c
                    self.forward = f
                    self.isRunning = true
                    self.status = "正在监听本地端口 \(port)"
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func stop() {
        forward?.stop()
        forward = nil
        client = nil
        isRunning = false
        status = "未启动"
    }
}
