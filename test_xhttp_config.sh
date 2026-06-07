#!/bin/bash
# 验证 generate_config 和 add_batch_direct_nodes 生成合法的 XHTTP inbound。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_FILE="$TMP_DIR/config.json"
GEN_PY="$TMP_DIR/gen_config.py"
BATCH_PY="$TMP_DIR/batch_direct.py"

# ---- 提取 generate_config 内嵌 Python ----
awk '
    /generate_config\(\) \{/ {fn=1; next}
    fn && /python3 << '\''PYEOF'\''/ {inside=1; next}
    inside && /^PYEOF$/ {exit}
    inside {print}
' "$ROOT/xray_deploy.sh" > "$GEN_PY"

# ---- 无节点的基础配置生成 ----
NEW_CONFIG_FILE="$CONFIG_FILE" \
UUID="test-uuid" \
PRIVATE_KEY="test-priv" \
SHORT_ID="test-sid" \
REALITY_DEST="www.cloudflare.com:443" \
REALITY_SERVER_NAME="www.cloudflare.com" \
XHTTP_MODE="auto" \
XHTTP_PATH="" \
NODES_DATA="" \
python3 "$GEN_PY"

python3 - "$CONFIG_FILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
inbounds = config["inbounds"]
# 无业务节点时只有 api-in
assert len(inbounds) == 1, f"expected 1 inbound, got {len(inbounds)}"
assert inbounds[0]["tag"] == "api-in"
print("no-nodes config ok")
PY

# ---- 单节点配置 ----
SEP=$'\x1f'
SINGLE_NODE="443${SEP}__DIRECT__${SEP}0${SEP}${SEP}${SEP}LA-Direct"

NEW_CONFIG_FILE="$CONFIG_FILE" \
UUID="test-uuid" \
PRIVATE_KEY="test-priv" \
SHORT_ID="test-sid" \
REALITY_DEST="www.cloudflare.com:443" \
REALITY_SERVER_NAME="www.cloudflare.com" \
XHTTP_MODE="auto" \
XHTTP_PATH="" \
NODES_DATA="$SINGLE_NODE" \
python3 "$GEN_PY"

python3 - "$CONFIG_FILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
inbounds = {inb["tag"]: inb for inb in config["inbounds"]}
inbound = inbounds["vless-in-1"]
stream = inbound["streamSettings"]
assert stream["network"] == "xhttp", f"Expected xhttp, got {stream['network']}"
assert stream["security"] == "reality", f"Expected reality, got {stream['security']}"
assert "xhttpSettings" in stream, "xhttpSettings missing"
assert stream["xhttpSettings"]["path"].startswith("/"), f"path must start with /: {stream['xhttpSettings']['path']}"
assert stream["xhttpSettings"]["mode"] == "auto", f"Expected auto mode, got {stream['xhttpSettings']['mode']}"
assert "target" in stream["realitySettings"], "realitySettings missing target"
clients = inbound["settings"]["clients"]
assert len(clients) == 1
assert "flow" not in clients[0], f"flow field must not be present in client: {clients[0]}"
print("single-node xhttp config ok")
PY

# ---- 两节点配置，路径互不相同 ----
NODES_TWO="${SINGLE_NODE}
443${SEP}__DIRECT__${SEP}0${SEP}${SEP}${SEP}JP-Direct"

NEW_CONFIG_FILE="$CONFIG_FILE" \
UUID="test-uuid" \
PRIVATE_KEY="test-priv" \
SHORT_ID="test-sid" \
REALITY_DEST="www.cloudflare.com:443" \
REALITY_SERVER_NAME="www.cloudflare.com" \
XHTTP_MODE="auto" \
XHTTP_PATH="" \
NODES_DATA="$NODES_TWO" \
python3 "$GEN_PY"

python3 - "$CONFIG_FILE" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
business_inbounds = [inb for inb in config["inbounds"] if inb.get("tag") != "api-in"]
assert len(business_inbounds) == 2, f"Expected 2 business inbounds, got {len(business_inbounds)}"
paths = [inb["streamSettings"]["xhttpSettings"]["path"] for inb in business_inbounds]
assert len(paths) == len(set(paths)) == 2, f"paths must be distinct: {paths}"
print("two-node distinct paths ok")
PY

# ---- 提取 add_batch_direct_nodes 内嵌 Python 并检验 XHTTP shape ----
BATCH_CONFIG="$TMP_DIR/batch_config.json"
cat > "$BATCH_CONFIG" <<'JSON'
{
  "inbounds": [
    {"tag": "api-in", "port": 10085},
    {"tag": "vless-in-5", "port": 8443, "protocol": "vless"}
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["vless-in-5"], "outboundTag": "direct"}
    ]
  }
}
JSON

awk '
    /add_batch_direct_nodes\(\) \{/ {fn=1; next}
    fn && /python3 << '\''PYEOF'\''/ {inside=1; next}
    inside && /^PYEOF$/ {exit}
    inside {print}
' "$ROOT/xray_deploy.sh" > "$BATCH_PY"

SEP=$'\x1f'
BATCH_DIRECT_DATA="6${SEP}8444${SEP}VPS-Direct-1
7${SEP}8445${SEP}VPS-Direct-2"

NEW_CONFIG_FILE="$BATCH_CONFIG" \
UUID="abc-uuid" \
PRIVATE_KEY="priv" \
SHORT_ID="sid" \
REALITY_DEST="www.cloudflare.com:443" \
REALITY_SERVER_NAME="www.cloudflare.com" \
BATCH_DIRECT_DATA="$BATCH_DIRECT_DATA" \
python3 "$BATCH_PY"

python3 - "$BATCH_CONFIG" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    config = json.load(f)
inbounds = {inb["tag"]: inb for inb in config["inbounds"]}
for tag in ["vless-in-6", "vless-in-7"]:
    inb = inbounds[tag]
    stream = inb.get("streamSettings", {})
    assert stream.get("network") == "xhttp", f"Expected xhttp, got {stream.get('network')}"
    assert "xhttpSettings" in stream, "xhttpSettings missing"
    assert stream["xhttpSettings"]["path"].startswith("/"), "path must start with /"
    clients = inb.get("settings", {}).get("clients", [{}])
    assert "flow" not in clients[0], f"flow field must not be present: {clients[0]}"
paths = [inbounds[t]["streamSettings"]["xhttpSettings"]["path"] for t in ["vless-in-6", "vless-in-7"]]
assert len(set(paths)) == 2, f"paths must be distinct: {paths}"
print("batch direct xhttp config shape ok")
PY

echo "xhttp config ok"
