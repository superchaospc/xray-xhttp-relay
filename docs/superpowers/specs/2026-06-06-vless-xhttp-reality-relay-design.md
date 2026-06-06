# VLESS XHTTP REALITY Relay Design

## Goal

Create a new public GitHub repository named
`superchaospc/xray-xhttp-relay`, derived from
`superchaospc/xray-relay`. Replace the public VLESS transport from
RAW/TCP + REALITY to XHTTP + REALITY while preserving the existing
installation, relay, node-management, monitoring, diagnostics, traffic,
firewall, subscription, rollback, and uninstall behavior.

The new repository is a separate project. The existing
`superchaospc/xray-relay` repository and its deployed RAW/TCP nodes remain
unchanged.

## Scope

The new project retains:

- All 16 existing menu actions and their current numbering.
- Direct VPS nodes and VPS-to-residential-SOCKS5 relay nodes.
- Single-node and batch node creation.
- Node deletion, batch deletion, rename, and port changes.
- Atomic configuration validation, installation, backup, and rollback.
- Firewall management, BBR tuning, traffic statistics, diagnostics,
  Xray updates, monitoring, subscriptions, QR codes, and uninstall.
- Existing Linux distribution support and installer supply-chain checks.

The project changes:

- Every managed VLESS inbound uses `network: "xhttp"` and
  `security: "reality"`.
- Every managed inbound has an XHTTP path.
- Generated VLESS links use `type=xhttp` and include `path` and `mode`.
- Documentation, labels, examples, tests, and repository identity refer
  to VLESS + XHTTP + REALITY.

The first release does not:

- Add a RAW/TCP compatibility mode.
- Convert nodes deployed by the old repository in place.
- Add CDN, reverse-proxy, domain, TLS certificate, or upload/download
  separation automation.
- Change the existing SOCKS5 outbound and routing architecture.

## Protocol Configuration

Each managed VLESS inbound has this transport shape:

```json
{
  "streamSettings": {
    "network": "xhttp",
    "security": "reality",
    "xhttpSettings": {
      "path": "/<random-node-path>",
      "mode": "auto"
    },
    "realitySettings": {
      "target": "<REALITY_DEST>",
      "serverNames": ["<REALITY_SERVER_NAME>"],
      "privateKey": "<private-key>",
      "shortIds": ["<short-id>"]
    },
    "sockopt": {
      "tcpFastOpen": true,
      "tcpNoDelay": true
    }
  }
}
```

The implementation uses the current `target` name instead of the legacy
`dest` alias. Existing REALITY key generation, public-key caching,
fingerprint selection, SNI configuration, and target overrides remain.

The new project removes `flow: "xtls-rprx-vision"` from server clients
and share links. Current upstream documentation limits XTLS Vision's
transport combination to TCP + TLS/REALITY, while XHTTP has its own XMUX
behavior. Carrying the old flow field into XHTTP would therefore create
an undocumented and potentially client-dependent configuration.

## XHTTP Mode

The default mode is `auto`. With XHTTP + REALITY, this lets the client
select Xray's default direct-connection behavior without requiring CDN or
reverse-proxy infrastructure.

`XHTTP_MODE` may override the default with:

- `auto`
- `stream-one`
- `stream-up`
- `packet-up`

The script validates the value before writing configuration. A bad value
stops the requested mutation without changing the active Xray
configuration.

## Path Lifecycle

Each node receives a distinct cryptographically random path when it is
created. The canonical stored value starts with `/` and contains only
URL-safe ASCII characters.

- A port change preserves the node's path.
- A rename preserves the node's path.
- Subscription and info-file refreshes read the path from the active
  configuration.
- Deleting a node deletes its path with the inbound.
- Batch creation generates and checks a separate path for every node.
- New paths are checked against all managed inbounds before use.

For deterministic automation, `XHTTP_PATH` may provide a path for a
single-node creation. Batch operations do not reuse one forced path;
they generate unique paths. The override is normalized and validated,
and cannot collide with an existing managed inbound.

## Share Links and State

Generated links use the existing VLESS URI fields plus:

```text
type=xhttp&path=<percent-encoded-path>&mode=<percent-encoded-mode>
```

The link generator uses structured percent encoding for query values and
node names. It must not concatenate unescaped user input.

The active Xray JSON configuration remains the source of truth. The
script regenerates:

- `/root/xray_nodes_info.txt`
- `/root/xray_subscription.txt`

from the active configuration after install and every successful node
mutation. Existing files produced by the new repository can therefore be
recovered without a second path database.

## Version and Client Compatibility

The script installs or updates to an Xray release that supports the
selected XHTTP configuration and validates it with `xray run -test`.
Preflight and diagnostics report an actionable error when the installed
core is too old for XHTTP.

README compatibility guidance distinguishes:

- Xray-based clients that understand XHTTP share-link fields.
- Clients that support REALITY but do not yet support XHTTP.
- Manual JSON import as a fallback when a GUI does not preserve `path`
  or `mode`.

No claim of compatibility is made without a tested client or an
upstream-documented capability.

## Safety and Error Handling

All configuration mutations continue using the existing workflow:

1. Create a temporary configuration.
2. Make the requested structured JSON change.
3. Run `xray run -test`.
4. Back up and atomically replace the active configuration.
5. Restart Xray.
6. Roll back automatically if validation or restart fails.
7. Update firewall and generated files only after successful activation.

Path and mode validation occurs before step 3. Existing permissions and
secret-redaction behavior remain unchanged.

The old project is not automatically detected or overwritten. The new
README explains that installing the new script on a server already
managed by `xray-relay` replaces the active Xray configuration and
therefore requires an intentional migration window.

## Repository Structure and Attribution

The new repository starts from the current `xray-relay` main branch so
that its mature tests and maintenance behavior are retained. It keeps
the existing license and adds clear attribution to the source project.

Primary files remain:

- `xray_deploy.sh`
- `README.md`
- `run_all_tests.sh`
- focused `test_*.sh` regression tests

The script filename and menu numbering remain stable to minimize
operational changes. Repository URLs, download commands, banners, and
managed firewall comments are updated only where project identity
requires it.

## Testing

The existing test suite must remain green after updating fixtures for
XHTTP links and configuration.

New or expanded tests cover:

- Inbound generation with XHTTP + REALITY.
- Valid and invalid `XHTTP_MODE` values.
- Random path syntax and uniqueness.
- `XHTTP_PATH` normalization, rejection, and collision handling.
- Path preservation after rename and port change.
- Path removal after delete and batch delete.
- Correct percent-encoded XHTTP share links.
- Info-file and subscription reconstruction from active JSON.
- Batch direct and SOCKS5 node creation with distinct paths.
- Minimum Xray version handling.
- Atomic rollback when XHTTP configuration validation fails.

Verification includes:

- `bash -n` and the complete local test suite.
- ShellCheck when available.
- `xray run -test` against the selected current Xray binary.
- A disposable Linux VPS smoke test covering install, direct node,
  SOCKS5 relay node, status, traffic, diagnostics, rename, port change,
  restart, deletion, and uninstall.
- Client connection tests for at least one maintained Xray-based desktop
  or mobile client before documenting it as compatible.

## Delivery

After verification, create the public repository
`superchaospc/xray-xhttp-relay`, push the implementation on its default
branch, and publish installation instructions that point only to the new
repository. The original repository remains untouched.
