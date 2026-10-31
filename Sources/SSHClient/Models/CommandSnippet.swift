import Foundation
import SwiftData

/// 可复用命令片段(参考 pockterm snippets)。
@Model
final class CommandSnippet {
    var id: UUID
    var title: String
    var command: String
    /// 可选:绑定到特定主机(为空表示全局可用)
    var hostId: UUID?

    init(title: String, command: String, hostId: UUID? = nil) {
        self.id = UUID()
        self.title = title
        self.command = command
        self.hostId = hostId
    }
}
