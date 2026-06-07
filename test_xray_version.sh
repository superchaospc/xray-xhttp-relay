#!/bin/bash
# 验证 Xray 版本解析与比较函数，以及 MIN_XHTTP_XRAY_VERSION 最低版本要求。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DEFS="$TMP_DIR/xray_defs.sh"
awk '/^preflight_check$/ {exit} {print}' "$ROOT/xray_deploy.sh" > "$DEFS"
# shellcheck disable=SC1090
source "$DEFS"

# ---- MIN_XHTTP_XRAY_VERSION 常量 ----
if [ "$MIN_XHTTP_XRAY_VERSION" != "24.10.31" ]; then
    echo "MIN_XHTTP_XRAY_VERSION 应为 24.10.31，实际: $MIN_XHTTP_XRAY_VERSION"
    exit 1
fi

# ---- parse_xray_version ----
ver=$(parse_xray_version "Xray 24.10.31 (xray-core)")
if [ "$ver" != "24.10.31" ]; then
    echo "parse_xray_version 解析失败，期望 24.10.31，实际: $ver"
    exit 1
fi

ver2=$(parse_xray_version "Xray 25.3.6 (xray-core) (go1.22)")
if [ "$ver2" != "25.3.6" ]; then
    echo "parse_xray_version 解析失败，期望 25.3.6，实际: $ver2"
    exit 1
fi

if parse_xray_version "no version here" 2>/dev/null; then
    echo "无版本号时 parse_xray_version 不应成功"
    exit 1
fi

# ---- version_at_least ----
version_at_least "24.10.31" "24.10.31" || { echo "24.10.31 >= 24.10.31 应为真"; exit 1; }
version_at_least "25.1.0" "24.10.31"   || { echo "25.1.0 >= 24.10.31 应为真"; exit 1; }
version_at_least "24.10.31" "24.10.32" && { echo "24.10.31 >= 24.10.32 应为假"; exit 1; } || true
version_at_least "24.9.1" "24.10.31"   && { echo "24.9.1 >= 24.10.31 应为假"; exit 1; } || true
version_at_least "23.99.99" "24.10.31" && { echo "23.99.99 >= 24.10.31 应为假"; exit 1; } || true

# ---- check_xray_version_for_xhttp：版本过旧时报错 ----
FAKE_XRAY_OLD="$TMP_DIR/xray_old"
cat > "$FAKE_XRAY_OLD" <<'SH'
#!/bin/bash
echo "Xray 24.9.30 (xray-core)"
SH
chmod +x "$FAKE_XRAY_OLD"

XRAY_BIN="$FAKE_XRAY_OLD" out=$(check_xray_version_for_xhttp 2>&1) && {
    echo "版本过旧时 check_xray_version_for_xhttp 应返回非零"; exit 1
} || true
if ! echo "$out" | grep -q "24.9.30"; then
    echo "报错信息应包含当前版本号: $out"
    exit 1
fi
if ! echo "$out" | grep -q "菜单 8"; then
    echo "报错信息应包含菜单8升级提示: $out"
    exit 1
fi

# ---- check_xray_version_for_xhttp：版本足够时静默通过 ----
FAKE_XRAY_OK="$TMP_DIR/xray_ok"
cat > "$FAKE_XRAY_OK" <<'SH'
#!/bin/bash
echo "Xray 24.10.31 (xray-core)"
SH
chmod +x "$FAKE_XRAY_OK"

XRAY_BIN="$FAKE_XRAY_OK" check_xray_version_for_xhttp 2>/dev/null || {
    echo "版本 24.10.31 应通过 check_xray_version_for_xhttp"; exit 1
}

FAKE_XRAY_NEW="$TMP_DIR/xray_new"
cat > "$FAKE_XRAY_NEW" <<'SH'
#!/bin/bash
echo "Xray 25.6.1 (xray-core)"
SH
chmod +x "$FAKE_XRAY_NEW"

XRAY_BIN="$FAKE_XRAY_NEW" check_xray_version_for_xhttp 2>/dev/null || {
    echo "版本 25.6.1 应通过 check_xray_version_for_xhttp"; exit 1
}

# ---- check_xray_version_for_xhttp：xray 不存在时静默通过 ----
XRAY_BIN="$TMP_DIR/nonexistent_xray_bin" check_xray_version_for_xhttp 2>/dev/null || {
    echo "xray 不存在时应静默返回 0"; exit 1
}

echo "xray version ok"
