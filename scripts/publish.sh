#!/usr/bin/env bash
set -euo pipefail

# 对外发布(上线): push main + tag, 建 GitHub release 并上传 DMG + appcast。
# 前置: 已 make release VERSION=x.y.z 且编辑好 dist/RELEASE_NOTES.md。用法: make publish VERSION=x.y.z
# 这是会让所有 Sparkle 客户端收到更新的不可逆动作, 故与本地准备分开、需显式触发。

VERSION="${1:-}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

[ -n "$VERSION" ] || { echo "用法: make publish VERSION=x.y.z" >&2; exit 1; }
TAG="v$VERSION"
DMG="$ROOT_DIR/dist/Horae.dmg"
APPCAST="$ROOT_DIR/dist/appcast.xml"
NOTES="$ROOT_DIR/dist/RELEASE_NOTES.md"

# 校验本地产物就绪
git rev-parse "$TAG" >/dev/null 2>&1 || { echo "本地无 tag $TAG, 先 make release VERSION=$VERSION" >&2; exit 1; }
for f in "$DMG" "$APPCAST" "$NOTES"; do
  [ -f "$f" ] || { echo "缺 $f, 先 make release VERSION=$VERSION" >&2; exit 1; }
done
! gh release view "$TAG" >/dev/null 2>&1 || { echo "release $TAG 已存在" >&2; exit 1; }

# 对外上线
git push origin main
git push origin "$TAG"
gh release create "$TAG" "$DMG" "$APPCAST" --title "Horae $TAG" --notes-file "$NOTES"

echo "已发布: $(gh release view "$TAG" --json url --jq .url 2>/dev/null || echo "$TAG")"
