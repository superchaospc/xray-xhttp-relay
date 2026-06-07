#!/bin/bash
# 验证项目身份标识、协议类型、环境变量文档、菜单数量与迁移警告准确性。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "$1"; exit 1; }

# ---- 仓库名称 ----
grep -q "xray-xhttp-relay" "$ROOT/README.md" \
    || fail "README.md 未包含仓库名 xray-xhttp-relay"

# ---- 协议三要素 ----
grep -q "VLESS" "$ROOT/xray_deploy.sh" \
    || fail "xray_deploy.sh 未包含 VLESS"
grep -q "XHTTP" "$ROOT/xray_deploy.sh" \
    || fail "xray_deploy.sh 未包含 XHTTP"
grep -q "REALITY" "$ROOT/xray_deploy.sh" \
    || fail "xray_deploy.sh 未包含 REALITY"

# ---- XHTTP_MODE / XHTTP_PATH 环境变量文档 ----
grep -q "XHTTP_MODE" "$ROOT/README.md" \
    || fail "README.md 未文档化 XHTTP_MODE 环境变量"
grep -q "XHTTP_PATH" "$ROOT/README.md" \
    || fail "README.md 未文档化 XHTTP_PATH 环境变量"

# ---- 16 个菜单功能 ----
menu_count=$(awk '/main_menu\(\)/{f=1} f && /^\}$/{exit} f{print}' "$ROOT/xray_deploy.sh" \
    | grep -cE '^\s+[0-9]+\) ' || true)
if [ "${menu_count:-0}" -lt 16 ]; then
    fail "main_menu 应有至少 16 条操作，实际: ${menu_count}"
fi

# ---- 迁移警告：必须明确说明全新安装会替换现有配置 ----
# 确认 README.md 不再声称"不会覆盖"
if grep -q "不会.*覆盖" "$ROOT/README.md"; then
    fail "README.md 仍含有错误的"不会覆盖"声明，迁移警告不准确"
fi
# 确认 README.md 说明了备份需求
grep -q "备份" "$ROOT/README.md" \
    || fail "README.md 迁移警告未提示备份"
# 确认 README.md 说明了配置将被替换/覆盖
grep -qE "将被.*替换|将.*覆盖|会.*覆盖|将被新配置" "$ROOT/README.md" \
    || fail "README.md 迁移警告未明确说明 config.json 将被替换"

# ---- 客户端兼容提示：不得宣称 NekoBox / NekoRay 可直接扫码使用 ----
if grep -qiE "Neko(Box|Ray)|Neobox" "$ROOT/xray_deploy.sh"; then
    fail "xray_deploy.sh 不应宣称 NekoBox / NekoRay 支持 XHTTP 二维码"
fi
grep -q "支持 XHTTP + REALITY 的客户端" "$ROOT/xray_deploy.sh" \
    || fail "xray_deploy.sh 缺少通用 XHTTP + REALITY 客户端提示"

echo "project identity ok"
