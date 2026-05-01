# Troubleshooting

## First Response

If the Mac is being held awake unexpectedly or network order looks wrong:

```bash
powernap restore
powernap status
```

`restore` is intentionally safe to run repeatedly. It clears PowerNAP-owned power leases, force-clears the clamshell override, marks open leases released, and restores the most recent network service order snapshot if one exists.

## Daemon Or Watchdog Not Running

Check the LaunchAgents:

```bash
launchctl print gui/$(id -u)/dev.powernap.daemon
launchctl print gui/$(id -u)/dev.powernap.watchdog
```

Reinstall or reload:

```bash
powernap install
```

Useful logs:

```bash
tail -f ~/Library/Logs/PowerNAP/powernapd.err.log
tail -f ~/Library/Logs/PowerNAP/watchdog.err.log
tail -f ~/Library/Logs/PowerNAP/powernapd.log
```

Run:

```bash
powernap doctor
```

If `doctor` appears stuck, use the bounded smoke-test form:

```bash
powernap doctor --skip-network-probes --check-timeout-seconds 2
```

This skips outbound HTTPS probes and prevents agent CLI checks from waiting forever.

Failures from `daemon ipc` mean `powernap codex` and `powernap claude` should not continue; the wrapper is designed to fail closed instead of running an unprotected session.

## Mac Sleeps When The Lid Closes

PowerNAP holds closed-lid state only during an active agent turn. It deliberately releases that state when the agent is waiting for input, waiting for permission, turn-idle, done, or errored.

Check:

```bash
powernap status
powernap leases
powernap doctor --hardware-spike
```

Common causes:

- The agent has not emitted `UserPromptSubmit` or another active hook yet.
- Codex hooks are not installed or `codex_hooks` is disabled.
- Claude was launched with `--bare`, which skips hooks.
- Battery or thermal policy released the lease.
- The watchdog found a stale heartbeat and cleared the clamshell override.
- The daemon is not reachable.

Apple documents ordinary idle assertions separately from forced sleep. Closing the lid is a forced sleep path, so a normal `caffeinate`-style idle assertion is not enough by itself.

## Codex Hooks Not Firing

Check:

```bash
powernap hooks status
cat ~/.codex/hooks.json
rg -n "codex_hooks" ~/.codex/config.toml
```

Expected config:

```toml
[features]
codex_hooks = true
```

The PowerNAP Codex hook should emit no stdout and should exit `0` if the daemon is unavailable. To debug hook parse/send failures:

```bash
POWERNAP_HOOK_DEBUG=1 powernap codex
```

Normal Codex sessions outside PowerNAP should be unaffected because the hook exits unless PowerNAP run environment variables are present.

## Claude Hooks Not Firing

`powernap claude` passes a per-run settings overlay with `--settings`. Check:

```bash
powernap hooks status
ls ~/Library/Caches/PowerNAP/claude-overlays/
claude --help | rg -- "--settings|--include-hook-events|--bare"
```

Do not use `--bare` with PowerNAP. Claude Code help says bare mode skips hooks, which defeats active/waiting detection.

## Network Does Not Move To iPhone USB

PowerNAP only attempts automatic failover while at least one wrapped agent run is active. It restores service order when all active turns become waiting, idle, done, or error.

Check the Mac side:

```bash
networksetup -listnetworkserviceorder
powernap network status
powernap doctor
```

For USB tethering:

- Connect the iPhone by USB.
- Tap Trust on the iPhone if prompted.
- Ensure Personal Hotspot is available in iPhone Settings or through your carrier plan.
- Confirm macOS shows an `iPhone USB` network service.

For Wi-Fi hotspot fallback:

- The hotspot must already be available or exposed through Apple Instant Hotspot/Auto-Join behavior.
- PowerNAP can join a configured SSID from the Mac side.
- PowerNAP cannot silently enable another device's Personal Hotspot through a documented public API.

For Bluetooth fallback:

- Pair/connect the iPhone from macOS System Settings first.
- Confirm `networksetup -listallnetworkservices` shows `Bluetooth PAN`.
- Set `allow_bluetooth_pan = true`.
- If you want Bluetooth instead of USB/Wi-Fi hotspot, set `prefer_usb_tether = false` and `allow_wifi_hotspot = false`.
- Test with `powernap network prefer-bluetooth`.

`failover-active` means PowerNAP has verified the route/probe state, not merely changed service order.

## Agent Stream Broke After Moving Networks

This is expected in free local-only mode. When the Mac leaves Wi-Fi, the upstream TCP/TLS/WebSocket/SSE connection to OpenAI or Anthropic can break. PowerNAP keeps the process alive, recovers a network path, and lets the agent retry if the agent/provider can recover.

Exact in-flight stream continuity requires a future remote relay or application-aware resume layer.

## Uninstall

Clean hooks first if desired:

```bash
powernap hooks uninstall
```

Then unload agents and remove binaries:

```bash
./scripts/uninstall.sh
```

State and logs are preserved unless removed manually.
