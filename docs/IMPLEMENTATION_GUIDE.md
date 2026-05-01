# PowerNAP Implementation Guide

Status: implementation-backed guide.

Last verified: 2026-04-30.

This guide is the contract for the local PowerNAP Free implementation. When code and guide disagree, either fix the code or update [Research References](RESEARCH_REFERENCES.md) with new evidence.

## 1. Product Contract

The target user story is:

```text
I run `powernap codex` at a coffee shop.
Codex starts a long active turn.
PowerNAP pre-arms closed-lid awake mode and active-turn network monitoring.
I close the laptop and get in a car.
While Codex is actively working, the Mac stays awake and PowerNAP moves the Mac side of networking toward iPhone tethering when Wi-Fi fails.
When Codex waits for input, asks for permission, finishes the turn, or exits, PowerNAP releases leases and the Mac can sleep.
```

The same contract applies to `powernap claude`. `powernap run -- <command>` supports generic commands but can only use process lifetime as the active signal unless the command emits compatible events.

## 2. Current Components

Implemented targets:

- `powernap`: CLI.
- `powernapd`: per-user daemon.
- `powernap-hook`: small command hook binary for Codex and Claude Code.
- `powernap-watchdog`: independent per-user watchdog.
- `PowerNAPCore`: config, IPC, state, hook normalization, hook installers.
- `PowerNAPPlatform`: IOKit power, CoreWLAN, Network.framework, SystemConfiguration-oriented helpers, Keychain, PTY.

Persistent state:

- Config: `~/Library/Application Support/PowerNAP/config.toml`
- SQLite: `~/Library/Application Support/PowerNAP/state.sqlite`
- Runtime socket and heartbeat: `$TMPDIR/PowerNAP/`
- Logs: `~/Library/Logs/PowerNAP/`

Install path:

- `./scripts/install.sh` copies release binaries to `/usr/local/bin` and runs `powernap install`.
- `powernap install` writes LaunchAgents for `powernapd` and `powernap-watchdog`.

## 3. Power Contract

### 3.1 Idle Sleep Assertion

PowerNAP uses `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep`.

This prevents idle sleep. It is not a lid-close solution by itself. Apple QA1340 distinguishes idle sleep from forced sleep and names lid close, Apple menu sleep, thermal emergency, and low battery as forced sleep cases. Apple also documents the user-idle assertion separately from forced sleep causes.

Required behavior:

- Acquire on active work.
- Release on waiting, turn-idle, done, error, process exit, safety cutoff, TTL expiration, watchdog cleanup, or `powernap restore`.
- Name assertions with `PowerNAP` and the run id.
- Show lease state through `powernap status` and `powernap leases`.

References:

- Apple QA1340: https://developer.apple.com/library/archive/qa/qa1340/_index.html
- Apple IOKit assertion doc: https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep
- Local SDK: `IOKit.framework/Headers/pwr_mgt/IOPMLib.h`

### 3.2 Clamshell Override

PowerNAP uses the IOKit root-domain user client path associated with `kPMSetClamshellSleepState`.

Verified facts:

- Local SDK headers define `kPMSetClamshellSleepState`.
- Apple XNU `RootDomainUserClient.cpp` dispatches `kPMSetClamshellSleepState` to `setClamShellSleepDisable(...)`.
- Apple XNU `IOPMrootDomain.cpp` uses clamshell sleep disable state in the lid-close policy path.
- This is a user-space IOKit call into macOS power management, not a kernel extension.

Required behavior:

- Pre-arm the clamshell override at active-turn start. Do not wait for lid close.
- Treat the override as global macOS state with no OS TTL.
- Pair it with a durable state record and an independent watchdog.
- Release it on waiting, turn-idle, done, error, safety cutoff, TTL expiration, stale daemon heartbeat, and manual restore.
- Do not run closed-lid QA until `powernap doctor --hardware-spike` passes.

References:

- Local SDK: `IOKit.framework/Headers/pwr_mgt/IOPMLibDefs.h`
- Local SDK: `IOKit.framework/Headers/pwr_mgt/IOPM.h`
- Apple XNU root-domain user client: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/iokit/Kernel/RootDomainUserClient.cpp
- Apple XNU root domain: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/iokit/Kernel/IOPMrootDomain.cpp

### 3.3 Watchdog

The clamshell override has no native expiration. PowerNAP therefore runs `powernap-watchdog` separately from `powernapd`.

Required behavior:

- `powernapd` writes heartbeat state while the clamshell override is held.
- Watchdog checks the heartbeat and clears stale clamshell state after `watchdog_release_after_seconds`.
- Watchdog clears PowerNAP-owned SQLite lease state as released.
- `powernap restore` also force-clears clamshell state.

Defaults:

- Heartbeat interval: 60 seconds.
- Watchdog release after: 180 seconds.

### 3.4 Safety Cutoffs

Release power leases when:

- Battery is below `min_battery_percent` and not charging.
- Battery is below `critical_battery_percent`.
- Thermal pressure is serious unless explicitly allowed, or critical always.
- Session heartbeat is stale.
- The wrapped process exits.
- The user runs `powernap restore`.

Defaults:

- `min_battery_percent = 20`
- `critical_battery_percent = 10`
- `max_closed_lid_minutes = 120`
- `active_lease_ttl_seconds = 1800`
- `waiting_grace_seconds = 20`

## 4. Agent Integration

PowerNAP normalizes agent-native hook events into:

```json
{
  "agent": "codex",
  "run_id": "uuid",
  "session_id": "agent-native-session-id",
  "turn_id": "optional",
  "phase": "active",
  "source_event": "UserPromptSubmit",
  "cwd": "/path",
  "tool_name": null
}
```

Normalized phases:

- `starting`
- `active`
- `waiting`
- `turn_idle`
- `done`
- `error`

Core mapping:

| Source event | Phase | Power action |
| --- | --- | --- |
| `SessionStart` | `starting` | Register session only |
| `UserPromptSubmit` | `active` | Acquire active leases |
| `PreToolUse` | `active` | Heartbeat/refresh active leases |
| `PostToolUse` | `active` | Heartbeat/refresh active leases |
| `PostToolUseFailure` | `active` | Agent can still continue |
| `PostToolBatch` | `active` | Agent can still continue |
| `PermissionRequest` | `waiting` | Release active leases |
| `Notification` | `waiting` | Release active leases |
| `Elicitation` | `waiting` | Release active leases |
| `ElicitationResult` | `active` | Resume active leases |
| `Stop` | `turn_idle` | Release active-turn leases, keep session registered |
| `TeammateIdle` | `turn_idle` | Release active-turn leases |
| `SessionEnd` | `done` | Release all leases |
| `StopFailure` | `error` | Release all leases |
| Process exit | `done` or `error` | Release all leases |

`Stop` is turn completion, not process exit. Treating `Stop` as terminal breaks interactive sessions.

### 4.1 Codex

Codex integration uses a global inert hook:

- PowerNAP installs a managed command hook in `~/.codex/hooks.json`.
- Existing hooks are preserved.
- Reinstall is idempotent.
- Uninstall removes only PowerNAP-managed hook groups.
- `~/.codex/config.toml` is updated to set `[features] codex_hooks = true`.
- Existing Codex hook/config files are backed up once as `.powernap.bak`.

The hook exits silently unless PowerNAP run environment variables are present:

- `POWERNAP_RUN_ID`
- `POWERNAP_HOOK_TOKEN`
- `POWERNAP_SOCKET`

Hook requirements:

- Timeout: 2 seconds.
- Exit `0` if daemon is unavailable.
- Emit no stdout.
- Parse only valid JSON hook payloads or explicit `POWERNAP_EVENT` synthetic events.
- Authenticate events with the per-run token.

References:

- OpenAI Codex hooks: https://developers.openai.com/codex/hooks
- OpenAI Codex config reference: https://developers.openai.com/codex/config-reference

### 4.2 Claude Code

Claude integration uses per-run settings overlays:

- `powernap claude` builds a temporary settings JSON overlay.
- It merges PowerNAP hook handlers with existing user settings.
- It launches `claude --settings <overlay> ...`.
- Overlay files are written under `~/Library/Caches/PowerNAP/claude-overlays/` and cleaned after the run.

Do not pass `--bare` to Claude Code. Claude local help says bare mode skips hooks.

Current Claude hook coverage includes `PermissionRequest`, `PermissionDenied`, `PostToolUseFailure`, `PostToolBatch`, `Elicitation`, `ElicitationResult`, `StopFailure`, and `TeammateIdle` in addition to the core lifecycle events.

References:

- Claude hooks: https://code.claude.com/docs/en/hooks
- Claude CLI reference: https://code.claude.com/docs/en/cli-reference
- Claude proxy docs: https://code.claude.com/docs/en/corporate-proxy

### 4.3 Generic Commands

`powernap run -- <command>` sends synthetic `SessionStart` and `UserPromptSubmit` events, treats the process lifetime as active, and releases on process exit. This is intentionally less precise because generic commands do not expose waiting/permission hooks.

## 5. Network Failover

Network failover is active-turn gated:

- `SessionStart` alone does not trigger failover.
- Active work adds the run id to the network active set.
- Waiting, turn-idle, done, or error removes the run id.
- When no active run remains, service order is restored.

Failover order:

1. Existing healthy primary path.
2. iPhone USB.
3. Configured Wi-Fi hotspot.
4. Apple Auto-Join Hotspot behavior if the OS exposes it.
5. Bluetooth PAN if `allow_bluetooth_pan = true` and macOS exposes a Bluetooth PAN network service.

PowerNAP must not mark failover as active merely because service order changed. Current code verifies route/probe state before reporting `failover-active = true`.

Health checks:

- Network.framework path status.
- Default route interface from `route -n get default`.
- HTTPS probes to configured endpoints, defaulting to:
  - `https://api.openai.com`
  - `https://chatgpt.com`
  - `https://api.anthropic.com`
  - `https://claude.ai`

Phone-side limitation:

- PowerNAP can manage the Mac side.
- It can prefer iPhone USB if the phone is plugged in and trusted.
- It can join known Wi-Fi SSIDs when available.
- It can prefer a Bluetooth PAN network service after the user has paired/connected the iPhone in macOS System Settings.
- It must not promise to silently turn on another device's Personal Hotspot via a documented public API.

References:

- Apple Personal Hotspot setup: https://support.apple.com/en-us/111785
- Apple Instant Hotspot/Auto-Join Hotspot: https://support.apple.com/en-us/109321
- Apple CoreWLAN: https://developer.apple.com/documentation/corewlan
- Apple NEHotspotConfigurationManager: https://developer.apple.com/documentation/networkextension/nehotspotconfigurationmanager
- Local `networksetup` and `route` man pages.

## 6. Proxy And Relay Boundary

Free local-only PowerNAP does not currently implement a proxy or VPN. This is intentional.

A local proxy would create two legs:

```text
agent -> 127.0.0.1 PowerNAP proxy -> OpenAI/Anthropic
```

If the Mac loses Wi-Fi, the upstream leg can break. The local loopback leg might remain open, but the proxy cannot preserve the same encrypted upstream TCP/TLS/WebSocket/SSE stream unless a stable remote endpoint owns that upstream connection or the proxy terminates and understands the provider protocol.

Future premium relay modes:

1. Stable egress proxy for new/retried requests.
2. Blind CONNECT relay that can keep some provider-facing sockets open during brief local outages.
3. Stream-aware API relay with opt-in payload visibility.
4. VPN/MASQUE/QUIC-style roaming tunnel.

Platform notes:

- Vercel is suitable for marketing/control plane, not the relay data plane.
- Cloudflare Workers can accept WebSockets and create outbound TCP sockets, but inbound direct TCP to Workers is not the general relay answer today.
- QUIC supports connection migration and is relevant for future tunnel work.

References:

- Vercel WebSocket Functions note: https://vercel.com/kb/guide/do-vercel-serverless-functions-support-websocket-connections
- Vercel limits: https://vercel.com/docs/limits
- Cloudflare Workers protocols: https://developers.cloudflare.com/workers/reference/protocols/
- Cloudflare TCP sockets: https://developers.cloudflare.com/workers/runtime-apis/tcp-sockets/
- Cloudflare Durable Object WebSockets: https://developers.cloudflare.com/durable-objects/best-practices/websockets/
- RFC 9000 QUIC: https://www.rfc-editor.org/rfc/rfc9000.html

## 7. Security Requirements

Local IPC:

- Unix domain socket only for hook-to-daemon traffic.
- Socket path under a user-owned private runtime directory.
- Per-run random token generated with Security.framework.
- Reject unknown `run_id` or invalid token.
- Never execute commands from hook payloads.

File permissions:

- App support, logs, and runtime directories are chmod `0700`.
- SQLite state files are chmod `0600`.
- Claude overlays are chmod `0600`.

Hooks:

- Treat hook JSON as untrusted.
- Missing PowerNAP env makes hooks inert.
- Malformed JSON is ignored fail-open and does not synthesize an active event.
- Hook timeout must stay short.
- Hook stdout must remain empty by default.

Secrets:

- Store hotspot credentials and future relay credentials in Keychain.
- Do not store OpenAI or Anthropic credentials.
- Do not log prompts, model output, API request bodies, or raw hook JSON by default.

## 8. Operational Commands

Primary:

```bash
powernap codex
powernap claude
powernap run -- <command>
powernap status
powernap doctor
powernap doctor --hardware-spike
powernap restore
```

Hook operations:

```bash
powernap hooks status
powernap hooks install
powernap hooks uninstall
powernap hooks clean
```

Network operations:

```bash
powernap network status
powernap network prefer-usb
powernap network prefer-bluetooth
powernap network restore
```

Install/uninstall:

```bash
powernap install
powernap uninstall
./scripts/install.sh
./scripts/uninstall.sh
```

## 9. Release Gates

Do not present the coffee-shop-to-car demo as reliable until all are true:

- `swift test` passes.
- `swift build -c release` passes.
- `powernap doctor` has no failures.
- `powernap doctor --hardware-spike` passes on the target Mac.
- `powernap restore` works with and without daemon IPC.
- Watchdog clears clamshell state after stale heartbeat.
- Active turns acquire idle and clamshell leases before lid close.
- Waiting, permission, turn-idle, done, error, and process exit release active leases.
- Codex and Claude hooks cannot block the agent if the daemon is down.
- Existing hooks are preserved.
- Network failover is attempted only during active turns.
- USB/hotspot failover is reported active only after route/probe verification.
- Service order restoration is verified.
- Docs and product copy state the free-mode stream-continuity boundary.
