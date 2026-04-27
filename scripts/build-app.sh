#!/usr/bin/env bash
# 把 OpenLess 打包成 .app bundle + ad-hoc codesign
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="OpenLess"
BUNDLE_ID="com.openless.app"
APP_VERSION="0.1.8"
BUILD_NUMBER="9"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BIN_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "[build-app] generate app icon"
swift scripts/generate-app-icon.swift

echo "[build-app] swift build -c release"
swift build -c release --product "${APP_NAME}"

BIN_SRC=".build/release/${APP_NAME}"
[ -f "${BIN_SRC}" ] || { echo "missing ${BIN_SRC}"; exit 1; }

echo "[build-app] assemble bundle at ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${BIN_DIR}" "${RES_DIR}"
cp "${BIN_SRC}" "${BIN_DIR}/${APP_NAME}"
cp "Resources/AppIcon.icns" "${RES_DIR}/AppIcon.icns"
cp "Resources/StatusBar/OpenLessStatusIcon.svg" "${RES_DIR}/OpenLessStatusIcon.svg"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OpenLess 需要麦克风权限以录制您的语音并转写为文字。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>OpenLess 需要权限以将转写后的文字插入到您当前光标所在的输入框。</string>
</dict>
</plist>
EOF

echo "[build-app] ad-hoc code sign"
codesign --force --deep --sign - "${APP_DIR}"

echo "[build-app] kill old app"
killall "${APP_NAME}" 2>/dev/null || true
if [[ "${RESET_TCC:-1}" != "0" ]]; then
  echo "[build-app] reset TCC approvals"
  tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true
  tccutil reset Microphone "${BUNDLE_ID}" 2>/dev/null || true
  tccutil reset AppleEvents "${BUNDLE_ID}" 2>/dev/null || true
  tccutil reset ListenEvent "${BUNDLE_ID}" 2>/dev/null || true
else
  echo "[build-app] keep existing TCC approvals"
fi

echo "[build-app] done: ${APP_DIR}"
echo
echo "下一步："
echo "  1. open ${APP_DIR}     # 双击启动；默认已重置权限，会重新弹辅助功能 + 麦克风权限"
echo "  2. 系统设置 → 隐私与安全 → 辅助功能 / 麦克风 → 勾选 OpenLess"
echo "  3. 屏幕右上角菜单栏 OpenLess 图标 → 退出 OpenLess（必须先退出再重启）"
echo "  4. 再次 open ${APP_DIR}"
echo "  5. 从 Dock 或菜单栏打开 OpenLess 首页；在「设置」里填火山 APP ID、Access Token、Resource ID，以及 Ark API Key（保存到 ~/.openless/credentials.json，0600）"
echo "  6. 实时日志（另开终端）: tail -f ~/Library/Logs/OpenLess/OpenLess.log"
echo "  7. 按右 Option（或 Fn）开始录音；再按一次结束；语音文字会插入当前输入框"
