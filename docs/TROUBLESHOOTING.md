# Troubleshooting

## First Response

If the Mac is being held awake unexpectedly:

```bash
powernap restore
powernap status
```

`restore` is intentionally safe to run repeatedly. It clears PowerNAP-owned power leases, force-clears the clamshell override, and marks open leases released.

## Daemon, Watchdog, Or Menu App Not Running

Check the LaunchAgents:

```bash
launchctl print gui/$(id -u)/dev.powernap.daemon
launchctl print gui/$(id -u)/dev.powernap.watchdog
launchctl print gui/$(id -u)/dev.powernap.menu
```

Reinstall or reload:

```bash
powernap install
```

Useful logs:

```bash
tail -f ~/Library/Logs/PowerNAP/powernapd.err.log
tail -f ~/Library/Logs/PowerNAP/watchdog.err.log
tail -f ~/Library/Logs/PowerNAP/menu.err.log
tail -f ~/Library/Logs/PowerNAP/powernapd.log
```

Run:

```bash
powernap doctor
```

If `doctor` appears stuck, use the bounded smoke-test form:

```bash
powernap doctor --check-timeout-seconds 2
```

This prevents agent CLI checks from waiting forever.

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

- The installed `/usr/local/bin/powernap` binary is stale after a source update.
- Codex hooks are not installed or `hooks` is disabled.
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
rg -n "hooks" ~/.codex/config.toml
```

Expected config:

```toml
[features]
hooks = true
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
