#!/usr/bin/env bash
#
# BearFuel 一键发布流水线
#
# 用法:
#   bash scripts/release.sh [patch|minor|major|none]
#   可用环境变量 FLUTTER_BIN 指定 flutter 可执行文件路径。
#
# 流程:
#   1. 升版      提升 pubspec.yaml 版本号与 build 号, 确保 CHANGELOG.md 有对应条目
#   2. 本地构建  flutter analyze + test, 构建分架构 Android APK
#                (检测到发布密钥时自动签名; macOS 上同时产出未签名 iOS IPA;
#                 Windows 等其他系统上 iOS 交由远端构建)
#   3. 远端构建  提交 pubspec/CHANGELOG → 打 vTag → 推送,
#                GitHub Actions 自动构建 签名 APK×3 + 未签名 IPA 并发布 Release
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUMP="${1:-patch}"

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
die() { printf '\n\033[1;31m[发布中止] %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- 0. 前置检查 ----------
command -v "$FLUTTER_BIN" >/dev/null 2>&1 ||
  die "未找到 flutter 命令, 可用 FLUTTER_BIN=/path/to/flutter bash scripts/release.sh 重试"
[ -z "$(git status --porcelain)" ] ||
  die "工作区有未提交改动, 请先提交全部工作后再发布"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
say "前置检查通过 (分支: $CURRENT_BRANCH)"

# ---------- 1. 升版 ----------
CURRENT_VERSION="$(awk '/^version:/{print $2}' pubspec.yaml)"
VERSION_NAME="${CURRENT_VERSION%%+*}"
BUILD_NUMBER="${CURRENT_VERSION##*+}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION_NAME"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  none) : ;;
  *) die "未知升版类型: $BUMP (可选 patch|minor|major|none)" ;;
esac

NEW_VERSION_NAME="${MAJOR}.${MINOR}.${PATCH}"
NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
NEW_VERSION="${NEW_VERSION_NAME}+${NEW_BUILD_NUMBER}"
TAG="v${NEW_VERSION_NAME}"

if [ "$NEW_VERSION_NAME" = "$VERSION_NAME" ]; then
  say "跳过升版, 沿用当前版本 ${CURRENT_VERSION}"
else
  say "升版 ${CURRENT_VERSION} → ${NEW_VERSION}"
  sed -i.bak "s/^version: .*/version: ${NEW_VERSION}/" pubspec.yaml
  rm -f pubspec.yaml.bak
fi

# CHANGELOG 缺少本版条目时生成占位, 避免发布无更新说明
if ! grep -q "## \[${NEW_VERSION_NAME}\]" CHANGELOG.md; then
  TODAY="$(date +%F)"
  awk -v entry="## [${NEW_VERSION_NAME}] - ${TODAY}" '
    /^## \[/ && !done { print ""; print entry; print ""; print "- 请在此补充本版更新说明。"; done=1 }
    { print }
  ' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
  info "已在 CHANGELOG.md 生成 ${NEW_VERSION_NAME} 占位条目"
fi

# ---------- 2. 本地验证与构建 ----------
say "flutter analyze"
"$FLUTTER_BIN" analyze

say "flutter test"
"$FLUTTER_BIN" test

# 签名方式检测: android/key.properties 或 BEARFUEL_KEY_* 环境变量
SIGNED="调试签名"
if [ -f android/key.properties ] ||
  { [ -n "${BEARFUEL_KEYSTORE_PATH:-}" ] && [ -n "${BEARFUEL_KEY_ALIAS:-}" ] &&
    [ -n "${BEARFUEL_KEY_PASSWORD:-}" ] && [ -n "${BEARFUEL_STORE_PASSWORD:-}" ]; }; then
  SIGNED="发布密钥签名"
fi

say "本地构建分架构 Android APK (${SIGNED})"
"$FLUTTER_BIN" build apk --release --split-per-abi \
  -Pbearfuel.targetAbis=armeabi-v7a,arm64-v8a,x86_64
ls -lh build/app/outputs/flutter-apk/*-release.apk || true

OS_NAME="$(uname -s)"
if [ "$OS_NAME" = "Darwin" ]; then
  say "本地构建未签名 iOS IPA"
  "$FLUTTER_BIN" build ios --release --no-codesign
  rm -rf Payload
  mkdir Payload
  cp -R build/ios/iphoneos/Runner.app Payload/
  rm -f "BearFuel-${NEW_VERSION_NAME}-ios-unsigned.ipa"
  zip -qry "BearFuel-${NEW_VERSION_NAME}-ios-unsigned.ipa" Payload
  rm -rf Payload
  info "IPA 产物: BearFuel-${NEW_VERSION_NAME}-ios-unsigned.ipa"
else
  say "当前系统 (${OS_NAME}) 无法本地构建 iOS (需要 macOS + Xcode)"
  info "iOS IPA 将由远端 GitHub Actions 构建并附带在 Release 中"
fi

# ---------- 3. 远端构建 ----------
say "提交版本并推送, 触发远端构建"
git add pubspec.yaml CHANGELOG.md
if git diff --cached --quiet; then
  info "版本与更新日志无新改动, 跳过发布提交"
else
  git commit -m "release: prepare BearFuel ${NEW_VERSION_NAME}"
fi
git tag "$TAG" 2>/dev/null || die "标签 $TAG 已存在"
git push origin "$CURRENT_BRANCH"
git push origin "$TAG"

say "发布流水线执行完成"
echo "  本地产物 : build/app/outputs/flutter-apk/app-{armeabi-v7a,arm64-v8a,x86_64}-release.apk"
echo "  远端进度 : https://github.com/1378944437/BearFuel/actions"
echo "  发布页面 : https://github.com/1378944437/BearFuel/releases/tag/$TAG"
echo "  远端产物 : 签名 Android APK ×3 (armeabi-v7a/arm64-v8a/x86_64) + 未签名 iOS IPA (含 SHA-256)"
