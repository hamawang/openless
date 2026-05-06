#!/usr/bin/env bash
# 同步更新 OpenLess 三处版本号 + Cargo.lock。
# 用法：
#     ./scripts/bump-version.sh 1.2.21
#
# 改的位置（CLAUDE.md 强调必须三处一起改）：
#   - openless-all/app/package.json                "version": "X.Y.Z"
#   - openless-all/app/src-tauri/tauri.conf.json   "version": "X.Y.Z"
#   - openless-all/app/src-tauri/Cargo.toml        version = "X.Y.Z"
#   - openless-all/app/src-tauri/Cargo.lock        通过 cargo update -p openless 同步
#
# CI 的 cross-platform 任务最后一步会校验三个文件版本号一致；漏改一处直接 fail。

set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "用法: $0 <new-version>" >&2
  echo "例:   $0 1.2.21" >&2
  exit 1
fi

NEW="$1"

if ! [[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "错误：版本号必须是 X.Y.Z 数字格式 (拿到 '$NEW')" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/openless-all/app"

PKG_JSON="$APP/package.json"
TAURI_CONF="$APP/src-tauri/tauri.conf.json"
CARGO_TOML="$APP/src-tauri/Cargo.toml"

for f in "$PKG_JSON" "$TAURI_CONF" "$CARGO_TOML"; do
  if [ ! -f "$f" ]; then
    echo "错误：找不到 $f" >&2
    exit 1
  fi
done

# macOS sed 跟 GNU sed 行为不同（-i 后缀必填空字符串）。统一用 -i.bak 然后 rm。
update_json_version() {
  local file="$1"
  sed -E -i.bak \
    "s/\"version\":[[:space:]]*\"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$NEW\"/" \
    "$file"
  rm "$file.bak"
}

update_cargo_toml_version() {
  local file="$1"
  # 仅匹配文件顶层 [package] 段下的 version = "X.Y.Z"，避免误改 dependencies 里的版本。
  # OpenLess 项目 Cargo.toml 第一个出现的 version = 一定是 [package] 自己的。
  sed -E -i.bak \
    "0,/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"$/s//version = \"$NEW\"/" \
    "$file"
  rm "$file.bak"
}

echo "▶ 升 package.json → $NEW"
update_json_version "$PKG_JSON"

echo "▶ 升 tauri.conf.json → $NEW"
update_json_version "$TAURI_CONF"

echo "▶ 升 Cargo.toml → $NEW"
update_cargo_toml_version "$CARGO_TOML"

echo "▶ 同步 Cargo.lock"
( cd "$APP/src-tauri" && cargo update -p openless 2>&1 | grep -E 'Updating|Locking|^error' || true )

echo
echo "===== 验证三处版本一致 ====="
PKG=$(node -p "require('$PKG_JSON').version")
TAU=$(node -p "require('$TAURI_CONF').version")
CRG=$(grep -E '^version = ' "$CARGO_TOML" | head -1 | sed -E 's/^version = "(.+)"$/\1/')

printf '%-20s %s\n' 'package.json:' "$PKG"
printf '%-20s %s\n' 'tauri.conf.json:' "$TAU"
printf '%-20s %s\n' 'Cargo.toml:' "$CRG"

if [ "$PKG" != "$NEW" ] || [ "$TAU" != "$NEW" ] || [ "$CRG" != "$NEW" ]; then
  echo "::error::三处版本号未对齐 — 请检查 sed 是否成功" >&2
  exit 1
fi

echo
echo "✓ 三处版本号一致：$NEW"
echo
echo "下一步建议："
echo "  git diff --stat $PKG_JSON $TAURI_CONF $CARGO_TOML \"$APP/src-tauri/Cargo.lock\""
echo "  git add $PKG_JSON $TAURI_CONF $CARGO_TOML \"$APP/src-tauri/Cargo.lock\""
echo "  git commit -m 'chore(release): $NEW'"
echo "  git push"
echo "  git tag v$NEW-tauri && git push origin v$NEW-tauri"
