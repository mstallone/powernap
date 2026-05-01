# PowerNAP

PowerNAP is a macOS CLI and per-user daemon for long-running AI coding agent sessions. The target workflow is:

```bash
powernap codex
```

You start a long Codex or Claude Code turn at a coffee shop, close the MacBook, get in a car, and do nothing else. While the agent is actively working, PowerNAP holds macOS power leases and tries to move networking from Wi-Fi to phone tethering. When the agent finishes the turn, asks for input, waits for permission, or exits, PowerNAP releases the leases so macOS can sleep normally.

## What It Guarantees

PowerNAP Free controls only the local Mac:

- Prevents idle sleep and pre-arms the closed-lid clamshell override during active agent work.
- Releases power leases when hooks report waiting, turn-idle, done, or error states.
- Runs `powernapd` and `powernap-watchdog` as per-user LaunchAgents.
- Uses Codex and Claude Code hooks through an agent-agnostic normalized event model.
- Prefers iPhone USB tethering, then configured Wi-Fi hotspots, only while an agent turn is active.
- Restores network service order and power state on idle, exit, daemon restore, or manual `powernap restore`.

PowerNAP Free does not guarantee that an already-open OpenAI or Anthropic stream survives a hard network break. A local-only proxy cannot preserve the upstream TCP/TLS/WebSocket/SSE connection after the Mac loses its network path. Exact stream continuity needs a remote relay or application-aware resume.

## Quick Start

```bash
swift build -c release
./scripts/install.sh
powernap hooks install
powernap doctor
powernap doctor --hardware-spike
powernap codex
```

`powernap doctor --hardware-spike` briefly enables and clears the clamshell override. Run it before real closed-lid QA.

## Commands

- `powernap codex [args...]`: Run Codex with PowerNAP protection.
- `powernap claude [args...]`: Run Claude Code with PowerNAP protection.
- `powernap run -- <command> [args...]`: Protect a generic command for its process lifetime.
- `powernap status [--json]`: Show daemon, session, lease, safety, and network state.
- `powernap doctor [--hardware-spike]`: Diagnose install, hooks, safety, and network readiness.
- `powernap restore`: Clear PowerNAP leases, clamshell state, and network service order.
- `powernap hooks install|status|uninstall|clean`: Manage Codex hooks and Claude overlays.
- `powernap network status|prefer-usb|prefer-bluetooth|restore`: Inspect or manually request network failover behavior.
- `powernap logs`, `powernap leases`, `powernap config`, `powernap install`, `powernap uninstall`.

## Documentation

- [Setup Guide](docs/SETUP.md)
- [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md)
- [Research References](docs/RESEARCH_REFERENCES.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Manual QA](docs/MANUAL_QA.md)
- [Uninstallation](docs/UNINSTALL.md)
- [System Plan](docs/SYSTEM_PLAN.md)

## Current Local Verification

Last verified on 2026-04-30:

- macOS 26.4.1 arm64.
- Codex CLI 0.128.0 with `codex_hooks` stable/enabled and `prevent_idle_sleep` experimental/enabled.
- Claude Code 2.1.105 with `--settings` and `--include-hook-events`.
- Network services: Wi-Fi `en0`, iPhone USB `en8`, Thunderbolt Bridge, ProtonVPN.

See [Research References](docs/RESEARCH_REFERENCES.md) for source-backed claims and links.
