import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultTheme") private var defaultTheme = TerminalTheme.default.name
    @AppStorage("defaultKeepAlive") private var defaultKeepAlive = true
    @AppStorage("defaultTerminalType") private var defaultTerminalType = "xterm-256color"

    var body: some View {
        NavigationStack {
            Form {
                Section("终端默认") {
                    Picker("主题", selection: $defaultTheme) {
                        ForEach(TerminalTheme.all) { t in Text(t.name).tag(t.name) }
                    }
                    Picker("终端类型", selection: $defaultTerminalType) {
                        Text("xterm-256color").tag("xterm-256color")
                        Text("xterm").tag("xterm")
                        Text("vt100").tag("vt100")
                    }
                    Toggle("新主机默认保持连接", isOn: $defaultKeepAlive)
                }
                Section("关于") {
                    LabeledContent("版本", value: "0.1.0")
                    LabeledContent("终端引擎", value: "SwiftTerm")
                    LabeledContent("传输层", value: "NMSSH (libssh2)")
                    LabeledContent("数据", value: "SwiftData + Keychain")
                    Link("参考开源项目", destination: URL(string: "https://github.com/migueldeicaza/SwiftTerm")!)
                }
                Section {
                    Text("凭据与私钥仅存于本机 Keychain,不离开设备。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}
