# Setup Guide

## Prerequisites

- macOS 13 or later.
- Apple Silicon is the primary tested target.
- Xcode Command Line Tools: `xcode-select --install`.
- Codex and/or Claude Code installed if you want first-class hooks.

## Build

```bash
swift build -c release
```

The release artifacts are in `.build/release/`:

- `powernap`
- `powernapd`
- `powernap-hook`
- `powernap-menu`
- `powernap-watchdog`

## Install

The easiest install path is:

```bash
./scripts/install.sh
```

The script builds release artifacts, copies all five binaries to `/usr/local/bin`, and runs:

```bash
powernap install
```

`powernap install` writes and bootstraps these per-user LaunchAgents:

- `~/Library/LaunchAgents/dev.powernap.daemon.plist`
- `~/Library/LaunchAgents/dev.powernap.watchdog.plist`
- `~/Library/LaunchAgents/dev.powernap.menu.plist`

The daemon, watchdog, and menu bar companion run as the current user, not root.

## Configure Hooks

Install Codex hooks:

```bash
powernap hooks install
```

This writes a PowerNAP-managed command hook to `~/.codex/hooks.json` and enables:

```toml
[features]
hooks = true
```

The hook is inert outside a PowerNAP-wrapped run. It exits immediately unless `POWERNAP_RUN_ID`, `POWERNAP_HOOK_TOKEN`, and `POWERNAP_SOCKET` are present.

Claude Code does not need a global install. `powernap claude` creates a temporary per-run settings overlay and passes it via `claude --settings <overlay>`. Do not pass `--bare` to Claude Code; Claude documents and local help confirms that `--bare` skips hooks.

## Verify

Run the non-invasive checks:

```bash
powernap doctor
```

If `doctor` is being used as a fast smoke test, bound subprocess checks:

```bash
powernap doctor --check-timeout-seconds 2
```

Before closing the lid for real QA, run the explicit hardware spike:

```bash
powernap doctor --hardware-spike
```

The hardware spike briefly enables and immediately clears the clamshell override. Do not start closed-lid testing until this passes and the watchdog LaunchAgent is loaded.

Useful checks:

```bash
powernap status
powernap hooks status
launchctl print gui/$(id -u)/dev.powernap.daemon
launchctl print gui/$(id -u)/dev.powernap.watchdog
launchctl print gui/$(id -u)/dev.powernap.menu
```

The menu bar icon uses a bolt while PowerNAP is blocking sleep, a moon when normal sleep is allowed, and a question mark when daemon status is unavailable. The number beside the icon is the count of active protected agent threads keeping the Mac awake.

## Run

Codex:

```bash
powernap codex
```

Claude Code:

```bash
powernap claude
```

Generic command:

```bash
powernap run -- ./long-running-agent
```

Codex and Claude wrappers acquire protection immediately, then agent hooks refine the state when a turn waits, idles, finishes, or exits. Generic mode treats the process lifetime as active because it has no agent-native waiting hooks.

## Restore

If anything looks wrong:

```bash
powernap restore
```

`restore` asks the daemon to release PowerNAP-owned leases and clear the clamshell override. If the daemon is unavailable, the CLI performs a local safety restore from the state database.

## Configuration

PowerNAP config lives at:

```text
~/Library/Application Support/PowerNAP/config.toml
```

Important defaults:

```toml
[power]
closed_lid_enabled = true
idle_sleep_assertion = true
max_closed_lid_minutes = 120
release_when_waiting = true
prearm_clamshell_on_active = true

[safety]
min_battery_percent = 20
critical_battery_percent = 10
allow_on_battery = true
allow_thermal_serious = false
watchdog_heartbeat_seconds = 60
watchdog_release_after_seconds = 180
active_lease_ttl_seconds = 1800
waiting_grace_seconds = 20
```

Runtime paths can be overridden for tests:

- `POWERNAP_RUNTIME_DIR`
- `POWERNAP_APP_SUPPORT_DIR`
- `POWERNAP_LOGS_DIR`
