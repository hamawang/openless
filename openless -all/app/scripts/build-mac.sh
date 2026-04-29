#!/usr/bin/env bash
# 一键构建 macOS 正式版 .app（ad-hoc 签名）。
#
# Tauri 的 bundle 输出不支持自定义 Info.plist 的 LSUIElement / NSXxxUsageDescription，
# 这里在 `tauri build` 之后用 PlistBuddy 注入，再重新 ad-hoc 签名。
#
# 用法：在 app/ 目录下执行
#     ./scripts/build-mac.sh           # 构建 + 注入 + 签名 + 装到 /Applications
#     INSTALL=0 ./scripts/build-mac.sh # 只构建，不装

set -euo pipefail

cd "$(dirname "$0")/.."

APP="src-tauri/target/release/bundle/macos/OpenLess.app"
INFO="$APP/Contents/Info.plist"
PB=/usr/libexec/PlistBuddy
INSTALL="${INSTALL:-1}"

echo "▶ tauri build"
npm run tauri build

echo "▶ 注入 Info.plist keys"
inject() {
  local key="$1" type="$2" value="$3"
  $PB -c "Delete :$key" "$INFO" 2>/dev/null || true
  $PB -c "Add :$key $type $value" "$INFO"
}
# 菜单栏 app（不在 Dock 显示，与 Swift LSUIElement = true 一致）
inject LSUIElement bool true
inject NSMicrophoneUsageDescription string "OpenLess需要麦克风权限来听写你的语音。"
inject NSAccessibilityUsageDescription string "OpenLess需要辅助功能权限来监听全局快捷键并把识别结果粘贴到当前光标位置。"
inject NSAppleEventsUsageDescription string "OpenLess需要发送按键事件，把识别结果粘贴到当前光标位置。"

echo "▶ ad-hoc 签名（修改 Info.plist 后必须重新签名，否则启动崩 codesign 校验）"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2

if [ "$INSTALL" = "1" ]; then
  echo "▶ 装到 /Applications"
  pkill -f "OpenLess.app/Contents/MacOS/openless" 2>/dev/null || true
  sleep 1
  # 每次重装前重置 TCC：ad-hoc 签名 hash 每次构建都会变，旧授权立即失效，
  # 不重置就会出现"系统设置里看着已勾选实际不生效"。
  tccutil reset Accessibility com.openless.app 2>/dev/null || true
  tccutil reset Microphone com.openless.app 2>/dev/null || true
  rm -rf /Applications/OpenLess.app
  cp -R "$APP" /Applications/
  xattr -dr com.apple.quarantine /Applications/OpenLess.app 2>/dev/null || true
  echo "✓ 装好了：/Applications/OpenLess.app"
  echo "  打开方式：open /Applications/OpenLess.app"
fi
