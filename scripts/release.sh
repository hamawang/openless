#!/usr/bin/env bash
# 发新版的一条龙脚本。
#
# 用法：
#   ./scripts/release.sh <version> [<build_number>] [<release_notes_file>]
#
# 例：
#   ./scripts/release.sh 1.0.02 A1004 docs/release-notes/1.0.02.md
#   ./scripts/release.sh 1.0.02
#
# 流程：
#   1. 改 build-app.sh 里的 APP_VERSION / BUILD_NUMBER
#   2. 跑 build-app.sh 出 .app
#   3. ditto 打包成 OpenLess-<version>.zip
#   4. sign_update zip → 拿 EdDSA 签名 + 长度
#   5. 在 appcast.xml 里追加新 <item>
#   6. git commit appcast.xml + build-app.sh
#   7. git tag v<version> + push main + push tag
#   8. gh release create + 上传 zip
#
# 依赖：
#   - /tmp/sparkle-tools/bin/sign_update（首次会自动从 Sparkle release 下载）
#   - gh CLI 已登录
#   - Keychain 里有 Sparkle EdDSA 私钥（已生成一次性）

set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: ./scripts/release.sh <version> [<build_number>] [<release_notes_file>]}"
BUILD="${2:-}"
NOTES_FILE="${3:-}"

if [ -z "${BUILD}" ]; then
  # 默认把 build number 设为 version 的简单变形（去掉点）。用户可显式覆盖。
  BUILD="$(echo "${VERSION}" | tr -d '.')"
fi

APP_NAME="OpenLess"
APP_DIR="build/${APP_NAME}.app"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
ZIP_PATH="build/${ZIP_NAME}"
APPCAST="appcast.xml"
SPARKLE_TOOLS_DIR="/tmp/sparkle-tools"
SIGN_UPDATE="${SPARKLE_TOOLS_DIR}/bin/sign_update"
SPARKLE_VERSION="2.9.1"

# 1. 确保 sign_update 工具就位
if [ ! -x "${SIGN_UPDATE}" ]; then
  echo "[release] 下载 Sparkle ${SPARKLE_VERSION} 工具..."
  mkdir -p "${SPARKLE_TOOLS_DIR}"
  (cd "${SPARKLE_TOOLS_DIR}" && \
    gh release download "${SPARKLE_VERSION}" -R sparkle-project/Sparkle \
      -p "Sparkle-${SPARKLE_VERSION}.tar.xz" --skip-existing && \
    tar -xJf "Sparkle-${SPARKLE_VERSION}.tar.xz")
fi

# 2. 改 build-app.sh 里的版本
echo "[release] 写入版本号 ${VERSION} / ${BUILD}"
/usr/bin/sed -i '' "s/^APP_VERSION=.*/APP_VERSION=\"${VERSION}\"/" scripts/build-app.sh
/usr/bin/sed -i '' "s/^BUILD_NUMBER=.*/BUILD_NUMBER=\"${BUILD}\"/" scripts/build-app.sh

# 3. 构建 .app（不重置 TCC，避免本机权限被清掉）
echo "[release] 构建 .app"
RESET_TCC=0 ./scripts/build-app.sh > /dev/null

# 4. 打包 zip
rm -f "${ZIP_PATH}"
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"
ZIP_SIZE=$(/usr/bin/stat -f%z "${ZIP_PATH}")
echo "[release] zip = ${ZIP_PATH} (${ZIP_SIZE} bytes)"

# 5. 用 Keychain 里的 EdDSA 私钥签 zip
SIGN_OUTPUT=$("${SIGN_UPDATE}" "${ZIP_PATH}")
# 输出形如：sparkle:edSignature="xxxx" length="1234567"
EDSIG=$(echo "${SIGN_OUTPUT}" | /usr/bin/sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
[ -n "${EDSIG}" ] || { echo "签名失败，sign_update 输出：${SIGN_OUTPUT}"; exit 1; }
echo "[release] EdDSA 签名 OK"

# 6. 准备 release notes（HTML 片段）
if [ -n "${NOTES_FILE}" ] && [ -f "${NOTES_FILE}" ]; then
  NOTES_HTML="<![CDATA[$(cat "${NOTES_FILE}")]]>"
else
  NOTES_HTML="<![CDATA[<p>OpenLess ${VERSION}</p>]]>"
fi

PUB_DATE=$(LC_ALL=C /bin/date -u +"%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/appergb/openless/releases/download/v${VERSION}/${ZIP_NAME}"

# 7. 在 appcast.xml 的标记行后插入新 <item>
TMP_ITEM=$(/usr/bin/mktemp)
cat > "${TMP_ITEM}" <<EOF

        <item>
            <title>OpenLess ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <description>${NOTES_HTML}</description>
            <enclosure
                url="${DOWNLOAD_URL}"
                length="${ZIP_SIZE}"
                type="application/octet-stream"
                sparkle:edSignature="${EDSIG}" />
        </item>
EOF
# sed 的 r 命令在匹配行后插入文件内容，比 awk -v 处理多行字符串更稳。
/usr/bin/sed -i '' "/<description>OpenLess update feed<\/description>/r ${TMP_ITEM}" "${APPCAST}"
rm -f "${TMP_ITEM}"
echo "[release] appcast.xml 已追加 ${VERSION}"

# 8. git commit + tag + push
git add scripts/build-app.sh "${APPCAST}"
git commit -m "release: v${VERSION} (build ${BUILD})"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

# 9. gh release create + 上传 zip
gh release create "v${VERSION}" "${ZIP_PATH}" \
  --title "OpenLess ${VERSION}" \
  --notes-file "${NOTES_FILE:-/dev/stdin}" <<EOF
OpenLess ${VERSION} (build ${BUILD}).

老用户：app 启动后自动检查更新；首次安装见 README。
EOF

echo
echo "[release] 完成 ✅"
echo "  Tag:     v${VERSION}"
echo "  Release: https://github.com/appergb/openless/releases/tag/v${VERSION}"
echo "  Zip:     ${ZIP_PATH} (${ZIP_SIZE} bytes)"
echo "  Sig:     ${EDSIG}"
