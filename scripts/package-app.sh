#!/usr/bin/env bash
set -euo pipefail

# 组装 horae 菜单栏 app 的 .app bundle: 编译 release, 放入资源, 嵌入并逐层签名 Sparkle.framework,
# 最后 ad-hoc 签名外层 + 固定 designated requirement。
# 不开 Hardened Runtime: ad-hoc 路径下它会挡住 Sparkle 加载进 app。

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
BUNDLE="$APP_DIR/Horae.app"
CONTENTS="$BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
BUNDLE_ID="com.user.horae.app"

cd "$APP_DIR"
swift build -c release

rm -rf "$BUNDLE"
mkdir -p "$MACOS" "$RES/icons" "$FRAMEWORKS"
cp "$APP_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$APP_DIR/.build/release/Horae" "$MACOS/Horae"
cp "$APP_DIR"/Icons/*.png "$RES/icons/"
cp "$APP_DIR/AppIcon.icns" "$RES/AppIcon.icns"
cp "$APP_DIR/presets.json" "$RES/presets.json"

# 嵌入 Sparkle.framework: SwiftPM 链接它但不把运行时辅助件(Autoupdate / Updater.app / XPC)放进 .app,
# 所以手动拷入并补标准 rpath, 让可执行在运行时解析到。优先用 universal xcframework 切片。
SPARKLE_FW_SRC="$(find "$APP_DIR/.build/artifacts" -path '*macos-arm64*/Sparkle.framework' -type d 2>/dev/null | head -1)"
[ -z "$SPARKLE_FW_SRC" ] && SPARKLE_FW_SRC="$APP_DIR/.build/release/Sparkle.framework"
if [ -d "$SPARKLE_FW_SRC" ]; then
  cp -R "$SPARKLE_FW_SRC" "$FRAMEWORKS/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/Horae" 2>/dev/null || true
else
  echo "warning: 未找到 Sparkle.framework, 本次构建无自动更新。" >&2
fi

# 逐层签名 Sparkle 内部嵌套代码(framework + Updater.app + Autoupdate + XPC services)。
# 必须 inner-out, 绝不 --deep(会毁掉 XPC 签名)。ad-hoc(-)足够个人分发。
SPARKLE_FW="$FRAMEWORKS/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
  while IFS= read -r -d '' nested; do
    codesign --force --sign - "$nested" >/dev/null
  done < <(find "$SPARKLE_FW" \( -name "*.xpc" -o -name "*.app" \) -print0)
  AUTOUPDATE="$(find "$SPARKLE_FW" -name Autoupdate -type f | head -1)"
  [ -n "$AUTOUPDATE" ] && codesign --force --sign - "$AUTOUPDATE" >/dev/null
  codesign --force --sign - "$SPARKLE_FW" >/dev/null
fi

# 外层 app: ad-hoc + 固定 designated requirement(锁 identifier), 让 Sparkle 的更新签名匹配校验
# 跨重建仍通过, 且 macOS 保留 TCC 授权。不用 --deep: 内部 Sparkle 已逐层签好。
codesign --force --sign - \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$BUNDLE" >/dev/null

echo "Built $BUNDLE"
