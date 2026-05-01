# Manual QA Runbook

Run this before any closed-lid demo. Do not skip `restore`, watchdog, or hook tests.

## T1: Build And Install

Steps:

1. `swift test`
2. `swift build -c release`
3. `./scripts/install.sh`
4. `powernap doctor`

Pass criteria:

- Tests and release build pass.
- `powernap doctor` has no failures.
- Daemon and watchdog LaunchAgents are loaded.

## T2: Hardware Spike

Steps:

1. `powernap doctor --hardware-spike`
2. `powernap restore`

Pass criteria:

- Idle assertion creation/release passes.
- Clamshell override enables and clears.
- Restore completes even after the spike.

## T3: Codex Hook Idempotency

Steps:

1. Back up any personal Codex hook config.
2. `powernap hooks install`
3. Record checksum of `~/.codex/hooks.json`.
4. `powernap hooks install`
5. Compare checksum and inspect `~/.codex/config.toml`.

Pass criteria:

- Existing user hooks are preserved.
- PowerNAP hook is not duplicated.
- `[features] codex_hooks = true` is present.

## T4: Claude Overlay

Steps:

1. `powernap claude --version`
2. Check `~/Library/Caches/PowerNAP/claude-overlays/` during a run.
3. Let the command exit.

Pass criteria:

- PowerNAP passes `--settings` overlay.
- Overlay is cleaned after the run.
- Do not pass `--bare`.

## T5: Active Lease Acquisition And Release

Steps:

1. Start `powernap codex`.
2. Submit a prompt that runs for at least 60 seconds.
3. In another terminal, run `powernap status`.
4. Wait for the turn to stop or ask for input.
5. Run `powernap status` again.

Pass criteria:

- Active turn shows active session and power leases.
- Waiting/turn-idle state releases clamshell and idle assertions.
- `Stop` is treated as turn-idle, not process exit.

## T6: Generic Command Mode

Steps:

1. `powernap run -- /bin/sleep 10`
2. During the sleep, run `powernap status`.
3. After exit, run `powernap status`.

Pass criteria:

- Process lifetime is treated as active.
- Exit releases all leases.

## T7: Closed-Lid Active Turn

Setup:

- Physical MacBook.
- Hardware spike passed.
- Battery and thermal checks pass.
- Watchdog LaunchAgent loaded.

Steps:

1. Start a long active turn with `powernap codex` or `powernap claude`.
2. Verify `powernap status` shows active leases.
3. Close the lid for 30-60 seconds.
4. Reopen the lid.
5. Run `powernap status`.

Pass criteria:

- The process is still alive.
- The active turn did not sleep solely because of lid close.
- Leases are released when the turn becomes idle or waiting.

## T8: Watchdog Recovery

Steps:

1. Start an active turn and verify clamshell lease state.
2. Stop `powernapd` with `launchctl bootout gui/$(id -u)/dev.powernap.daemon`.
3. Wait longer than `watchdog_release_after_seconds`.
4. Run `powernap restore`.
5. Restart with `powernap install`.

Pass criteria:

- Watchdog clears stale clamshell state.
- Restore is safe after daemon loss.
- Reinstall returns daemon/watchdog to healthy state.

## T9: Network USB Failover

Setup:

- Wi-Fi connected.
- iPhone connected by USB and trusted.
- iPhone USB service visible in `networksetup -listnetworkserviceorder`.

Steps:

1. Start an active agent turn.
2. Disable Wi-Fi or leave Wi-Fi range.
3. Run `powernap network status`.
4. Run `route -n get default`.

Pass criteria:

- PowerNAP only attempts failover while the turn is active.
- iPhone USB is moved ahead of Wi-Fi.
- `failover-active` becomes true only after route/probe verification.
- Service order is restored when the turn becomes waiting, idle, done, or after `powernap restore`.

## T10: Network Hotspot Fallback

Setup:

- No iPhone USB service.
- A known hotspot is configured in PowerNAP/Keychain.
- Hotspot is visible or Auto-Join Hotspot can expose it.

Steps:

1. Start an active agent turn.
2. Make primary Wi-Fi unavailable.
3. Watch `powernap network status`.

Pass criteria:

- PowerNAP attempts configured hotspot join.
- Success is not reported until probes pass.
- Documentation and UI do not claim PowerNAP can silently enable phone-side hotspot.

## T11: Emergency Restore

Steps:

1. During any active test, run `powernap restore`.
2. Run `powernap status`.
3. Run `networksetup -listnetworkserviceorder`.

Pass criteria:

- Clamshell override is cleared.
- Open leases are marked released.
- Network service order is restored from snapshot if one exists.
- Command succeeds even if daemon IPC is unavailable.
