#!/bin/bash
# 验证本地 REALITY 落地 (REALITY_DEST_LOCAL=1)：
#   - generate_config 在 REALITY_DEST_LOCAL=1 时追加 reality-dest-local 内置 TLS inbound
#   - 该 inbound 仅监听 127.0.0.1、自签证书、minVersion 1.3，且不污染业务节点枚举
#   - 业务节点 REALITY target 指向本机
#   - load_node_identity 跳过 reality-dest-local，正确取到真实节点密钥与 dest
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_FILE="$TMP_DIR/config.json"
GEN_PY="$TMP_DIR/gen_config.py"
ID_PY="$TMP_DIR/identity.py"

# ---- 提取 generate_config 内嵌 Python ----
awk '
    /generate_config\(\) \{/ {fn=1; next}
    fn && /python3 << '\''PYEOF'\''/ {inside=1; next}
    inside && /^PYEOF$/ {exit}
    inside {print}
' "$ROOT/xray_deploy.sh" > "$GEN_PY"

SEP=$'\x1f'
NODE="443${SEP}__DIRECT__${SEP}0${SEP}${SEP}${SEP}LA-Direct"

NEW_CONFIG_FILE="$CONFIG_FILE" \
UUID="test-uuid" \
PRIVATE_KEY="test-priv" \
SHORT_ID="test-sid" \
REALITY_DEST="127.0.0.1:9443" \
REALITY_SERVER_NAME="www.cloudflare.com" \
REALITY_DEST_LOCAL="1" \
REALITY_DEST_LOCAL_PORT="9443" \
REALITY_DEST_CERT="/usr/local/etc/xray/reality-dest.crt" \
REALITY_DEST_KEY="/usr/local/etc/xray/reality-dest.key" \
XHTTP_MODE="auto" \
XHTTP_PATH="" \
NODES_DATA="$NODE" \
python3 "$GEN_PY"

python3 - "$CONFIG_FILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
inbounds = {inb.get("tag"): inb for inb in config["inbounds"]}

# 1) 本地落地 inbound 存在且形态正确
assert "reality-dest-local" in inbounds, "缺少 reality-dest-local inbound"
rd = inbounds["reality-dest-local"]
assert rd["listen"] == "127.0.0.1", f"必须仅监听 127.0.0.1: {rd.get('listen')}"
assert rd["port"] == 9443, f"端口应为 9443: {rd.get('port')}"
stream = rd["streamSettings"]
assert stream["security"] == "tls", f"应为 tls: {stream['security']}"
assert stream["tlsSettings"]["minVersion"] == "1.3", "minVersion 应为 1.3"
certs = stream["tlsSettings"]["certificates"][0]
assert certs["certificateFile"].endswith("reality-dest.crt"), certs
assert certs["keyFile"].endswith("reality-dest.key"), certs
assert stream["tlsSettings"]["serverName"] == "www.cloudflare.com"

# 2) 业务节点 target 指向本机
biz = [i for i in config["inbounds"] if i.get("tag") not in ("api-in", "reality-dest-local")]
assert len(biz) == 1, f"业务节点数应为 1，实得 {len(biz)}"
assert biz[0]["streamSettings"]["realitySettings"]["target"] == "127.0.0.1:9443", "业务节点 target 应指向本机"

# 3) reality-dest-local 不计入业务节点（按脚本统一口径）
assert "reality-dest-local" not in [i.get("tag") for i in biz], "本地落地不应被当作业务节点"
print("local-dest inbound shape + 业务枚举排除 ok")
PY

# ---- load_node_identity：reality-dest-local 排在前面也要跳过 ----
awk '
    /load_node_identity\(\) \{/ {fn=1; next}
    fn && /python3 << '\''PYEOF'\''/ {inside=1; next}
    inside && /^PYEOF$/ {exit}
    inside {print}
' "$ROOT/xray_deploy.sh" > "$ID_PY"

IDCFG="$TMP_DIR/idcfg.json"
cat > "$IDCFG" <<'JSON'
{
  "inbounds": [
    {"tag": "api-in", "port": 10085, "listen": "127.0.0.1"},
    {"tag": "reality-dest-local", "port": 9443, "listen": "127.0.0.1",
     "settings": {"clients": [{"id": "DUMMY"}]},
     "streamSettings": {"security": "tls"}},
    {"tag": "vless-in-1", "port": 443,
     "settings": {"clients": [{"id": "REAL-UUID"}]},
     "streamSettings": {"realitySettings": {"privateKey": "REAL-PRIV", "shortIds": ["abcd"],
       "serverNames": ["www.cloudflare.com"], "target": "127.0.0.1:9443"}}}
  ]
}
JSON

OUT=$(CONFIG_FILE="$IDCFG" python3 "$ID_PY")
echo "$OUT" | grep -qE "^PRIVATE_KEY='?REAL-PRIV'?$"        || { echo "✗ 未跳过 reality-dest-local，取到错误 PRIVATE_KEY: $OUT"; exit 1; }
echo "$OUT" | grep -qE "^UUID='?REAL-UUID'?$"               || { echo "✗ UUID 未取自真实节点: $OUT"; exit 1; }
echo "$OUT" | grep -qE "^REALITY_DEST='?127.0.0.1:9443'?$"  || { echo "✗ 未从 config 读出本地 dest: $OUT"; exit 1; }
echo "load_node_identity 跳过本地落地并取真实节点 ok"

echo "local dest ok"
