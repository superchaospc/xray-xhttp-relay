#!/bin/bash
# 使用实际安装的 Xray 验证最小 XHTTP+REALITY 配置可通过 xray run -test。
# Xray 未安装时静默跳过（exit 0）。
set -euo pipefail

if ! command -v xray &>/dev/null; then
    echo "xray not installed – skip"
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---- 生成 x25519 密钥对（兼容新旧标签） ----
KEY_OUTPUT=$(xray x25519 2>/dev/null)
# 支持 "Private key: ..." 和 "Password: ..." 两种标签
PRIVATE_KEY=$(echo "$KEY_OUTPUT" | grep -iE "private key|password" | head -1 | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEY_OUTPUT" | grep -i "public" | awk '{print $NF}')

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "无法从 xray x25519 输出解析密钥对"
    echo "Key output labels: $(echo "$KEY_OUTPUT" | awk '{print $1, $2}' | head -5)"
    exit 1
fi

UUID=$(python3 -c "import uuid; print(uuid.uuid4())")
SHORT_ID=$(python3 -c "import os; print(os.urandom(8).hex())")

CONFIG_FILE="$TMP_DIR/test_xhttp_reality.json"

# ---- 写入最小 XHTTP+REALITY 配置 ----
PRIVATE_KEY="$PRIVATE_KEY" SHORT_ID="$SHORT_ID" UUID="$UUID" \
python3 - "$CONFIG_FILE" << 'PYEOF'
import json, os, sys

priv = os.environ["PRIVATE_KEY"]
sid  = os.environ["SHORT_ID"]
uid  = os.environ["UUID"]
out  = sys.argv[1]

config = {
    "log": {"loglevel": "warning"},
    "inbounds": [
        {
            "tag": "vless-in-1",
            "listen": "127.0.0.1",
            "port": 12345,
            "protocol": "vless",
            "settings": {
                "clients": [{"id": uid}],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "reality",
                "xhttpSettings": {"path": "/testpath", "mode": "auto"},
                "realitySettings": {
                    "target": "www.cloudflare.com:443",
                    "serverNames": ["www.cloudflare.com"],
                    "privateKey": priv,
                    "shortIds": [sid]
                }
            }
        }
    ],
    "outbounds": [
        {"tag": "direct", "protocol": "freedom"},
        {"tag": "block",  "protocol": "blackhole"}
    ],
    "routing": {
        "rules": [
            {"type": "field", "inboundTag": ["vless-in-1"], "outboundTag": "direct"}
        ]
    }
}
with open(out, "w") as f:
    json.dump(config, f, indent=4)
PYEOF

# ---- 校验配置（不启动服务）----
if xray run -test -config "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "xray real config ok"
else
    echo "xray run -test 失败:"
    xray run -test -config "$CONFIG_FILE" 2>&1 || true
    exit 1
fi
