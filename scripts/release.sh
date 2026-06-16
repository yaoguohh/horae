#!/usr/bin/env bash
set -euo pipefail

# 本地准备一个 Horae 发布(不做任何对外动作): 校验 → 质量门禁 → bump 版本 → 提交 → 打 tag →
# 构建 DMG → 生成并 EdDSA 签名 appcast → 生成 release notes 草稿。
# 对外 push / gh release 由 scripts/publish.sh 单独执行。用法: make release VERSION=x.y.z

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PLIST="$ROOT_DIR/app/Info.plist"
DIST="$ROOT_DIR/dist"
DMG="$DIST/Horae.dmg"
APPCAST="$DIST/appcast.xml"
NOTES="$DIST/RELEASE_NOTES.md"
REPO_URL="https://github.com/yaoguohh/horae"

# 1) 校验: 版本格式 / 干净工作树 / 在 main / tag 不重复
[ -n "$VERSION" ] || { echo "用法: make release VERSION=x.y.z" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION 需形如 1.2.3, 收到: $VERSION" >&2; exit 1; }
TAG="v$VERSION"
[ -z "$(git status --porcelain)" ] || { echo "工作树不干净, 先提交或清理再发布" >&2; exit 1; }
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "请在 main 分支发布" >&2; exit 1; }
! git rev-parse "$TAG" >/dev/null 2>&1 || { echo "tag $TAG 已存在" >&2; exit 1; }

# 2) 质量门禁: 不发布坏代码(make dmg 也会 swift build, 此处补 Go vet/lint/test)
make check

# 3) bump 版本: 短版本=VERSION, build 自动 +1
CUR_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
NEW_BUILD=$((CUR_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"
echo "版本 -> $VERSION (build $NEW_BUILD)"

# 4) 发布提交 + annotated tag(沿用既有 chore(release) 格式)
git add "$PLIST"
git commit -m "chore(release): $TAG"
git tag -a "$TAG" -m "$TAG"

# 5) DMG(内部会 make app → app/build.noindex/Horae.app → dist/Horae.dmg)
make dmg

# 6) appcast: dist 清到只剩 DMG(避免并入旧条目), 生成单条目并签名。
#    EdDSA 私钥自动读 Keychain(与 Info.plist 的 SUPublicEDKey 配对), 可能弹授权。
GENERATE_APPCAST="$(find "$ROOT_DIR/app/.build" -path '*sparkle*/bin/generate_appcast' -type f 2>/dev/null | head -1)"
[ -n "$GENERATE_APPCAST" ] || { echo "找不到 generate_appcast(make dmg 应已让 SwiftPM 解析出 Sparkle 工具)" >&2; exit 1; }
find "$DIST" -maxdepth 1 -type f ! -name 'Horae.dmg' -delete
"$GENERATE_APPCAST" --download-url-prefix "$REPO_URL/releases/download/$TAG/" --maximum-versions 1 "$DIST"

# 7) release notes 草稿: 上个 tag..本次 的提交主题, 供编辑后给 publish 用
PREV_TAG="$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null || true)"
RANGE="${PREV_TAG:+$PREV_TAG..}$TAG"
{
  echo "## Horae $TAG"
  echo
  git log --no-merges --pretty='- %s' "$RANGE"
} > "$NOTES"

echo
echo "本地准备完成:"
echo "  提交 $(git rev-parse --short HEAD) + tag $TAG"
echo "  $DMG"
echo "  $APPCAST (已签名)"
echo "  $NOTES (请编辑后再发布)"
echo "下一步: 编辑 $NOTES, 然后  make publish VERSION=$VERSION"
