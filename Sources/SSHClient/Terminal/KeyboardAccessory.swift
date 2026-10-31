import SwiftUI

/// 虚拟键盘辅助条:为无实体键盘的场景提供 Ctrl/Esc/Tab/方向键/常用符号(参考 pockterm/AnySSH)。
struct KeyboardAccessoryBar: View {
    let onInput: (String) -> Void
    let onKey: (KeyCode) -> Void

    enum KeyCode: String {
        case esc = "\u{1b}"
        case tab = "\t"
        case up = "\u{1b}[A"
        case down = "\u{1b}[B"
        case left = "\u{1b}[D"
        case right = "\u{1b}[C"
        case ctrlC = "\u{03}"
        case ctrlD = "\u{04}"
        case ctrlZ = "\u{1a}"
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([KeyCode.esc, .tab, .ctrlC, .ctrlD, .ctrlZ], id: \.self.rawValue) { k in
                    keyButton(k.rawValue, label: label(for: k))
                }
                Divider().frame(height: 28)
                ForEach([KeyCode.up, .down, .left, .right], id: \.self.rawValue) { k in
                    keyButton(k.rawValue, label: arrow(for: k))
                }
                Divider().frame(height: 28)
                ForEach(["|", "/", "~", "sudo ", "cd ", "ls -la", "clear"], id: \.self) { s in
                    Button(action: { onInput(s) }) {
                        Text(s).font(.system(size: 13, design: .monospaced))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    private func keyButton(_ value: String, label: String) -> some View {
        Button(action: { onKey(KeyCode(rawValue: value) ?? .esc) }) {
            Text(label).font(.system(size: 13, design: .monospaced))
        }
        .buttonStyle(.bordered)
    }

    private func label(for k: KeyCode) -> String {
        switch k {
        case .esc: return "Esc"
        case .tab: return "Tab"
        case .ctrlC: return "C-c"
        case .ctrlD: return "C-d"
        case .ctrlZ: return "C-z"
        default: return k.rawValue
        }
    }

    private func arrow(for k: KeyCode) -> String {
        switch k {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        default: return "?"
        }
    }
}
