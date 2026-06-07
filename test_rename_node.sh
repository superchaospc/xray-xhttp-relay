#!/bin/bash
# 验证节点名称可写回 _remark，并能覆盖 INFO_FILE 中的旧名称刷新订阅链接。
# 同时验证改名后生成的链接保留了原 inbound 的 XHTTP path 和 mode。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_FILE="$TMP_DIR/config.json"
INFO_FILE="$TMP_DIR/xray_nodes_info.txt"
SUB_FILE="$TMP_DIR/xray_subscription.txt"
RENAME_PY="$TMP_DIR/rename_node_update.py"
REFRESH_PY="$TMP_DIR/refresh_info.py"
FORMAT_HELPER="$TMP_DIR/format_vless_host.py"

awk '
    /rename_node\(\) \{/ {fn=1; next}
    fn && /NEW_CONFIG_FILE="\$NEW_CONFIG" IDX="\$IDX" NEW_NAME="\$SAFE_NAME" python3 << '\''PYEOF'\''/ {inside=1; next}
    inside && /^PYEOF$/ {exit}
    inside {print}
' "$ROOT/xray_deploy.sh" > "$RENAME_PY"

awk '
    /refresh_info_file_from_config\(\) \{/ {fn=1; next}
    fn && /python3 << '\''PYEOF'\''/ {count++; if (count == 2) {inside=1}; next}
    inside && /^PYEOF$/ {exit}
    inside {print}
' "$ROOT/xray_deploy.sh" > "$REFRESH_PY"

awk '
    /format_vless_host_py\(\) \{/ {fn=1; next}
    fn && /cat <<'\''PYEOF'\''/ {inside=1; next}
    inside && /^PYEOF$/ {exit}
    inside {print}
' "$ROOT/xray_deploy.sh" > "$FORMAT_HELPER"

cat > "$CONFIG_FILE" <<'JSON'
{
  "inbounds": [
    {"tag": "api-in", "port": 10085},
    {
      "tag": "vless-in-1",
      "port": 443,
      "protocol": "vless",
      "_remark": "LA-Direct",
      "settings": {"clients": [{"id": "ignored"}]},
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {"path": "/fixedPathABC", "mode": "stream-one"},
        "realitySettings": {"shortIds": ["sid"]}
      }
    },
    {
      "tag": "vless-in-2",
      "port": 8444,
      "protocol": "vless",
      "_remark": "Old-Residential",
      "settings": {"clients": [{"id": "ignored"}]},
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {"path": "/fixedPathXYZ", "mode": "auto"},
        "realitySettings": {"shortIds": ["sid"]}
      }
    }
  ],
  "outbounds": [
    {"tag": "socks5-out-2", "protocol": "socks", "settings": {"servers": [{"address": "161.77.77.5", "port": 12324}]}},
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["vless-in-1"], "outboundTag": "direct"},
      {"type": "field", "inboundTag": ["vless-in-2"], "outboundTag": "socks5-out-2"}
    ]
  }
}
JSON

cat > "$INFO_FILE" <<'EOF'
=== LA-Direct ===
端口: 443
出口: VPS 直连 (38.47.118.82)
链接: vless://abc-uuid@38.47.118.82:443?encryption=none&security=reality&type=xhttp&path=%2FfixedPathABC&mode=stream-one#LA-Direct

=== Old-Residential ===
端口: 8444
落地: 161.77.77.5:12324
链接: vless://abc-uuid@38.47.118.82:8444?encryption=none&security=reality&type=xhttp&path=%2FfixedPathXYZ&mode=auto#Old-Residential
EOF

NEW_CONFIG_FILE="$CONFIG_FILE" IDX="2" NEW_NAME="JP-Residential-New" python3 "$RENAME_PY"

python3 - "$CONFIG_FILE" <<'PY'
import json
import sys

config = json.load(open(sys.argv[1]))
inbounds = {inb["tag"]: inb for inb in config["inbounds"]}
assert inbounds["vless-in-1"]["_remark"] == "LA-Direct"
assert inbounds["vless-in-2"]["_remark"] == "JP-Residential-New"

# Path and mode must be preserved after rename
xhttp_2 = inbounds["vless-in-2"]["streamSettings"]["xhttpSettings"]
assert xhttp_2["path"] == "/fixedPathXYZ", f"path changed: {xhttp_2['path']}"
assert xhttp_2["mode"] == "auto", f"mode changed: {xhttp_2['mode']}"
PY

if NEW_CONFIG_FILE="$CONFIG_FILE" IDX="9" NEW_NAME="Nope" python3 "$RENAME_PY" >/dev/null 2>&1; then
    echo "无效编号不应成功"
    exit 1
fi

CONFIG_FILE="$CONFIG_FILE" \
INFO_FILE="$INFO_FILE" \
VPS_IP="38.47.118.82" \
UUID="abc-uuid" \
PUBLIC_KEY="PUBKEY" \
SHORT_ID="SID" \
CLIENT_FP="chrome" \
REALITY_SERVER_NAME="www.cloudflare.com" \
FORMAT_VLESS_HOST_PY="$(cat "$FORMAT_HELPER")" \
REFRESH_NAME_PORT="8444" \
REFRESH_NAME="JP-Residential-New" \
python3 "$REFRESH_PY"

grep -Fq "=== JP-Residential-New ===" "$INFO_FILE"
grep -Fq "#JP-Residential-New" "$INFO_FILE"
if grep -Fq "Old-Residential" "$INFO_FILE"; then
    echo "旧节点名称未被覆盖"
    exit 1
fi

# 验证刷新后的链接保留了 vless-in-2 inbound 的原始 path 和 mode
python3 - "$INFO_FILE" <<'PY'
import sys, urllib.parse

content = open(sys.argv[1]).read()
in_block = False
jp_link = None
for line in content.splitlines():
    if line.startswith("=== JP-Residential-New ==="):
        in_block = True
    elif in_block and line.startswith("链接: "):
        jp_link = line[len("链接: "):]
        break

assert jp_link is not None, "JP-Residential-New 节点链接未找到"
qs = urllib.parse.parse_qs(urllib.parse.urlparse(jp_link).query)
assert qs.get("type") == ["xhttp"], f"type must be xhttp, got {qs.get('type')}"
assert qs.get("path") == ["/fixedPathXYZ"], f"path must be /fixedPathXYZ, got {qs.get('path')}"
assert qs.get("mode") == ["auto"], f"mode must be auto, got {qs.get('mode')}"
assert "flow" not in qs, f"link must not contain flow param"
print("rename path/mode preservation ok")
PY

grep -Fq "15) 修改节点名称" "$ROOT/xray_deploy.sh"

echo "rename node ok"
