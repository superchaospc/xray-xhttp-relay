# VLESS XHTTP REALITY Relay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a public `superchaospc/xray-xhttp-relay` repository that preserves every existing relay-management feature while changing all managed VLESS inbounds and share links from RAW/TCP + Vision + REALITY to XHTTP + REALITY.

**Architecture:** Keep the existing single-script operational model and menu numbering. Add small embedded Python helpers for validated XHTTP mode/path generation, inbound construction, and URI generation, then route every install/add/refresh/change-port path through those contracts. Treat the active Xray JSON as the source of truth so paths survive rename and port changes without a side database.

**Tech Stack:** Bash, embedded Python 3, Xray-core JSON configuration, shell regression tests, ShellCheck, Git/GitHub CLI.

---

## File Map

- Modify `xray_deploy.sh`: XHTTP constants, validation, path generation, inbound JSON, link generation, version diagnostics, banners and repository identity.
- Modify `run_all_tests.sh`: register XHTTP-focused regression tests.
- Create `test_xhttp_helpers.sh`: mode/path validation, random path uniqueness, URI encoding, and no-legacy-field checks.
- Create `test_xhttp_config.sh`: initial, single, and batch inbound configuration contracts.
- Modify `test_batch_direct_nodes.sh`: require distinct XHTTP paths and no Vision flow.
- Modify `test_info_parse.sh`, `test_subscription_file.sh`, `test_rename_node.sh`, `test_config_remarks.sh`, and `test_public_key_and_ports.sh`: use XHTTP share-link fixtures and assert path persistence.
- Modify `README.md`: rename project, installation URL, XHTTP environment variables, compatibility and migration warnings.
- Modify `docs/superpowers/specs/2026-06-06-vless-xhttp-reality-relay-design.md`: retain as the accepted design record.

### Task 1: Lock the XHTTP helper contract with failing tests

**Files:**
- Create: `test_xhttp_helpers.sh`
- Modify: `run_all_tests.sh`
- Test: `test_xhttp_helpers.sh`

- [ ] **Step 1: Write the failing helper regression test**

Create a shell test that extracts the embedded helper source from `xray_deploy.sh` and asserts:

```bash
assert_mode auto
assert_mode stream-one
assert_mode stream-up
assert_mode packet-up
if assert_mode invalid-mode; then exit 1; fi

path1=$(generate_xhttp_path)
path2=$(generate_xhttp_path)
[[ "$path1" =~ ^/[A-Za-z0-9_-]{16,64}$ ]]
[ "$path1" != "$path2" ]

[ "$(normalize_xhttp_path alpha/beta)" = "/alpha/beta" ]
if normalize_xhttp_path "/bad path"; then exit 1; fi

link=$(build_vless_link "uuid" "2001:db8::1" 443 "example.com" chrome pk sid "/a/b?c" auto "Node Name")
[[ "$link" == *"type=xhttp"* ]]
[[ "$link" == *"path=%2Fa%2Fb%3Fc"* ]]
[[ "$link" == *"mode=auto"* ]]
[[ "$link" == *"#Node%20Name" ]]
[[ "$link" != *"flow="* ]]
```

Add it to `run_all_tests.sh` immediately after `test_public_key_and_ports.sh`.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash test_xhttp_helpers.sh
```

Expected: non-zero exit because the XHTTP helper block and functions do not exist.

- [ ] **Step 3: Add the minimal helper implementation**

In `xray_deploy.sh`, add:

```bash
XHTTP_MODE="${XHTTP_MODE:-auto}"
XHTTP_PATH="${XHTTP_PATH:-}"
```

Add one embedded Python helper block that defines:

```python
VALID_XHTTP_MODES = {"auto", "stream-one", "stream-up", "packet-up"}

def validate_xhttp_mode(mode):
    if mode not in VALID_XHTTP_MODES:
        raise ValueError("XHTTP_MODE must be auto, stream-one, stream-up, or packet-up")
    return mode

def normalize_xhttp_path(path):
    path = "/" + path.lstrip("/")
    if not re.fullmatch(r"/[A-Za-z0-9._~!$&'()*+,;=:@%/-]+", path):
        raise ValueError("invalid XHTTP path")
    return path

def generate_xhttp_path(existing=()):
    existing = set(existing)
    while True:
        candidate = "/" + secrets.token_urlsafe(18).rstrip("=")
        if candidate not in existing:
            return candidate

def build_vless_link(uuid, host, port, sni, fp, pbk, sid, path, mode, name):
    host = f"[{host}]" if ":" in host and not host.startswith("[") else host
    query = urllib.parse.urlencode({
        "encryption": "none",
        "security": "reality",
        "sni": sni,
        "fp": fp,
        "pbk": pbk,
        "sid": sid,
        "type": "xhttp",
        "path": path,
        "mode": mode,
    })
    return f"vless://{uuid}@{host}:{port}?{query}#{urllib.parse.quote(name, safe='')}"
```

Expose thin Bash wrappers used by the test and later tasks.

- [ ] **Step 4: Run the helper test and full baseline**

Run:

```bash
bash test_xhttp_helpers.sh
bash run_all_tests.sh
```

Expected: helper test passes; existing fixture tests may fail only where they explicitly expect TCP links.

- [ ] **Step 5: Commit the helper contract**

```bash
git add xray_deploy.sh test_xhttp_helpers.sh run_all_tests.sh
git commit -m "feat: add validated xhttp transport helpers"
```

### Task 2: Convert initial and incremental inbound generation

**Files:**
- Create: `test_xhttp_config.sh`
- Modify: `xray_deploy.sh`
- Modify: `run_all_tests.sh`
- Modify: `test_batch_direct_nodes.sh`
- Test: `test_xhttp_config.sh`
- Test: `test_batch_direct_nodes.sh`

- [ ] **Step 1: Write failing inbound-shape tests**

Extract and execute the initial and batch-direct embedded Python blocks with deterministic inputs. Assert each business inbound has:

```python
stream = inbound["streamSettings"]
assert stream["network"] == "xhttp"
assert stream["security"] == "reality"
assert stream["xhttpSettings"]["mode"] == "auto"
assert stream["xhttpSettings"]["path"].startswith("/")
assert "target" in stream["realitySettings"]
assert "dest" not in stream["realitySettings"]
assert "flow" not in inbound["settings"]["clients"][0]
```

For two batch nodes:

```python
paths = [inb["streamSettings"]["xhttpSettings"]["path"] for inb in business]
assert len(paths) == len(set(paths)) == 2
```

Add `test_xhttp_config.sh` to `run_all_tests.sh`.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
bash test_xhttp_config.sh
bash test_batch_direct_nodes.sh
```

Expected: failures showing `network` is `tcp`, `xhttpSettings` is absent, or `flow` remains.

- [ ] **Step 3: Convert every inbound constructor**

Update the embedded Python in:

- `generate_config`
- `add_batch_nodes`
- `add_node`
- `add_direct_node`
- `add_batch_direct_nodes`

Each constructor must validate `XHTTP_MODE`, gather existing paths from:

```python
{
    inb.get("streamSettings", {}).get("xhttpSettings", {}).get("path")
    for inb in config.get("inbounds", [])
}
```

and create:

```python
"settings": {"clients": [{"id": uuid}], "decryption": "none"},
"streamSettings": {
    "network": "xhttp",
    "security": "reality",
    "xhttpSettings": {"path": path, "mode": xhttp_mode},
    "realitySettings": {
        "target": reality_dest,
        "serverNames": [reality_server_name],
        "privateKey": private_key,
        "shortIds": [short_id],
    },
    "sockopt": {"tcpFastOpen": True, "tcpNoDelay": True},
},
```

Use `XHTTP_PATH` only for a single-node creation. Reject collisions. Initial and batch creation always generate one unique path per inbound unless the initial install contains exactly one node and an explicit path was supplied.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
bash test_xhttp_config.sh
bash test_batch_direct_nodes.sh
bash run_all_tests.sh
```

Expected: XHTTP configuration tests pass; remaining failures are limited to old link fixtures.

- [ ] **Step 5: Commit inbound conversion**

```bash
git add xray_deploy.sh test_xhttp_config.sh test_batch_direct_nodes.sh run_all_tests.sh
git commit -m "feat: generate xhttp reality inbounds"
```

### Task 3: Convert all share links and preserve paths

**Files:**
- Modify: `xray_deploy.sh`
- Modify: `test_info_parse.sh`
- Modify: `test_subscription_file.sh`
- Modify: `test_rename_node.sh`
- Modify: `test_config_remarks.sh`
- Modify: `test_public_key_and_ports.sh`
- Modify: `test_batch_delete_nodes.sh`
- Modify: `test_restart_rollback_permissions.sh`
- Test: the files above

- [ ] **Step 1: Update fixtures first and verify RED**

Replace TCP fixtures with encoded XHTTP links such as:

```text
vless://abc-uuid@38.47.118.82:443?encryption=none&security=reality&sni=www.cloudflare.com&fp=chrome&pbk=PUBKEY&sid=SID&type=xhttp&path=%2Fnode-one&mode=auto#LA-Direct
```

Add assertions that rename and port-change operations retain the original
`xhttpSettings.path`. Extend `test_batch_delete_nodes.sh` so the deleted
inbound and its path are absent while every retained inbound keeps its
original path. Extend `test_restart_rollback_permissions.sh` with an
XHTTP candidate containing a known path and assert a failed restart
restores the previous configuration and path byte-for-byte.

Run:

```bash
bash test_info_parse.sh
bash test_subscription_file.sh
bash test_rename_node.sh
bash test_config_remarks.sh
bash test_public_key_and_ports.sh
bash test_batch_delete_nodes.sh
bash test_restart_rollback_permissions.sh
```

Expected: failures because production code still emits TCP links.

- [ ] **Step 2: Use the link helper everywhere**

Replace manual VLESS URI concatenation in:

- `print_result`
- `refresh_info_file_from_config`
- `add_batch_nodes`
- `add_node`
- `add_direct_node`
- `add_batch_direct_nodes`
- `change_port`

Read `path` and `mode` from each inbound's `xhttpSettings`. Do not regenerate either value during refresh, rename, or port changes. Percent-encode all query values and fragments via `urllib.parse`.

- [ ] **Step 3: Add a legacy-field guard**

In `test_xhttp_helpers.sh`, scan production link/config code:

```bash
if rg -n 'type=tcp|xtls-rprx-vision|"network"[[:space:]]*:[[:space:]]*"tcp"' xray_deploy.sh; then
    echo "legacy transport field remains"
    exit 1
fi
```

These patterns target legacy VLESS literals. Operational firewall,
sysctl, and socket-tuning strings do not match them.

- [ ] **Step 4: Run focused and full tests**

Run:

```bash
bash test_xhttp_helpers.sh
bash test_info_parse.sh
bash test_subscription_file.sh
bash test_rename_node.sh
bash test_config_remarks.sh
bash test_public_key_and_ports.sh
bash test_batch_delete_nodes.sh
bash test_restart_rollback_permissions.sh
bash run_all_tests.sh
```

Expected: all tests pass.

- [ ] **Step 5: Commit link conversion**

```bash
git add xray_deploy.sh test_xhttp_helpers.sh test_info_parse.sh test_subscription_file.sh test_rename_node.sh test_config_remarks.sh test_public_key_and_ports.sh test_batch_delete_nodes.sh test_restart_rollback_permissions.sh
git commit -m "feat: generate persistent xhttp share links"
```

### Task 4: Add Xray compatibility diagnostics

**Files:**
- Modify: `xray_deploy.sh`
- Create: `test_xray_version.sh`
- Modify: `run_all_tests.sh`
- Test: `test_xray_version.sh`

- [ ] **Step 1: Write a failing version parser test**

Test these cases:

```bash
version_at_least "24.10.31" "24.10.31"
version_at_least "26.3.27" "24.10.31"
if version_at_least "24.9.30" "24.10.31"; then exit 1; fi
[ "$(parse_xray_version 'Xray 26.6.1 (Xray, Penetrates Everything.)')" = "26.6.1" ]
```

Also assert diagnostics mention XHTTP when the fake Xray version is below
`24.10.31`. Xray-core `v24.10.31` is the first stable release whose
official release notes state that SplitHTTP and HTTP were merged into
XHTTP and REALITY was unblocked for the transport.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
bash test_xray_version.sh
```

Expected: failure because version helpers are absent.

- [ ] **Step 3: Implement version handling**

Define `MIN_XHTTP_XRAY_VERSION="24.10.31"`. Parse `xray version`,
compare numeric components without external version-sort dependencies,
and:

- fail installation before changing configuration when XHTTP is unsupported;
- warn in `show_status`;
- report an error in `troubleshoot`;
- keep `update_xray` as the remediation path.

Regardless of version parsing, retain `xray run -test -config "$candidate"` as the authoritative compatibility check.

- [ ] **Step 4: Run test and suite**

Run:

```bash
bash test_xray_version.sh
bash run_all_tests.sh
```

Expected: all tests pass.

- [ ] **Step 5: Commit diagnostics**

```bash
git add xray_deploy.sh test_xray_version.sh run_all_tests.sh
git commit -m "feat: diagnose xhttp core compatibility"
```

### Task 5: Rebrand documentation without changing operations

**Files:**
- Modify: `README.md`
- Modify: `xray_deploy.sh`
- Create: `test_project_identity.sh`
- Modify: `run_all_tests.sh`
- Test: `test_project_identity.sh`

- [ ] **Step 1: Write failing identity and documentation assertions**

Assert:

```bash
grep -Fq 'superchaospc/xray-xhttp-relay' README.md
grep -Fq 'VLESS + XHTTP + REALITY' README.md
grep -Fq 'XHTTP_MODE' README.md
grep -Fq 'XHTTP_PATH' README.md
grep -Fq '不会自动迁移旧 RAW/TCP 节点' README.md
grep -Fq 'XHTTP Reality 中转部署工具' xray_deploy.sh
```

Also assert all existing menu labels `1)` through `16)` remain present.

- [ ] **Step 2: Run and verify RED**

Run:

```bash
bash test_project_identity.sh
```

Expected: failure because repository identity and docs still describe the old project.

- [ ] **Step 3: Update README and user-facing text**

Document:

- new repository name and raw install URL;
- XHTTP + REALITY architecture;
- default `XHTTP_MODE=auto`;
- supported mode overrides;
- single-node `XHTTP_PATH` behavior;
- no Vision `flow`;
- clients must preserve `type=xhttp`, `path`, and `mode`;
- old RAW/TCP deployments are not migrated automatically;
- installing over an old deployment replaces active Xray configuration;
- all original relay, monitoring, firewall, traffic, and node-management features remain.

Keep attribution and license. Update banner/version to the new project's first release without renumbering menu items.

- [ ] **Step 4: Run identity and full tests**

Run:

```bash
bash test_project_identity.sh
bash run_all_tests.sh
```

Expected: all tests pass.

- [ ] **Step 5: Commit rebrand**

```bash
git add README.md xray_deploy.sh test_project_identity.sh run_all_tests.sh
git commit -m "docs: publish xhttp relay project guidance"
```

### Task 6: Validate with the real Xray binary

**Files:**
- Create: `test_xray_real_config.sh`
- Modify: `run_all_tests.sh`
- Test: `test_xray_real_config.sh`

- [ ] **Step 1: Add a real-binary configuration test**

Generate a temporary minimal config using `xray uuid` and `xray x25519`,
with one XHTTP + REALITY VLESS inbound on `127.0.0.1:443`, API inbound,
direct/block outbounds, `target: "www.cloudflare.com:443"`,
`mode: "auto"`, and a fixed test-only path. Parse both current Xray key
output labels (`Private key` and `Password`) without printing secrets.
Use the same JSON shape as the script. Run:

```bash
xray run -test -config "$CONFIG_FILE"
```

Skip with exit 0 and a clear message only when `xray` is unavailable. Never print the generated private key.

- [ ] **Step 2: Run the test**

Run:

```bash
bash test_xray_real_config.sh
```

Expected: Xray reports configuration OK. If it rejects a field, update the production and test JSON together, then rerun.

- [ ] **Step 3: Run static and full verification**

Run:

```bash
bash -n xray_deploy.sh
shellcheck -S error xray_deploy.sh test_*.sh
bash run_all_tests.sh
git diff --check
```

Expected: zero exit codes, no test failures, and no whitespace errors.

- [ ] **Step 4: Audit the accepted specification**

Confirm with searches:

```bash
rg -n 'type=tcp|xtls-rprx-vision' xray_deploy.sh README.md test_*.sh
rg -n 'network.*tcp' xray_deploy.sh
rg -n 'xhttpSettings|type=xhttp|XHTTP_MODE|XHTTP_PATH' xray_deploy.sh README.md test_*.sh
```

Expected: no legacy VLESS transport/link fields; TCP references are only operational TCP socket/firewall tuning.

- [ ] **Step 5: Commit final verification test**

```bash
git add test_xray_real_config.sh run_all_tests.sh
git commit -m "test: validate xhttp reality with xray"
```

### Task 7: Independent review and GitHub publication

**Files:**
- Review all changed files.
- No production edit is required unless review finds a defect.

- [ ] **Step 1: Review the complete diff**

Run:

```bash
git status --short
git diff upstream/main...HEAD --stat
git diff upstream/main...HEAD -- xray_deploy.sh README.md run_all_tests.sh test_*.sh
```

Check every original menu action still exists and every VLESS creation
path uses XHTTP. Record that live VPS and client connectivity remain a
release limitation unless SSH access to a disposable VPS and a
maintained client are available in the current environment; local
real-core validation is not presented as an end-to-end connectivity
test.

- [ ] **Step 2: Run final verification from a clean state**

Run:

```bash
bash run_all_tests.sh
shellcheck -S error xray_deploy.sh test_*.sh
git diff --check upstream/main...HEAD
```

Expected: all tests pass and lint/diff checks exit zero.

- [ ] **Step 3: Create the public GitHub repository**

Authenticate with the existing GitHub CLI session and run:

```bash
gh repo create superchaospc/xray-xhttp-relay \
  --public \
  --description "One-click Xray VLESS + XHTTP + REALITY relay with residential SOCKS5 support" \
  --source . \
  --remote origin \
  --push
```

If `origin` already exists locally, create the remote repository without adding a remote, then push:

```bash
gh repo create superchaospc/xray-xhttp-relay --public --description "One-click Xray VLESS + XHTTP + REALITY relay with residential SOCKS5 support"
git push -u origin main
```

- [ ] **Step 4: Verify the published repository**

Run:

```bash
gh repo view superchaospc/xray-xhttp-relay --json nameWithOwner,isPrivate,url,defaultBranchRef
git ls-remote origin refs/heads/main
```

Expected: `isPrivate` is `false`, default branch is `main`, and remote `main` resolves to local `HEAD`.

- [ ] **Step 5: Report delivery**

Provide the repository URL, test count, Xray version used for real-config validation, and any unperformed VPS/client smoke tests. Do not claim live connectivity unless a disposable VPS and maintained client were actually exercised.
