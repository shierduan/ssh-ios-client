import Foundation
import SwiftData

/// 主机分组。支持嵌套(parentId),子组可继承父组的凭据与设置(参考 pockterm)。
@Model
final class HostGroup {
    var id: UUID
    var name: String
    var parentId: UUID?
    /// 可被子组/主机继承的凭据
    var inheritedUsername: String?
    var inheritedAuthRaw: String?
    var inheritedKeyReference: String?
    var sortOrder: Int

    init(name: String, parentId: UUID? = nil, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
    }
}
