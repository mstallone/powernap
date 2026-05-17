# PowerNAP

PowerNAP keeps long-running AI coding agent sessions alive on macOS while they are actively working, then gets out of the way when they stop.

It is built for workflows like:

```bash
powernap codex
```

Start a long Codex or Claude Code turn, close the MacBook, and let the agent continue. PowerNAP holds macOS power leases only while protected work is active. When the agent waits for input, asks for permission, finishes, errors, or exits, PowerNAP releases its leases so the Mac can sleep normally.

## What You Get

- `powernap`: CLI wrapper for Codex, Claude Code, and generic long-running commands.
- `powernapd`: per-user daemon that tracks protected sessions and owns power leases.
- `powernap-hook`: small fail-open hook binary for Codex and Claude Code events.
- `powernap-watchdog`: independent cleanup process for stale closed-lid state.
- `powernap-menu`: menu bar companion that shows whether PowerNAP is blocking sleep and how many active protected threads are keeping the Mac awake.

PowerNAP is local-only. Its job is power/session safety on this Mac.

## Requirements

- macOS 13 or later.
- Xcode Command Line Tools.
- Codex and/or Claude Code if you want first-class agent hooks.

Apple Silicon is the primary tested target.

## Install

```bash
swift build -c release
./scripts/install.sh
powernap hooks install
powernap doctor
powernap doctor --hardware-spike
```

`scripts/install.sh` builds release binaries, copies them to `/usr/local/bin`, installs shell aliases in `~/.zshrc`, and installs three per-user LaunchAgents:

- `dev.powernap.daemon`
- `dev.powernap.watchdog`
- `dev.powernap.menu`

The hardware spike briefly enables and clears the closed-lid override. Run it before relying on closed-lid behavior.

## Use

After opening a new shell, run Codex under PowerNAP:

```bash
codex
```

For the current shell, load the aliases immediately:

```bash
source ~/.zshrc
```

Run Claude Code under PowerNAP:

```bash
claude
```

Protect a generic process for its lifetime:

```bash
powernap run -- ./long-running-agent
```

Codex and Claude wrappers acquire protection immediately, then agent hooks refine the state when a turn waits, idles, finishes, or exits. Codex startup protection expires after a short grace period if no prompt has started yet, and the local transcript fallback reacquires protection on `task_started` and releases it on `task_complete`. Generic mode treats the process lifetime as active because generic commands do not expose agent-native waiting or permission hooks.

## Menu Bar App

`powernap-menu` starts automatically after install. It shows:

- a bolt icon when PowerNAP is blocking sleep;
- a Zzz icon when normal sleep is allowed;
- a question-mark icon when the daemon cannot be reached;
- a count beside the icon for active protected agent threads.

The menu includes daemon state, sleep state, active thread count, held leases, active sessions, battery state, thermal state, last refresh time, restore, logs, refresh, and quit actions.

## Commands

```bash
powernap status [--json]
powernap leases
powernap restore
powernap doctor [--hardware-spike] [--check-timeout-seconds 2]
powernap hooks install|status|uninstall|clean
powernap config
powernap logs
powernap install
powernap uninstall
```

`powernap restore` is safe to run repeatedly. It releases PowerNAP-owned leases, clears the closed-lid override, and marks open leases released in local state.

## Configuration

PowerNAP writes config to:

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

Runtime paths can be overridden for tests with `POWERNAP_RUNTIME_DIR`, `POWERNAP_APP_SUPPORT_DIR`, and `POWERNAP_LOGS_DIR`.

## Safety Model

PowerNAP is conservative by default:

- Hooks fail open so agent commands are not blocked by hook errors.
- Agent wrappers fail closed if the daemon is unavailable before protection starts.
- Power leases release when agents wait, idle, finish, error, or exit.
- Battery, thermal, TTL, daemon shutdown, watchdog, and manual restore paths all release PowerNAP-owned state.
- The watchdog independently clears stale closed-lid state if the daemon dies.
- PowerNAP does not log prompts, model output, API request bodies, credentials, or raw hook JSON by default.

## Development

```bash
swift test
swift build -c release
bash -n scripts/install.sh scripts/uninstall.sh
```

CI runs the same build, test, and shell syntax gates on macOS.

## Docs

- [Setup](docs/SETUP.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Uninstall](docs/UNINSTALL.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)

## License

PowerNAP is released under the [MIT License](LICENSE).
