#!/usr/bin/env bash
# 云端/本地统一的 iOS 编译脚本（macOS）。
# 流程：xcodegen 生成工程 → pod install 拉取 NMSSH/libssh2 → 针对 iOS 模拟器免签名编译。
# CI 工作流(.github/workflows/ci.yml) 直接调用本脚本，本地 Mac 也可 `bash scripts/ci.sh` 复现。
set -euo pipefail

echo "==> Xcode / Swift 版本"
xcodebuild -version
swift --version

echo "==> 安装工具链 xcodegen + cocoapods (brew)"
brew install xcodegen cocoapods

echo "==> XcodeGen 生成工程"
xcodegen generate

echo "==> pod install 拉取 NMSSH + libssh2"
pod install --repo-update

echo "==> 可用 schemes"
xcodebuild -workspace SSHClient.xcworkspace -list

echo "==> 针对 iOS 模拟器编译（免签名）"
xcodebuild build \
  -workspace SSHClient.xcworkspace \
  -scheme SSHClient \
  -sdk iphonesimulator \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  -destination 'generic/platform=iOS Simulator' \
  ONLY_ACTIVE_ARCH=NO
