#!/usr/bin/env sh
# pack.sh — 把 volcengine-rds-mysql Skill 打成可发布的 zip / tar.gz
#
# 产物：dist/volcengine-rds-mysql-v<VERSION>.{zip,tar.gz} 及 .sha256
# 版本源：volcengine-rds-mysql/VERSION（回退 git describe）
#
# 设计要点：
#   - 只打 skill 子目录，绝不卷入 AGENTS.md / .trae / volcengine-cli 等内部物
#   - staging + 排除清单双保险；打包后断言包内无敏感 / 多余文件
#   - 显式修正 verds 可执行位，防跨平台丢权限

set -eu

# 某些终端（如 Trae 的 safe_rm）会把 rm 包装成 shell 函数并可能干扰脚本；
# 清除继承的函数包装，删除统一走真实二进制。
unset -f rm cp mv 2>/dev/null || true
if [ -x /bin/rm ]; then RM=/bin/rm; else RM=rm; fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="volcengine-rds-mysql"
SKILL_DIR="$ROOT/$NAME"
DIST="$ROOT/dist"

log() { printf '%s\n' "$*" >&2; }
die() { log "[pack] $*"; exit 1; }

[ -d "$SKILL_DIR" ] || die "找不到 skill 目录: $SKILL_DIR"

# 1. 版本号：VERSION 文件优先，回退 git tag
VERSION="$(cat "$SKILL_DIR/VERSION" 2>/dev/null | tr -d ' \t\r\n' || true)"
if [ -z "$VERSION" ]; then
  VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
fi
[ -n "$VERSION" ] || die "无法确定版本号（缺 VERSION 文件且无 git tag）"

# 2. 必需文件校验（缺一即失败）
for f in SKILL.md README.md LICENSE CHANGELOG.md VERSION scripts/verds references/actions.md; do
  [ -e "$SKILL_DIR/$f" ] || die "缺少必需文件: $f"
done

# 3. 干净 staging（带排除清单）
WORK="$(mktemp -d)"
trap '$RM -rf "$WORK"' EXIT INT TERM
STAGE="$WORK/$NAME"
mkdir -p "$STAGE"

if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude '.idea/' --exclude '.vscode/' \
    --exclude '.DS_Store' --exclude '._*' \
    --exclude '.git/' --exclude '.gitignore' \
    --exclude '.cache/' --exclude 'volcengine-rds-skill/' \
    --exclude 've' --exclude '*.sha256' \
    --exclude 'dist/' --exclude '*.zip' --exclude '*.tar.gz' \
    "$SKILL_DIR/" "$STAGE/"
else
  # 无 rsync 的回退：cp 后手动清理排除项
  cp -R "$SKILL_DIR/" "$STAGE/"
  $RM -rf "$STAGE/.idea" "$STAGE/.vscode" "$STAGE/.cache" \
         "$STAGE/volcengine-rds-skill" "$STAGE/dist" "$STAGE/.git" "$STAGE/.gitignore"
  find "$STAGE" \( -name '.DS_Store' -o -name '._*' -o -name '*.zip' \
         -o -name '*.tar.gz' -o -name '*.sha256' -o -name 've' \) -delete 2>/dev/null || true
fi

# 4. 显式修正可执行位
chmod 0755 "$STAGE/scripts/verds"

# 5. 打包（顶层带 skill 目录名）
mkdir -p "$DIST"
ZIP="$DIST/$NAME-v$VERSION.zip"
TGZ="$DIST/$NAME-v$VERSION.tar.gz"
$RM -f "$ZIP" "$TGZ"

( cd "$WORK" && zip -rX "$ZIP" "$NAME" >/dev/null ) || die "zip 打包失败"
( cd "$WORK" && COPYFILE_DISABLE=1 tar --no-xattrs -czf "$TGZ" "$NAME" 2>/dev/null \
  || tar -czf "$TGZ" "$NAME" ) || die "tar 打包失败"

# 6. 校验和
( cd "$DIST" && { shasum -a 256 "$(basename "$ZIP")" "$(basename "$TGZ")" \
    2>/dev/null || sha256sum "$(basename "$ZIP")" "$(basename "$TGZ")"; } \
    > "$NAME-v$VERSION.sha256" )

# 7. 断言产物干净（无敏感 / 多余文件）
BADHIT="$(unzip -Z1 "$ZIP" | grep -Ei '\.idea/|\.DS_Store|(^|/)\._|\.git/|AGENTS\.md|volcengine-cli/' || true)"
[ -z "$BADHIT" ] || die "产物包含不应发布的文件：
$BADHIT"

log "[pack] 完成："
log "  $ZIP"
log "  $TGZ"
log "  $DIST/$NAME-v$VERSION.sha256"
log ""
log "[pack] 包内清单："
unzip -Z1 "$ZIP" | sed 's/^/    /' >&2
