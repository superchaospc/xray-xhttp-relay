#!/bin/bash
# get_ip 在 IPv4 获取失败时应自动回退到 IPv6，而不是直接要求手动输入。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HELPER="$TMP_DIR/get_ip.sh"
awk '
    /is_valid_ip_literal\(\) \{/ {inside=1}
    /get_ip\(\) \{/ {inside=1}
    inside {print}
    inside && /^}/ {inside=0}
' "$ROOT/xray_deploy.sh" > "$HELPER"

# 伪 curl: IPv4 (-s4) 全部失败，IPv6 (-s6) 返回合法地址。
cat > "$TMP_DIR/curl" << 'EOF'
#!/bin/sh
for arg in "$@"; do
    case "$arg" in
        -s4) exit 1 ;;
        -s6) printf '%s\n' '2001:db8::1'; exit 0 ;;
    esac
done
exit 1
EOF
chmod +x "$TMP_DIR/curl"

set +e
out="$(
    PATH="$TMP_DIR:$PATH" \
    IP_CACHE_FILE="$TMP_DIR/ip.cache" \
    IP_CACHE_TTL=3600 \
    RED="" YELLOW="" NC="" \
    bash -c "source '$HELPER'; get_ip" </dev/null 2>/dev/null
)"
rc=$?
set -e

if [ "$rc" -ne 0 ]; then
    echo "get_ip 在 IPv4 失败、IPv6 可用时应返回成功，实际 rc=$rc"
    exit 1
fi

if [ "$out" != "2001:db8::1" ]; then
    echo "get_ip 未自动回退到 IPv6，期望 '2001:db8::1'，实际 '$out'"
    exit 1
fi

if [ "$(cat "$TMP_DIR/ip.cache" 2>/dev/null)" != "2001:db8::1" ]; then
    echo "get_ip 未缓存回退得到的 IPv6 地址"
    exit 1
fi

echo "get ip ipv6 fallback ok"
