# 云端编译状态与排查记录

> 用途：本机是 Windows，**无法本地编译 iOS 工程**，全部验证依赖 GitHub Actions 的 macOS runner。
> 本文记录环境限制、日志获取方式、已解决的编译问题与当前阻塞点，供后续会话直接接续。

## 1. 仓库与 CI

| 项 | 值 |
| --- | --- |
| 仓库 | https://github.com/shierduan/ssh-ios-client （**public**） |
| 默认分支 | `main` |
| 工作流 | `.github/workflows/ci.yml`，push 到 `main/master/develop` 即触发（也支持 `workflow_dispatch` 手动触发） |
| Runner | `macos-latest` → 实测 **Xcode 26.6 / Swift 6.3.3 / SDK iphonesimulator26.5**（arm64 Apple Silicon） |
| 构建脚本 | `scripts/ci.sh`（xcodegen → pod install → xcodebuild 免签名编模拟器） |

## 2. 日志获取（重要：别走 Actions Logs API）

**GitHub 的 Actions 日志接口不可用**：`GET /repos/.../actions/jobs/{id}/logs` 会 302 到 Azure blob，
在本机代理环境下返回 `401 InvalidAuthenticationInfo`（且 `Location` 为空，无法手动跟随）。
同样 `raw.githubusercontent.com` 也不可达；`curl` 走代理同样失败。**只有 `api.github.com` 可用。**

因此 CI 做了改造：构建结束后（无论成败）把日志**提交回仓库的独立分支 `ci-log`**：

| 文件（在 `ci-log` 分支） | 内容 |
| --- | --- |
| `ci-build.log` | 完整构建日志（较大，~300KB，代理下易截断） |
| `ci-summary.txt` | **精简摘要**：error/BUILD 行 + linker/符号行 + 尾部 80 行（**优先读这个**） |

读取方式（走 `api.github.com`，可正常访问）：

```python
# Accept: application/vnd.github.v3.raw 可直接拿原文
GET /repos/shierduan/ssh-ios-client/contents/ci-summary.txt?ref=ci-log
```

`ci-log` 不在工作流的触发分支列表里，所以回写日志**不会造成循环触发**。

## 3. 推送方式（重要：git over https 被代理阻断）

本机 `git push https://github.com/...` 会失败：`CONNECT tunnel failed, response 502`
（偶发 `schannel: server closed abruptly`）。但早期曾成功过，属代理侧不稳定。

**解决办法：绕过 git，直接用 GitHub contents API 提交文件** —— 已封装为
`scripts/gh_push_api.py`（同样会生成 commit 并触发 CI）：

```bash
export GH_TOKEN=<PAT>
export GH_OWNER=shierduan
export GH_REPO=ssh-ios-client
export GH_BRANCH=main
python3 scripts/gh_push_api.py "<commit message>" <file1> [file2 ...]
```

注意：该脚本早期有 bug —— 用 `lstrip("./")` 归一化路径会把 `.github/...` 的点吃掉，
导致文件被写到错误路径 `github/workflows/ci.yml`。**已修正为只去掉一次 `./` 前缀**。

## 4. 已解决 / 已定位的问题（按时间顺序）

| # | 现象 | 根因 | 处理 |
| --- | --- | --- | --- |
| 1 | `pod install` 报 `CocoaPods could not find compatible versions for pod "NMSSH (~> 2.4)"` | NMSSH 最新发布是 **2.3.1**，根本没有 2.4.x | Podfile 改为 `pod 'NMSSH', '~> 2.3'` |
| 2 | `xcodebuild: error: Could not resolve package dependencies: no versions of 'swiftterm' match 2.0.0..<3.0.0` | SwiftTerm 最新 tag 是 `v1.99.2`（SPM 识别为 1.99.2），没有 2.x | 改为 `1.99.2` |
| 3 | 依赖解析通过后，`Validate plug-in "SwiftTermBuildInfoPlugin"` 失败 → `BUILD FAILED` (exit 65) | SwiftTerm **1.19+ 引入了 build tool 插件** `SwiftTermBuildInfoPlugin`（依赖 executable `SwiftTermBuildInfoGenerator`），在 Xcode 26 下插件校验失败 | 经逐个版本确认：`v1.16.0` 是**最后一个不含该插件**的版本 → 固定 `exactVersion: "1.16.0"` |
| 4 | XcodeGen 报 `Unknown package requirement` | XcodeGen 的精确版本键是 **`exactVersion`**，不是 `exact` | 改用 `exactVersion` |
| 5 | **当前阻塞**：`clang: error: linker command failed` / `ld: 64-bit mach-o member 'e_ubsec.o' not 8-byte aligned in .../Pods/NMSSH/NMSSH-iOS/Libraries/lib/libcrypto.a` | NMSSH 2.3.1 **内置 2010 年代的预编译 OpenSSL(libcrypto.a)**，其 archive 成员未 8 字节对齐，现代 ld 直接拒绝 | 先试了 `ONLY_ACTIVE_ARCH=YES`（只编 arm64 绕开 x86_64 切片）→ **无效**，arm64 切片同样有问题 |

补充：第 5 步说明 **NMSSH 自带的 vendored 二进制在现代工具链下不可用**；
且它本质是 OpenSSL 1.0.x，对一个 SSH 客户端而言安全性与可维护性都不可接受。

**好消息**：到第 5 步为止，Swift 源码（含 SwiftTerm 桥接、UI、模型）本身已能编译通过，
失败只发生在 NMSSH 这个 C 预编译依赖的链接阶段。

## 5. 当前决策：把传输层从 NMSSH 迁移到 Citadel（纯 Swift）

**目标**：移除 CocoaPods / NMSSH / 预编译 OpenSSL，改用 SwiftPM 的
[Citadel](https://github.com/orlandos-nl/Citadel) 0.12.1（构建在 swift-nio-ssh 之上，纯 Swift，
仅含一个从源码编译的 C target `CCitadelBcrypt`，**无预编译二进制**）。它同时提供 shell/PTY、SFTP
与 `DirectTCPIP` 转发，可完整覆盖现有功能。

### 已核实的 Citadel API（避免重复调研）

```swift
// 连接
let settings = SSHClientSettings(
    host: "example.com",
    authenticationMethod: { .passwordBased(username: "u", password: "p") },
    hostKeyValidator: .acceptAnything()   // 生产应改为 known-hosts 校验
)
let client = try await SSHClient.connect(to: settings)

// 认证方式（SSHAuthenticationMethod）
.passwordBased(username:password:)
.ed25519(username:privateKey:)      // Curve25519.Signing.PrivateKey
.rsa(username:privateKey:)          // Insecure.RSA.PrivateKey
.p256(username:privateKey:)

// 交互式 PTY（终端所用）
try await client.withPTY(SSHChannelRequestEvent.PseudoTerminalRequest(
    wantReply: true, term: "xterm",
    terminalCharacterWidth: 80, terminalRowHeight: 24,
    terminalPixelWidth: 0, terminalPixelHeight: 0,
    terminalModes: .init([.ECHO: 1])
)) { ttyOutput, ttyStdinWriter in /* ... */ }

// SFTP
try await client.withSFTP { sftp in
    let items = try await sftp.listDirectory(atPath: "/tmp")
}   // 或 client.openSFTP()
// SFTPClient: listDirectory / openFile / withFile / createDirectory / remove / rmdir /
//             rename / getAttributes / setAttributes / getRealPath / close / isActive

// 端口转发（本地 -L）
client.createDirectTCPIPChannel(...)   // Sources/Citadel/DirectTCPIP/Client
```

> 依赖注意：Citadel 0.12.1 依赖 swift-nio-ssh 的**分支版** `Wellz26/swift-nio-ssh`（0.3.4..<0.4.0），
> 而非 Apple 官方仓库；引入时按 SwiftPM 传递依赖自动解析即可。

### 需要改动的文件（已 grep 定位）

| 文件 | 改动 |
| --- | --- |
| `Sources/SSHClient/BridgingHeader.h` | 删除（不再需要 NMSSH/libssh2；若无需 ObjC 则同步移除 `SWIFT_OBJC_BRIDGING_HEADER`） |
| `Sources/SSHClient/Core/SSH/NMSSHClient.swift` | 重写为 `CitadelSSHClient.swift`（实现同一 `SSHClient` 协议） |
| `Sources/SSHClient/Core/SSH/SSHConnectionHelper.swift` | 改为返回 Citadel 客户端 |
| `Sources/SSHClient/Core/SFTP/SFTPBrowser.swift` | 改用 Citadel `SFTPClient` |
| `Sources/SSHClient/Core/PortForward/PortForwardManager.swift` + `SSHForwarding.h/.m` | 删除 libssh2 桥接，改用 `createDirectTCPIPChannel` |
| `Sources/SSHClient/Terminal/TerminalSession.swift` | `NMSSHClient()` → 新客户端类 |
| `Sources/SSHClient/Views/PortForwardSetupView.swift` | 引用类型同步替换 |
| `Sources/SSHClient/Views/SettingsView.swift` | 传输层显示文案改为 Citadel |
| `project.yml` | 加 Citadel 包、移除桥接头设置 |
| `Podfile` / `scripts/ci.sh` | 移除 CocoaPods；`xcodebuild` 由 `-workspace ...xcworkspace` 改为 `-project SSHClient.xcodeproj` |

## 6. 下一步

1. 按上表完成 Citadel 迁移（重点是 `withPTY` 与 `TerminalSession` 的数据流接线）。
2. `project.yml` 加入 Citadel，CI 去掉 `pod install`。
3. 推送后读 `ci-summary.txt` 迭代修复，直至 `BUILD SUCCEEDED`。
