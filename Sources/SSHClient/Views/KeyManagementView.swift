import SwiftUI
import SwiftData

struct KeyManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SSHKey.name) private var keys: [SSHKey]

    @State private var showGenerate = false
    @State private var genName = ""
    @State private var genType: SSHKeyType = .ed25519
    @State private var showImport = false
    @State private var importPublic = ""
    @State private var importPrivate = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(keys) { key in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(key.name).font(.headline)
                            Spacer()
                            Text(key.type.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(key.publicKey)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .contextMenu {
                        Button("复制公钥") { UIPasteboard.general.string = key.publicKey }
                        Button("删除", role: .destructive) {
                            KeychainManager.delete(tag: key.keychainTag)
                            modelContext.delete(key)
                        }
                    }
                }
            }
            .navigationTitle("密钥")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showGenerate = true } label: { Label("生成密钥", systemImage: "plus") }
                        Button { showImport = true } label: { Label("导入密钥", systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showGenerate) { generateSheet }
            .sheet(isPresented: $showImport) { importSheet }
        }
    }

    private var generateSheet: some View {
        NavigationStack {
            Form {
                TextField("名称(可选)", text: $genName)
                Picker("类型", selection: $genType) {
                    ForEach(SSHKeyType.allCases) { t in Text(t.displayName).tag(t) }
                }
                Text("私钥仅存于 Keychain,并要求在读取时通过 Face ID / Touch ID 解锁。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("生成密钥")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showGenerate = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("生成") {
                        let comment = genName.isEmpty ? "SSHClient" : genName
                        let g = KeyGenerator.generate(genType, comment: comment)
                        let tag = KeychainManager.makeTag(prefix: "sshkey", id: UUID())
                        _ = KeychainManager.save(g.privateKeyPEM, tag: tag, requireBiometry: true)
                        let record = SSHKey(
                            name: genName.isEmpty ? "\(g.keyType.displayName) \(formattedNow())" : genName,
                            keyType: g.keyType,
                            publicKey: g.publicKeyOpenSSH,
                            keychainTag: tag
                        )
                        modelContext.insert(record)
                        showGenerate = false
                    }
                }
            }
        }
    }

    private var importSheet: some View {
        NavigationStack {
            Form {
                Section("公钥(OpenSSH 格式,可选)") {
                    TextEditor(text: $importPublic).frame(minHeight: 80)
                }
                Section("私钥(PEM / OpenSSH 格式)") {
                    TextEditor(text: $importPrivate).frame(minHeight: 120)
                }
            }
            .navigationTitle("导入密钥")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showImport = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        let tag = KeychainManager.makeTag(prefix: "sshkey", id: UUID())
                        _ = KeychainManager.save(importPrivate, tag: tag, requireBiometry: true)
                        let record = SSHKey(
                            name: "导入密钥 \(formattedNow())",
                            keyType: importPrivate.contains("OPENSSH PRIVATE KEY") ? .ed25519 : .rsa,
                            publicKey: importPublic.isEmpty ? "(未提供公钥)" : importPublic,
                            keychainTag: tag
                        )
                        modelContext.insert(record)
                        showImport = false
                    }
                    .disabled(importPrivate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func formattedNow() -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: Date())
    }
}
