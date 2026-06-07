#!/bin/bash
# 验证回滚后会重新归一化 config.json 权限，且 systemctl restart 非零不会绕过回滚。
# 同时验证回滚恢复的 XHTTP 配置（含 path/mode）与备份字节完全一致。
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

# 使用一个包含 XHTTP xhttpSettings 的真实结构作为备份内容
BACKUP_CONTENT='{"inbounds":[{"tag":"vless-in-1","port":443,"_remark":"LA-Direct","streamSettings":{"network":"xhttp","xhttpSettings":{"path":"/fixedSecretPath","mode":"stream-one"}}}]}'

printf '%s\n' '{"broken":true}' > "$CONFIG_FILE"
printf '%s\n' "$BACKUP_CONTENT" > "${CONFIG_FILE}.bak.20260513-120000"
chmod 600 "${CONFIG_FILE}.bak.20260513-120000"

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
            local restart_count
            restart_count=$(cat "$RESTART_COUNT_FILE")
            restart_count=$((restart_count + 1))
            printf '%s\n' "$restart_count" > "$RESTART_COUNT_FILE"
            if [ "$restart_count" -eq 1 ]; then
                return 1
            fi
            [ "$(file_mode "$CONFIG_FILE")" = "640" ]
            ;;
        is-active)
            local restart_count
            restart_count=$(cat "$RESTART_COUNT_FILE")
            [ "$restart_count" -ge 2 ] && [ "$(file_mode "$CONFIG_FILE")" = "640" ]
            ;;
        *)
            return 1
            ;;
    esac
}

OUT_FILE="$TMP_DIR/out"
set +e
restart_with_rollback >"$OUT_FILE" 2>&1
rc=$?
set -e
out=$(cat "$OUT_FILE")

if [ "$rc" -eq 0 ]; then
    echo "回滚成功恢复服务时，业务返回值仍应为非零"
    printf '%s\n' "$out"
    exit 1
fi

restart_count=$(cat "$RESTART_COUNT_FILE")
if [ "$restart_count" -ne 2 ]; then
    echo "期望执行两次 restart，实际 $restart_count"
    printf '%s\n' "$out"
    exit 1
fi

# 权限恢复
[ "$(file_mode "$CONFIG_FILE")" = "640" ]

# 验证内容字节完全一致（XHTTP path/mode 保留）
restored=$(cat "$CONFIG_FILE")
if [ "$restored" != "$BACKUP_CONTENT" ]; then
    echo "回滚内容与备份不一致"
    echo "expected: $BACKUP_CONTENT"
    echo "got:      $restored"
    exit 1
fi

# 验证恢复后 XHTTP 路径和模式完整
python3 - "$CONFIG_FILE" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
inb = cfg["inbounds"][0]
xhttp = inb.get("streamSettings", {}).get("xhttpSettings", {})
assert xhttp.get("path") == "/fixedSecretPath", f"path lost after rollback: {xhttp.get('path')}"
assert xhttp.get("mode") == "stream-one", f"mode lost after rollback: {xhttp.get('mode')}"
print("xhttp config restored byte-for-byte ok")
PY

echo "restart rollback permissions ok"
