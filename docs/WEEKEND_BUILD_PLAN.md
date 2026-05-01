# Weekend Build Plan

Status: historical build roadmap. For current commands and guarantees, use
[Implementation Guide](IMPLEMENTATION_GUIDE.md) and [Setup Guide](SETUP.md).

Goal: build a local-only PowerNAP Free MVP that a developer can run on their own Mac for Codex and Claude Code.

The product demo must feel like this:

```text
Run `powernap codex` in a coffee shop.
Start a long Codex turn.
Close the laptop.
Get in a Waymo.
PowerNAP keeps the Mac awake, moves networking to tethering when Wi-Fi dies, and releases active leases when Codex is waiting, turn-idle, or exited.
```

This plan is intentionally scoped. It avoids hosted relay, VPN, kernel extensions, and TLS MITM.

## Team Shape

Recommended team for a weekend:

- Engineer 1: macOS power manager and daemon.
- Engineer 2: agent hooks and CLI wrapper.
- Engineer 3: network manager and tether failover.
- Engineer 4: QA, docs, packaging, and safety testing.

If fewer people are available:

- Prioritize power manager, hook adapter, and `restore`.
- Ship network failover as `doctor` plus iPhone USB service switching with route/probe verification.
- Defer local proxy to the next iteration.

## Stack Recommendation

Fastest path on macOS:

- Swift for daemon, macOS APIs, and optional menu bar later.
- Swift ArgumentParser for CLI.
- SQLite for state.
- XPC or Unix domain socket for local IPC.
- Shell out to `networksetup` only where SystemConfiguration/CoreWLAN would slow the weekend.

Alternative:

- Rust for CLI/daemon/proxy.
- Small Swift helper for macOS-only APIs.

Recommended weekend choice:

- Use Swift for v0 because power, Keychain, Network.framework, SystemConfiguration, and CoreWLAN are all native.

## Day 0: Repo And Spike

Deliverables:

- Buildable Swift package or Xcode project.
- `powernap --help`.
- `powernapd` launched manually.
- `powernap restore` stub.
- Clamshell override spike in a throwaway command.
- Clamshell watchdog spike that clears the override after missed heartbeat.
- Idle assertion spike.
- Network service discovery spike.

Acceptance:

- Can build locally.
- Can run `powernap status`.
- Can acquire and release idle assertion.
- Can list Wi-Fi and iPhone USB services.
- Can prove whether clamshell override call works on target macOS.
- Can prove clamshell override is cleared by watchdog if the daemon stops heartbeating.

## Day 1: Power And Session Core

Build:

- SQLite state store.
- Lease model.
- Daemon IPC.
- Idle assertion manager.
- Clamshell override manager.
- Independent clamshell watchdog.
- Safety policy.
- `powernap restore`.
- Fake agent command:

```bash
powernap run -- ./scripts/fake-agent.sh
```

Fake agent should emit hook events:

- SessionStart
- UserPromptSubmit
- PreToolUse
- PostToolUse
- PermissionRequest
- Stop

Acceptance:

- Active event acquires idle assertion.
- Active event acquires clamshell override immediately, before the lid closes.
- Waiting event releases clamshell override.
- Stop releases active-turn leases but keeps the session registered as waiting/turn-idle.
- Process exit releases everything and marks the session done/error.
- TTL expiration releases everything.
- `powernap restore` releases everything.
- Killing daemon and restarting releases stale leases.
- Missed watchdog heartbeat clears clamshell override.

## Day 2: Codex And Claude Hooks

Build:

- `powernap-hook` executable.
- Hook event parser.
- Normalized event model.
- Hook timeout handling.
- Codex hook installer:
  - Add global inert hook.
  - Preserve existing hooks.
  - Uninstall only PowerNAP-managed hook.
- Claude hook installer:
  - Prefer per-run temp settings file for wrapped sessions.
  - Provide global install only as explicit option.
- `powernap codex`.
- `powernap claude`.
- PTY/tmux session handling.

Acceptance:

- Normal Codex outside PowerNAP is unaffected.
- `powernap codex` receives hook events.
- `powernap claude` receives hook events.
- Permission/waiting releases power leases.
- Stop maps to waiting/turn-idle and releases active-turn leases.
- Process exit releases power leases.
- Existing user hooks are preserved.
- Hook command exits `0` if `powernapd` is unavailable.
- Hook command timeout is short, for example 2 seconds.
- Hook emits no stdout unless explicitly required by the agent integration.

## Day 3: Network Failover

Build:

- Network health monitor.
- Probe endpoints.
- iPhone USB detection.
- Service order snapshot.
- Prefer iPhone USB during active turn.
- Default route/interface verification.
- HTTPS probe verification on the selected interface.
- Restore service order after turn.
- Known hotspot config flow:

```bash
powernap config edit
```

- Keychain storage for hotspot password.
- `powernap doctor` checks.

Acceptance:

- With Wi-Fi healthy, no change.
- With active turn and Wi-Fi failed, iPhone USB is preferred if present.
- iPhone USB failover is not marked successful until default route and HTTPS probes verify it.
- With active turn and iPhone USB absent, known hotspot join is attempted if configured.
- Hotspot failover is not marked successful until route and HTTPS probes verify it.
- When turn stops, original network order is restored.
- When waiting, network failover stops.
- `doctor` clearly explains missing setup.

## Day 4: Hardening And Demo

Build:

- Logs.
- Status output.
- Install/uninstall scripts.
- Safety messages.
- Manual test checklist.
- README for local install.

Demo:

1. Start on Wi-Fi.
2. Run `powernap codex`.
3. Submit a long task.
4. Verify status shows active power leases and clamshell pre-armed.
5. Close lid.
6. Disable Wi-Fi or leave Wi-Fi range.
7. Verify iPhone USB or hotspot becomes active and route/probes use it.
8. Let agent finish.
9. Verify PowerNAP releases leases.
10. Verify Mac can sleep.

## MVP Command Behavior

### `powernap codex`

Expected:

- Starts daemon if needed.
- Ensures hook is installed or prompts with install instruction.
- Starts Codex in PTY.
- Registers session.
- Streams status events to daemon.
- On active turn, pre-arms closed-lid mode before lid close.

### `powernap claude`

Expected:

- Starts daemon if needed.
- Builds temp Claude settings file with PowerNAP hook.
- Starts Claude in PTY.
- Registers session.
- On active turn, pre-arms closed-lid mode before lid close.

### `powernap run -- <command>`

Expected:

- Starts any command.
- Treats process lifetime as active unless configured otherwise.
- Releases on exit.

### `powernap status`

Expected:

- Shows daemon state.
- Shows active sessions.
- Shows power leases.
- Shows safety.
- Shows network state.

### `powernap restore`

Expected:

- Always safe to run.
- Releases all PowerNAP-owned assertions.
- Clears clamshell override.
- Stops clamshell watchdog.
- Restores network order.
- Stops local proxy.
- Marks leases released.

## Engineering Task Breakdown

### PowerManager Tasks

- Implement idle assertion wrapper.
- Implement clamshell override spike.
- Wrap clamshell override in lease API.
- Add TTL watchdog.
- Add independent clamshell watchdog heartbeat and cleanup.
- Add battery threshold.
- Add thermal pressure threshold.
- Add crash restore on daemon start.

### Agent Tasks

- Define normalized hook JSON schema.
- Implement hook executable.
- Make hook timeout short and non-blocking.
- Implement Codex hook installer.
- Implement Claude temp settings generator.
- Implement run wrappers.
- Implement PTY/tmux support.
- Implement process supervision.

### Network Tasks

- Implement `NWPathMonitor`.
- Implement DNS/HTTPS probes.
- Discover network services.
- Detect iPhone USB service.
- Snapshot service order.
- Temporarily prefer iPhone USB.
- Verify actual default route/interface after switching.
- Verify agent-relevant HTTPS probes after switching.
- Restore order.
- Implement known hotspot join.
- Store credentials in Keychain.

### UX Tasks

- Implement `doctor`.
- Implement status formatting.
- Implement logs.
- Write setup guide.
- Write uninstall guide.
- Write troubleshooting guide.

## Safety Checklist

Before any closed-lid test:

- `powernap restore` works.
- TTL watchdog works.
- Independent clamshell watchdog works.
- Battery threshold works.
- Daemon restart restore works.
- Logs show exactly when clamshell override is enabled.
- Status shows clamshell override is pre-armed before closing the lid.

Before any network-order test:

- Snapshot is stored.
- Restore works.
- Route/probe verification is implemented.
- Manual restore command is documented.

Before any hook install test:

- Existing hook file is backed up.
- Existing hooks are preserved.
- Uninstall removes only PowerNAP hook.
- Hook cannot block the agent if PowerNAP is down.

## Definition Of Done For Weekend MVP

Power:

- Active turn keeps Mac awake.
- Active turn pre-arms closed-lid mode before lid close.
- Waiting/turn-idle/done releases awake state.
- Closed-lid mode works on target Mac.
- Restore works.

Agent:

- Codex works.
- Claude Code works.
- Generic run works.

Network:

- iPhone USB failover works.
- Known hotspot attempt works.
- Route and HTTPS probes verify successful failover.
- Restore works.

Safety:

- TTL works.
- Battery cutoff works.
- Daemon crash recovery works.
- Watchdog recovery works if the daemon stops heartbeating.

Docs:

- Setup guide.
- Doctor guide.
- Known limitations.
- Premium relay future plan.

## Cut List If Weekend Slips

Cut in this order:

1. Local proxy.
2. Bluetooth PAN.
3. Wi-Fi hotspot auto-join.
4. Menu bar UI.
5. Premium relay stubs.
6. Advanced per-process data usage.

Do not cut:

- `restore`.
- TTL.
- Waiting/done release.
- Hook preservation.
- Explicit limitation messaging.
