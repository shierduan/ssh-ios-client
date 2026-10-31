import SwiftUI
import SwiftData

struct HostDetailView: View {
    let host: Host
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section("连接") {
                LabeledContent("别名", value: host.alias)
                LabeledContent("地址", value: "\(host.hostname):\(host.port)")
                LabeledContent("用户", value: host.username.isEmpty ? "—" : host.username)
                LabeledContent("认证", value: host.authMethod.displayName)
            }
            Section("终端") {
                LabeledContent("终端类型", value: host.terminalType)
                LabeledContent("主题", value: host.themeName)
                LabeledContent("字体", value: "\(host.fontName) \(Int(host.fontSize))pt")
                Toggle("保持连接", isOn: .constant(host.keepAlive))
            }
            Section("快捷操作") {
                NavigationLink("打开终端", destination: TerminalView(host: host))
                NavigationLink("文件管理 (SFTP)", destination: SFTPBrowserView(host: host))
                NavigationLink("本地端口转发",
                               destination: PortForwardSetupView(host: host, kind: .local))
                NavigationLink("动态 SOCKS 转发",
                               destination: PortForwardSetupView(host: host, kind: .dynamic))
            }
            if !host.notes.isEmpty {
                Section("备注") { Text(host.notes) }
            }
        }
        .navigationTitle(host.alias)
    }
}
