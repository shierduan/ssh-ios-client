#!/usr/bin/env bash
# 云端/本地统一的 iOS 编译脚本（macOS）。
# 流程：xcodegen 生成工程 → pod install 拉取 NMSSH/libssh2 → 针对 iOS 模拟器免签名编译。
# 全部输出会经工作流 tee 到 build.log，便于排查（首次编译很可能暴露 API/类型错误）。
set -uo pipefail

echo "==> [$(date -u)] Xcode / Swift 版本"
xcodebuild -version
swift --version || true

echo "==> 确保工具链（缺则安装）"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
command -v pod       >/dev/null 2>&1 || brew install cocoapods

echo "==> XcodeGen 生成工程"
xcodegen generate

echo "==> pod install 拉取 NMSSH + libssh2"
pod install --repo-update

echo "==> 可用 schemes"
xcodebuild -workspace SSHClient.xcworkspace -list

echo "==> 针对 iOS 模拟器编译（免签名）"
# 只构建 arm64（Apple Silicon active arch）：
# NMSSH 2.3.1 内置的预编译 OpenSSL(libcrypto.a) 的 x86_64 切片含未 8 字节对齐的成员，
# 现代 ld 会直接报 "not 8-byte aligned" 而链接失败；仅编 arm64 可绕开该坏切片。
xcodebuild build \
  -workspace SSHClient.xcworkspace \
  -scheme SSHClient \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  -destination 'generic/platform=iOS Simulator' \
  ONLY_ACTIVE_ARCH=YES
BUILD_STATUS=$?

echo "==> BUILD EXIT CODE: $BUILD_STATUS"
exit $BUILD_STATUS
