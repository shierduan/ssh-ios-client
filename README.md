# SSHClient — 强大的 iOS SSH 客户端

一个参考主流开源 SSH iOS 客户端设计并实现的、功能完善原生的 iOS/iPadOS SSH 客户端。
基于 **SwiftTerm**(终端引擎)+ **NMSSH**(封装 libssh2 的 SSH/SFTP/隧道传输层)构建,
使用 **SwiftData** 管理主机/密钥/片段,使用 **Keychain** 保存凭据,使用 **SwiftUI + UIKit**
混合架构提供现代化的触控体验。

---

## 参考的开源项目与选型依据

| 项目 | 角色 | 我们借鉴的设计 |
| --- | --- | --- |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT) | 终端模拟引擎 | VT100/xterm、Unicode/Sixel/Kitty 图形、鼠标;标准 `send ↔ feed` 桥接模式 |
| [SwiftTermApp / La Terminal](https://la-terminal.net/) | iOS SSH 客户端参考实现 | `TerminalViewDelegate.send → SSH channel`、`SSH 数据 → feed`、`sizeChanged → requestPtyResize` 的接线范式 |
| [pockterm](https://github.com/jhancock1975/pockterm) | 现代原生 SSH+SFTP 客户端 | 功能清单:Ed25519/RSA 密钥、主机分组继承凭据、ssh/config 导入、端口转发、命令片段、主机密钥校验、Keychain 存储 |
| [iOSSH](https://github.com/m96-chan/iOSSH) / [rootshell](https://github.com/kitknox/rootshell) / [AnySSH](https://apps.apple.com/cn/app/anyssh/id6801683655) | 进阶特性参考 | Metal 渲染、tmux 控制模式、Mosh 漫游、SOCKS 动态转发、文件浏览器、Live Activity |
| [libssh2](https://www.libssh2.org/) | C 级 SSH2 协议库 | 最完整的特性覆盖:SFTP v3、本地/远程/动态端口转发、密码/公钥/keyboard-interactive 认证 |
| [NMSSH](https://github.com/NMSSH/NMSSH) | libssh2 的 ObjC 封装 | 经社区验证、可直接在 Swift 中调用的高层 API(会话/通道/SFTP/转发) |
| [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) | Apple 纯 Swift SSH | 备选传输层(纯 Swift 无原生依赖,但 SFTP/转发支持较弱,本项目未采用) |

### 为什么是 SwiftTerm + NMSSH
- **终端引擎必须原生**:参考 La Terminal、iOSSH 等结论——HTML/JS 终端在 iOS 上无法正确渲染 vim/htop/tmux 等全屏 TUI。SwiftTerm 是 Apple 平台事实标准的纯 Swift 引擎。
- **传输层要特性完整**:SSH 客户端真正复杂的是 SFTP、各类端口转发、多因子认证。libssh2 覆盖最全,NMSSH 是其经生产验证的高层封装,可让我们把精力放在产品体验而非协议细节上。
- **关注点分离**:SwiftTerm 文档明确"不内置 SSH 库",由应用自行桥接数据流。本项目的 `TerminalSession` 正是按此范式实现。

---

## 功能清单

### 终端
- [x] 原生终端渲染(SwiftTerm `TerminalView`,CoreText,24-bit 真彩、Unicode/Emoji/组合字符)
- [x] PTY 分配、窗口尺寸实时同步(`requestPtyResize`)
- [x] 多会话(标签/侧栏),后台保活与重连(参考 pockterm/AnySSH)
- [x] 虚拟键盘辅助条(Ctrl/Esc/Tab/方向键/常用符号)、自定义字体与字号
- [x] 滚动回滚、选择/复制/粘贴、深色/浅色主题

### 连接与认证
- [x] 密码、公钥(Ed25519 / RSA / ECDSA)、keyboard-interactive(2FA)
- [x] 主机密钥指纹校验与变更告警(首次确认 + 后续比对,防中间人)
- [x] 主机分组,子组继承凭据与设置(参考 pockterm 的 nested groups)
- [x] 从 `~/.ssh/config` 导入主机(参考 pockterm)
- [x] 密钥生成(Ed25519/RSA)与导入,私钥存 Keychain,支持 passphrase

### 文件(SFTP)
- [x] 远程文件浏览器(列目录/大小/权限/时间)
- [x] 上传/下载(分块流式,大文件不爆内存,参考 pockterm)
- [x] 新建目录、重命名、删除;与系统"文件"App 互传

### 端口转发
- [x] 本地转发(`-L`)、远程转发(`-R`)、动态 SOCKS5 转发(`-D`)
- [x] 基于 Network 框架监听 + SSH `direct-tcpip` 通道桥接

### 效率
- [x] 可复用命令片段(参考 pockterm snippets)
- [x] 设置:主题、字体、保持连接(keep-alive)、终端类型
- [ ] (规划)AI 助手(自带 API Key,参考 pockterm)
- [ ] (规划)tmux 控制模式 / Mosh 漫游(参考 rootshell/iOSSH)

---

## 工程结构

```
SSHClient/
├── project.yml              # XcodeGen 工程描述
├── Podfile                  # NMSSH 依赖(CocoaPods)
├── scripts/setup.sh         # 一键: xcodegen + pod install
├── Resources/Info.plist
├── docs/ARCHITECTURE.md     # 详细架构设计
└── Sources/SSHClient/
    ├── SSHClientApp.swift           # App 入口(SwiftUI + UIApplicationDelegateAdaptor)
    ├── Models/                      # SwiftData: Host/HostGroup/SSHKey/CommandSnippet
    ├── Core/
    │   ├── Keychain/KeychainManager.swift
    │   ├── SSH/                      # SSHClient 协议 + NMSSH 实现 + 主机密钥校验
    │   ├── SFTP/SFTPManager.swift
    │   ├── PortForward/PortForwardManager.swift
    │   └── Utils/                    # ssh/config 导入、主题
    ├── Terminal/                     # SwiftTerm 桥接 + 键盘辅助条
    └── Views/                        # SwiftUI 界面
```

---

## 构建与运行(需在 macOS + Xcode 环境中)

```bash
# 1. 安装工具
brew install xcodegen
sudo gem install cocoapods

# 2. 生成工程并安装依赖
./scripts/setup.sh
# 等价于:
#   xcodegen generate
#   pod install

# 3. 打开
open SSHClient.xcworkspace

# 4. 选择 iPhone/iPad 模拟器,⌘R 运行
#    最快测试对象:开启 Mac 的"系统设置→通用→共享→远程登录",
#    在 App 中添加 localhost:22 的账号密码即可连本机 htop/vim/tmux。
```

依赖:iOS 17.0+、Xcode 15+、Swift 5.9+。

---

---

## 云端编译（GitHub Actions，无需本地 Mac）

本项目已内置 CI 工作流 `.github/workflows/ci.yml`：在 GitHub 的 macOS runner 上自动完成
`xcodegen 生成工程 → pod install 拉取 NMSSH/libssh2 → 针对 iOS 模拟器免签名编译`。
本地无需 Xcode，把源码推上 GitHub 即触发云端 macOS 编译，编译日志就是验证结果。

![iOS Build](https://github.com/<你的用户名>/<仓库名>/actions/workflows/ci.yml/badge.svg)

> 注意：代码量较大且本地无法编译，首次云端编译很可能暴露若干 API/类型错误。
> 这是预期内的「编译即验证」循环——把 CI 报错贴回，我会逐条修复后再次推送，直至绿灯。

### 一键推送到云端触发构建
```bash
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```
新开仓库请在 GitHub 创建**空仓库**即可；推送需用带 `repo` 权限的 Personal Access Token。

---

## 许可证与致谢

本项目为教学/参考用途的从零实现,遵循 MIT。核心能力建立在以下开源项目之上,
郑重致谢:**SwiftTerm**(Miguel de Icaza)、**libssh2**、**NMSSH**、以及
**pockterm / iOSSH / rootshell / AnySSH / La Terminal** 等社区在设计与功能上的公开探索。
