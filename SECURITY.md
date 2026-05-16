# Security Policy

PowerNAP runs local daemons, installs agent hooks, and changes power state.
Please report security issues privately before opening a public issue.

## Reporting

Open a private security advisory on GitHub, or contact the maintainer through
the repository owner profile if advisories are unavailable.

Include:

- Affected version or commit.
- macOS version and architecture.
- Reproduction steps.
- Expected and actual impact.
- Any logs with credentials, prompts, and model output removed.

## Security Invariants

- IPC uses a Unix domain socket in a private per-user runtime directory.
- Hook events use per-run random tokens.
- Hooks are inert outside PowerNAP-wrapped runs.
- Malformed or unauthenticated hook input must not synthesize active work.
- Power leases must have restore paths and watchdog cleanup.
- Secrets must not be written to config files or logs.
