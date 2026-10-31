import SwiftUI
import SwiftData

struct AddHostView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HostGroup.sortOrder) private var groups: [HostGroup]
    @Query private var keys: [SSHKey]

    @State private var alias = ""
    @State private var hostname = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: AuthMethod = .password
    @State private var selectedGroupID: UUID?
    @State private var selectedKeyID: UUID?
    @State private var notes = ""
    @State private var themeName = TerminalTheme.default.name
    @State private var fontName = "Menlo"
    @State private var fontSize = 13.0
    @State private var keepAlive = true

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("别名", text: $alias)
                    TextField("主机地址", text: $hostname)
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                    TextField("用户名", text: $username)
                }
                Section("分组") {
                    Picker("所属分组", selection: $selectedGroupID) {
                        Text("无").tag(UUID?.none)
                        ForEach(groups) { g in Text(g.name).tag(Optional(g.id)) }
                    }
                }
                Section("认证") {
                    Picker("方式", selection: $authMethod) {
                        ForEach(AuthMethod.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    if authMethod == .publicKey {
                        Picker("密钥", selection: $selectedKeyID) {
                            Text("选择密钥").tag(UUID?.none)
                            ForEach(keys) { k in Text(k.name).tag(Optional(k.id)) }
                        }
                    }
                }
                Section("终端") {
                    Picker("主题", selection: $themeName) {
                        ForEach(TerminalTheme.all) { t in Text(t.name).tag(t.name) }
                    }
                    TextField("字体", text: $fontName)
                    Stepper("字号 \(Int(fontSize))pt", value: $fontSize, in: 8...32)
                    Toggle("保持连接", isOn: $keepAlive)
                }
                Section("备注") {
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("新增主机")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(alias.isEmpty || hostname.isEmpty)
                }
            }
        }
    }

    private func save() {
        let host = Host(
            alias: alias,
            hostname: hostname,
            port: Int(port) ?? 22,
            username: username,
            authMethod: authMethod,
            keyReference: selectedKeyID?.uuidString,
            groupId: selectedGroupID,
            themeName: themeName,
            fontName: fontName,
            fontSize: fontSize,
            keepAlive: keepAlive,
            notes: notes
        )
        // 用 key id 字符串作为 keychain 引用
        if let keyID = selectedKeyID { host.keyReference = keyID.uuidString }
        modelContext.insert(host)
        dismiss()
    }
}
