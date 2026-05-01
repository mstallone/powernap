# PowerNAP System Plan

Status: architecture summary. The implementation contract is [Implementation Guide](IMPLEMENTATION_GUIDE.md); source evidence is [Research References](RESEARCH_REFERENCES.md).

Last verified: 2026-04-30.

## Product Story

PowerNAP exists for one concrete workflow:

```text
Run `powernap codex` in a coffee shop.
Start a long active turn.
Close the laptop.
Get in a car.
PowerNAP keeps the Mac awake while the agent is actually working, moves Mac-side networking toward phone tethering when Wi-Fi fails, and releases everything when the agent waits or exits.
```

The same architecture supports `powernap claude` and generic `powernap run -- <command>`.

## Free Product Boundary

PowerNAP Free is local-only. It can:

- Hold macOS idle assertions.
- Pre-arm and clear the IOKit clamshell override.
- Watch daemon heartbeats from a separate watchdog.
- Detect agent active/waiting/idle/done/error phases through hooks.
- Keep the wrapped process attached through PTY/session supervision.
- Prefer iPhone USB or a configured hotspot during active turns.
- Restore power and network state when work is no longer active.

PowerNAP Free cannot guarantee exact in-flight model stream continuity across a hard network transition. Local recovery can keep the process alive and make retries work quickly; a stable remote relay is required for stronger continuity.

## Core Architecture

```text
powernap CLI
  |
  | Unix domain socket + per-run token
  v
powernapd LaunchAgent
  |-- Hook event ingestor
  |-- Lease manager
  |-- IOKit idle assertion manager
  |-- IOKit clamshell override manager
  |-- Network orchestrator
  |-- PTY/process supervisor
  |-- SQLite state store
  |
  | heartbeat + SQLite state
  v
powernap-watchdog LaunchAgent
```

`powernap-hook` is launched by Codex/Claude hooks and sends normalized events to `powernapd`. It is inert outside PowerNAP because it requires run-specific environment variables.

## Power Strategy

Use both:

1. `kIOPMAssertionTypePreventUserIdleSystemSleep` for ordinary idle sleep.
2. `kPMSetClamshellSleepState` through the IOKit root-domain user client for lid-close behavior.

The clamshell override is global OS state, so PowerNAP treats it as a short-lived lease owned by policy, not as a permanent setting:

- Acquire only during active work.
- Release on waiting, idle, done, error, process exit, safety cutoff, restore, or stale heartbeat.
- Keep an independent watchdog.
- Require `powernap doctor --hardware-spike` before physical closed-lid QA.

## Agent Strategy

Normalize agent events into phases:

- `starting`
- `active`
- `waiting`
- `turn_idle`
- `done`
- `error`

Codex:

- Global inert hook in `~/.codex/hooks.json`.
- Preserve existing hooks.
- Enable `[features] codex_hooks = true`.
- Short timeout and no stdout.

Claude Code:

- Per-run settings overlay via `claude --settings`.
- No global mutation.
- Do not use `--bare` because it skips hooks.

Generic:

- Process lifetime is active by default.

## Network Strategy

Failover is active-turn gated. PowerNAP does not change service order just because a wrapped agent session exists; it waits for an active work signal.

Failover order:

1. Existing healthy route.
2. iPhone USB service.
3. Configured Wi-Fi hotspot.
4. OS Auto-Join Hotspot behavior when available.

Success requires route and HTTPS probe verification. Service-order mutation alone is not enough.

PowerNAP can manage the Mac side of tethering. It cannot silently activate Personal Hotspot on another device through documented public APIs.

## Future Premium Relay

Premium adds a stable remote endpoint:

```text
agent -> local PowerNAP proxy -> roaming tunnel -> hosted relay -> OpenAI/Anthropic
```

Possible modes:

1. Stable egress for new/retried requests.
2. Blind CONNECT relay that keeps provider-facing sockets alive during brief local outages.
3. Stream-aware relay with explicit privacy tradeoffs.
4. VPN/MASQUE/QUIC-style tunnel.

Vercel is not the relay data plane. Use a VPS/Fly/Hetzner/DigitalOcean-style service first; evaluate Cloudflare Workers/Durable Objects later where their WebSocket/outbound TCP model fits.

## Release Gates

- Unit/integration tests pass.
- Release build passes.
- `powernap doctor` passes.
- `powernap doctor --hardware-spike` passes on the target Mac.
- `powernap restore` works with daemon IPC and local fallback.
- Watchdog clears stale clamshell state.
- Active turns acquire power leases before lid close.
- Waiting/permission/idle/done/error states release leases.
- Network failover is attempted only during active turns.
- Failover is marked active only after route/probe verification.
- Docs clearly state the free-mode network continuity boundary.
