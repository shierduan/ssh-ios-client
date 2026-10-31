#!/bin/bash
# SSHClient 一键初始化:生成 Xcode 工程并安装依赖
set -e

echo "==> 检查工具..."
command -v xcodegen >/dev/null 2>&1 || { echo "请先安装 xcodegen: brew install xcodegen"; exit 1; }
command -v pod >/dev/null 2>&1 || { echo "请先安装 cocoapods: sudo gem install cocoapods"; exit 1; }

echo "==> 用 XcodeGen 生成 SSHClient.xcodeproj ..."
xcodegen generate

echo "==> 用 CocoaPods 安装 NMSSH ..."
pod install

echo "==> 完成。请打开 SSHClient.xcworkspace"
open SSHClient.xcworkspace
