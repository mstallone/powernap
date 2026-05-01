# Setup Guide

## Prerequisites

- macOS 13 or later.
- Apple Silicon is the primary tested target.
- Xcode Command Line Tools: `xcode-select --install`.
- Codex and/or Claude Code installed if you want first-class hooks.
- For the coffee-shop-to-car demo, set up at least one phone fallback:
  - Preferred: iPhone USB connected, trusted by the Mac, with Personal Hotspot available.
  - Optional: a known iPhone hotspot SSID configured in PowerNAP.
  - Optional: Apple Auto-Join Hotspot. Apple documents fully automatic Mac joining as available on macOS Tahoe 26 or later, so do not rely on it for older macOS targets.

## Build

```bash
swift build -c release
```

The release artifacts are in `.build/release/`:

- `powernap`
- `powernapd`
- `powernap-hook`
- `powernap-watchdog`

## Install

The easiest install path is:

```bash
./scripts/install.sh
```

The script builds release artifacts, copies all four binaries to `/usr/local/bin`, and runs:

```bash
powernap install
```

`powernap install` writes and bootstraps these per-user LaunchAgents:

- `~/Library/LaunchAgents/dev.powernap.daemon.plist`
- `~/Library/LaunchAgents/dev.powernap.watchdog.plist`

The daemon and watchdog run as the current user, not root.

## Configure Hooks

Install Codex hooks:

```bash
powernap hooks install
```

This writes a PowerNAP-managed command hook to `~/.codex/hooks.json` and enables:

```toml
[features]
codex_hooks = true
```

The hook is inert outside a PowerNAP-wrapped run. It exits immediately unless `POWERNAP_RUN_ID`, `POWERNAP_HOOK_TOKEN`, and `POWERNAP_SOCKET` are present.

Claude Code does not need a global install. `powernap claude` creates a temporary per-run settings overlay and passes it via `claude --settings <overlay>`. Do not pass `--bare` to Claude Code; Claude documents and local help confirms that `--bare` skips hooks.

## Verify

Run the non-invasive checks:

```bash
powernap doctor
```

If `doctor` is being used as a fast smoke test, skip outbound probes and bound subprocess checks:

```bash
powernap doctor --skip-network-probes --check-timeout-seconds 2
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
powernap network status
launchctl print gui/$(id -u)/dev.powernap.daemon
launchctl print gui/$(id -u)/dev.powernap.watchdog
```

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

Generic mode treats the process lifetime as active because it has no agent-native waiting hooks.

## Restore

If anything looks wrong:

```bash
powernap restore
```

`restore` asks the daemon to release PowerNAP-owned leases, clear the clamshell override, and restore the saved network service order. If the daemon is unavailable, the CLI performs a local safety restore from the state database.

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

[network]
enabled = true
allow_cellular = true
prefer_usb_tether = true
allow_wifi_hotspot = true
allow_bluetooth_pan = false
restore_service_order = true
keep_tether_until_turn_done = true
max_cellular_mb_per_session = 2048
```

For an iPhone Bluetooth Personal Hotspot path, pair/connect the iPhone in macOS System Settings first so macOS exposes a `Bluetooth PAN` network service. Then set:

```toml
[network]
enabled = true
prefer_usb_tether = false
allow_wifi_hotspot = false
allow_bluetooth_pan = true
restore_service_order = true
```

Manual test:

```bash
powernap network prefer-bluetooth
powernap network status
powernap network restore
```

Runtime paths can be overridden for tests:

- `POWERNAP_RUNTIME_DIR`
- `POWERNAP_APP_SUPPORT_DIR`
- `POWERNAP_LOGS_DIR`
