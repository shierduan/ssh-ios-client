import SwiftUI
import SwiftData

struct SnippetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CommandSnippet.title) private var snippets: [CommandSnippet]

    @State private var showAdd = false
    @State private var title = ""
    @State private var command = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(snippets) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.title).font(.headline)
                        Text(s.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .contextMenu { Button("复制") { UIPasteboard.general.string = s.command } }
                }
                .onDelete { idx in for i in idx { modelContext.delete(snippets[i]) } }
            }
            .navigationTitle("命令片段")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField("标题", text: $title)
                        TextField("命令", text: $command, axis: .vertical)
                            .lineLimit(4...)
                    }
                    .navigationTitle("新增片段")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("保存") {
                                let s = CommandSnippet(title: title.isEmpty ? command : title, command: command)
                                modelContext.insert(s)
                                showAdd = false
                            }
                            .disabled(command.isEmpty)
                        }
                    }
                }
            }
        }
    }
}
