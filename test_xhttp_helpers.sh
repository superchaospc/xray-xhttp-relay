#!/bin/bash
# 验证 XHTTP 传输助手：模式校验、路径生成/归一化、链接构建，以及无遗留字段。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DEFS="$TMP_DIR/xray_defs.sh"
awk '/^preflight_check$/ {exit} {print}' "$ROOT/xray_deploy.sh" > "$DEFS"
# shellcheck disable=SC1090
source "$DEFS"

# ---- 模式校验 ----
validate_xhttp_mode auto
validate_xhttp_mode stream-one
validate_xhttp_mode stream-up
validate_xhttp_mode packet-up
if validate_xhttp_mode invalid-mode 2>/dev/null; then
    echo "invalid-mode 不应通过校验"; exit 1
fi

# ---- 路径生成 ----
path1=$(generate_xhttp_path)
path2=$(generate_xhttp_path)
if ! [[ "$path1" =~ ^/[A-Za-z0-9_-]{16,64}$ ]]; then
    echo "路径格式不合法: $path1"; exit 1
fi
if [ "$path1" = "$path2" ]; then
    echo "连续生成的两个路径相同: $path1"; exit 1
fi

# ---- 路径归一化 ----
norm=$(normalize_xhttp_path "alpha/beta")
if [ "$norm" != "/alpha/beta" ]; then
    echo "归一化结果不符: $norm"; exit 1
fi
if normalize_xhttp_path "/bad path" 2>/dev/null; then
    echo "含空格的路径不应通过归一化"; exit 1
fi

# ---- 链接构建 ----
link=$(build_vless_link "uuid" "2001:db8::1" 443 "example.com" chrome pk sid "/a/b?c" auto "Node Name")
if [[ "$link" != *"type=xhttp"* ]]; then
    echo "链接缺少 type=xhttp: $link"; exit 1
fi
if [[ "$link" != *"path=%2Fa%2Fb%3Fc"* ]]; then
    echo "路径未正确编码: $link"; exit 1
fi
if [[ "$link" != *"mode=auto"* ]]; then
    echo "链接缺少 mode=auto: $link"; exit 1
fi
if [[ "$link" != *"#Node%20Name" ]]; then
    echo "链接 fragment 编码错误: $link"; exit 1
fi
if [[ "$link" == *"flow="* ]]; then
    echo "链接不应包含 flow=: $link"; exit 1
fi
# IPv6 地址应被方括号包裹
if [[ "$link" != *"@[2001:db8::1]:"* ]]; then
    echo "IPv6 地址未用方括号包裹: $link"; exit 1
fi

# ---- 遗留字段检测 ----
if grep -nE 'type=tcp|xtls-rprx-vision|"network"[[:space:]]*:[[:space:]]*"tcp"' "$ROOT/xray_deploy.sh" \
    | grep -vE '^[0-9]+:[[:space:]]*#'; then
    echo "xray_deploy.sh 中存在遗留 VLESS TCP/Vision 字段"
    exit 1
fi

echo "xhttp helpers ok"
