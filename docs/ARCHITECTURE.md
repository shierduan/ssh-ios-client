# 架构设计文档

> 本文档说明 SSHClient 的模块划分、数据流、关键技术决策,以及它们如何从被参考的开源项目中提炼而来。

## 1. 总体分层

```
┌──────────────────────────────────────────────────────────┐
│                       SwiftUI 界面层                       │
│  HostsListView / HostDetailView / KeyManagementView /     │
│  SettingsView / SnippetsView / SFTPBrowserView            │
└───────────────┬──────────────────────────┬───────────────┘
                │ 触发连接/传输              │ 读取模型
                ▼                          ▼
┌──────────────────────────┐   ┌──────────────────────────┐
│   Terminal 桥接层         │   │   SwiftData 持久层        │
│  TerminalSession         │   │  Host/HostGroup/          │
│  (SwiftTerm TerminalView │   │  SSHKey/CommandSnippet    │
│   + TerminalViewDelegate)│   └──────────────────────────┘
└───────────────┬──────────┘
                │ send(data) / sizeChanged(cols,rows)
                ▼
┌──────────────────────────┐
│   SSH 传输层 (SSHClient)  │  协议 + NMSSH 实现
│  connect/auth/openShell/  │  ── 封装 libssh2 ──
│  read/write/forward/SFTP  │
└───────────────┬──────────┘
                │ libssh2 C API
                ▼
        ┌────────────────┐
        │  远端 SSH 服务器 │
        └────────────────┘

凭据/私钥: Keychain(独立于 SwiftData,永不落明文)
```

## 2. 终端引擎:SwiftTerm 桥接范式

参考 SwiftTerm 官方文档与 SwiftTermApp/La Terminal,`TerminalView`(UIKit)通过
`TerminalViewDelegate` 与应用通信。本项目的 `TerminalSession` 充当该 delegate,实现三条数据流:

1. **用户输入 → SSH**:`send(source:data:)` 中把字节写入 SSH 通道
   ```swift
   func send(source: TerminalView, data: ArraySlice<UInt8>) {
       sshClient?.write(Data(data))
   }
   ```
2. **SSH 输出 → 终端**:通道收到数据后调用 `terminalView.feed(byteArray:)`
3. **尺寸变化 → SSH**:`sizeChanged(source:newCols:newRows:)` 中调用 `requestPtyResize`

环境变量的构造沿用官方推荐:
```swift
let env = Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true)
```

SwiftUI 侧通过 `UIViewRepresentable` 包裹 `TerminalView`,并把 `TerminalSession` 作为
`terminalDelegate` 注入;会话对象同时持有 `SSHClient` 引用,形成"UI ↔ 终端引擎 ↔ SSH"闭环。

## 3. SSH 传输层:协议 + 实现分离

定义 `SSHClient` 协议,使传输实现可替换(NMSSH / 未来的 libssh2 直连 / swift-nio-ssh):

```swift
protocol SSHClient {
    var delegate: SSHClientDelegate? { get set }
    func connect(host: String, port: Int) async throws
    func authenticate(_ method: AuthMethod) async throws
    func openShell(pty: String, cols: Int, rows: Int, env: [String:String]) async throws
    func write(_ data: Data)
    func resize(cols: Int, rows: Int)
    func startSFTP() -> SFTPHandle?
    func openLocalForward(...) / openDynamicForward(...) // 端口转发
    func disconnect()
}
```

`NMSSHClient` 用 NMSSH 实现:
- 连接/认证使用 `NMSSHSession`(`connect()` / `authenticateByPassword` / `authenticateByPublicKey`)
- Shell 通道:`session.channel.requestPty = "xterm-256color"` → `requestPtySize(rows, cols)` → `startShell()`
- 流式读取:采用 `NMSessionChannelDelegate` 的 `didReadRawData`,在主线程外把 `Data` 喂给终端
- SFTP:`NMSFTP(session:)` 提供列目录/上传/下载/删除/建目录
- 主机密钥:NMSSH 暴露 `session.rawSession`(libssh2 session),可在握手后读取服务端
  `ssh-ed25519`/`ssh-rsa` 指纹做首次确认与后续比对(参考 pockterm 的 host-key verification)

> 为何协议化:rootshell/iOSSH 等前沿项目证明了"可插拔传输"的价值(如切换 libghostty-vt 后端)。
> 本项目以 NMSSH 为默认实现,但保留切换到 libssh2 直连或 swift-nio-ssh 的空间。

## 4. 持久层:SwiftData

- `Host`:别名、地址、端口、用户名、认证方式、默认密钥引用、分组、终端类型、主题、是否启用 keep-alive
- `HostGroup`:嵌套分组,子组可继承凭据与设置(参考 pockterm nested groups)
- `SSHKey`:密钥元数据(名称、类型 Ed25519/RSA、公钥、Keychain 引用);**私钥仅在 Keychain**
- `CommandSnippet`:标题 + 命令文本,可绑定到主机

## 5. 安全:Keychain

- 密码、私钥、passphrase 一律存入 Keychain(`kSecClassGenericPassword` / `kSecClassKey`)
- 生物识别( Face ID / Touch ID )解锁敏感操作,`Info.plist` 声明 `NSFaceIDUsageDescription`
- 绝不将密钥写入 SwiftData 或磁盘明文

## 6. 端口转发设计

- **本地转发(-L)**:`NWListener` 监听本地端口 → 每来一个连接,通过 SSH `direct-tcpip` 通道
  连到目标(host:port)→ 双向搬运数据
- **远程转发(-R)**:请求服务端 `tcpip-forward` 全局请求,将远端端口流量回送本地
- **动态转发(-D)**:本地起 SOCKS5 代理,每个客户端连接按 SOCKS 协商出的目标开 `direct-tcpip`

NMSSH 的 `openForwardChannel(toHost:port:)` 用于建立 `direct-tcpip`。该部分依赖传输层能力,
需在真机/模拟器上联调验证(已在 README 标注为需验证项)。

## 7. 后台与重连

- iOS 不允许后台长驻 SSH,但可在 `beginBackgroundTask` 内保持短暂活跃;
- 切回前台时检查连接存活:存活则复用 shell,断开则新建(参考 pockterm/iOSSH 行为);
- 需要真正"断线不断 shell"时应使用远程 tmux(已在 UI 中引导用户)。

## 8. 后续演进路线

1. AI 助手(自带 API Key,参考 pockterm)
2. tmux 控制模式 / Mosh 兼容漫游(参考 rootshell/iOSSH)
3. Metal 加速渲染(参考 iOSSH/rootshell)
4. 文件提供器(File Provider)把 SFTP 挂进"文件" App(参考 Secure Shellfish)
5. iCloud 同步主机与密钥(参考 La Terminal)
