# Contributing

PowerNAP is a macOS Swift package. Contributions should keep the local-only
safety contract intact: PowerNAP may keep a Mac awake only while protected work
is active, and it must release power state when work stops, waits, or becomes
unsafe.

## Development Setup

Requirements:

- macOS 13 or later.
- Xcode Command Line Tools.
- Swift Package Manager.

Build and test:

```bash
swift test
swift build -c release
bash -n scripts/install.sh scripts/uninstall.sh
```

Run the non-invasive local diagnostic after installing:

```bash
powernap doctor --check-timeout-seconds 2
```

Only run closed-lid tests on hardware after:

```bash
powernap doctor --hardware-spike
```

## Change Guidelines

- Keep hooks fail-open: hook failures must not block Codex or Claude Code.
- Keep hook stdout empty unless an agent integration explicitly requires output.
- Treat hook payloads as untrusted input.
- Do not log prompts, model output, API request bodies, credentials, or raw hook JSON by default.
- Preserve existing Codex/Claude user configuration when installing or uninstalling hooks.
- Add or update tests for config parsing, IPC, lease lifecycle, hook mapping, and state restoration changes.
- Update docs when behavior, safety assumptions, install paths, or release gates change.

## Pull Request Checklist

- `swift test` passes.
- `swift build -c release` passes.
- Shell scripts pass `bash -n`.
- User-facing commands and docs match.
- Power, hook, install, and menu bar behavior should have a clear manual verification path in the relevant user-facing docs.
