import SwiftUI
import SwiftData

struct HostsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Host.alias) private var hosts: [Host]
    @Query(sort: \HostGroup.sortOrder) private var groups: [HostGroup]

    @State private var showAdd = false
    @State private var showImport = false
    @State private var importText = ""

    var body: some View {
        NavigationStack {
            List {
                if groups.isEmpty {
                    Section("分组") {
                        Text("暂无分组。新增主机时可创建分组,子组可继承凭据(参考 pockterm)。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("主机 (\(hosts.count))") {
                    ForEach(hosts) { host in
                        NavigationLink(value: host) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(host.alias).font(.headline)
                                Text("\(host.username)@\(host.hostname):\(host.port)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { modelContext.delete(hosts[i]) }
                    }
                }
            }
            .navigationTitle("SSHClient")
            .navigationDestination(for: Host.self) { host in
                HostDetailView(host: host)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAdd = true } label: { Label("新增主机", systemImage: "plus") }
                        Button { showImport = true } label: { Label("导入 ssh/config", systemImage: "doc.badge.plus") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddHostView() }
            .sheet(isPresented: $showImport) {
                NavigationStack {
                    Form {
                        Section("粘贴 ~/.ssh/config 内容") {
                            TextEditor(text: $importText)
                                .frame(minHeight: 200)
                        }
                    }
                    .navigationTitle("导入配置")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showImport = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                let parsed = SSHConfigImporter.parse(importText)
                                for h in SSHConfigImporter.toHosts(parsed) {
                                    modelContext.insert(h)
                                }
                                showImport = false
                            }
                        }
                    }
                }
            }
        }
    }
}
