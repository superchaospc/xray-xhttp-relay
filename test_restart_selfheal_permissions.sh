#!/bin/bash
# 验证 restart_with_rollback 会在“重启前”就把 config.json 与本地落地自签证书
# 一并归一化到 640，使得内容正常但权限坏(如 600 / root:root)的文件仅靠一次重启即
# 自愈，不需要走失败→回滚流程。覆盖“只是重启”就起不来的场景。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 只加载函数定义，避免执行脚本末尾的 preflight/main_menu。
DEFS="$TMP_DIR/xray_defs.sh"
awk '/^preflight_check$/ {exit} {print}' "$ROOT/xray_deploy.sh" > "$DEFS"
# shellcheck disable=SC1090
source "$DEFS"

CONFIG_FILE="$TMP_DIR/config.json"
printf '%s\n' '{"content":"good"}' > "$CONFIG_FILE"
chmod 600 "$CONFIG_FILE"

# 模拟启用了本地 REALITY 落地：证书/私钥存在但权限坏
REALITY_DEST_CERT="$TMP_DIR/reality-dest.crt"
REALITY_DEST_KEY="$TMP_DIR/reality-dest.key"
printf '%s\n' 'CERT' > "$REALITY_DEST_CERT"
printf '%s\n' 'KEY'  > "$REALITY_DEST_KEY"
chmod 600 "$REALITY_DEST_CERT" "$REALITY_DEST_KEY"

detect_xray_service_group() {
    printf '%s\n' "root"
}

file_mode() {
    stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}

RESTART_COUNT_FILE="$TMP_DIR/restart_count"
printf '%s\n' 0 > "$RESTART_COUNT_FILE"
systemctl() {
    case "$1" in
        restart)
            local c; c=$(cat "$RESTART_COUNT_FILE"); c=$((c + 1))
            printf '%s\n' "$c" > "$RESTART_COUNT_FILE"
            return 0
            ;;
        is-active)
            [ "$(file_mode "$CONFIG_FILE")" = "640" ]
            ;;
        *) return 1 ;;
    esac
}

set +e
restart_with_rollback >"$TMP_DIR/out" 2>&1
rc=$?
set -e

[ "$rc" -eq 0 ] || { echo "健康重启应返回 0，实际 $rc"; cat "$TMP_DIR/out"; exit 1; }

count=$(cat "$RESTART_COUNT_FILE")
[ "$count" -eq 1 ] || { echo "期望仅 1 次 restart（不回滚），实际 $count"; exit 1; }

[ "$(file_mode "$CONFIG_FILE")" = "640" ] || { echo "config 权限未自愈为 640"; exit 1; }
grep -q '"content":"good"' "$CONFIG_FILE" || { echo "config 内容被意外改动"; exit 1; }

# 本地落地证书/私钥也应被归一化到 640
[ "$(file_mode "$REALITY_DEST_CERT")" = "640" ] || { echo "落地证书权限未自愈为 640"; exit 1; }
[ "$(file_mode "$REALITY_DEST_KEY")" = "640" ]  || { echo "落地私钥权限未自愈为 640"; exit 1; }

echo "restart selfheal permissions ok"
