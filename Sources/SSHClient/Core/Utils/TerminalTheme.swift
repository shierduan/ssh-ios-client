import UIKit

/// 终端主题。SwiftTerm 负责 ANSI/256/TrueColor 调色板;
/// 此处提供背景、前景与光标色,以及可切换的预设。
struct TerminalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let background: UIColor
    let foreground: UIColor
    let cursor: UIColor

    static let `default` = TerminalTheme(
        id: "default", name: "默认(暗)",
        background: UIColor(white: 0.05, alpha: 1),
        foreground: UIColor(white: 0.92, alpha: 1),
        cursor: .systemGreen
    )

    static let light = TerminalTheme(
        id: "light", name: "浅色",
        background: .white,
        foreground: .black,
        cursor: .systemBlue
    )

    static let solarized = TerminalTheme(
        id: "solarized", name: "Solarized Dark",
        background: UIColor(red: 0.0, green: 0.17, blue: 0.21, alpha: 1),
        foreground: UIColor(red: 0.84, green: 0.85, blue: 0.76, alpha: 1),
        cursor: UIColor(red: 0.53, green: 0.66, blue: 0.0, alpha: 1)
    )

    static let all: [TerminalTheme] = [.default, .light, .solarized]

    static func named(_ name: String) -> TerminalTheme {
        all.first { $0.name == name } ?? .default
    }
}
