# Research References

Last verified: 2026-04-30.

This file records the evidence behind the PowerNAP implementation guide. Prefer primary vendor docs, local SDK headers, local command output, and source code over forum posts.

## Claims Matrix

| Claim | Evidence | Product implication |
| --- | --- | --- |
| Ordinary idle assertions are not enough for lid close. | Apple QA1340 says I/O Kit can prevent or delay idle sleep, but forced sleep includes closing a laptop lid, Apple menu sleep, thermal emergency, and low battery. | PowerNAP needs idle assertion plus clamshell override. |
| The clamshell path is user-space IOKit, not a kext. | Local SDK defines `kPMSetClamshellSleepState`; Apple XNU `RootDomainUserClient.cpp` dispatches it; `IOPMrootDomain.cpp` uses clamshell sleep disable state. | Build and harden user-space IOKit first. Do not start with a kext. |
| Clamshell override must be pre-armed. | Lid close is the forced-sleep decision point. | Acquire on active-turn start, before the user closes the lid. |
| Clamshell override needs an independent watchdog. | The IOKit clamshell state is global power-management state, not an expiring lease. | A separate LaunchAgent watchdog must clear stale state if the daemon hangs or dies. |
| Codex hooks support the turn events PowerNAP needs. | Codex docs list `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, and `Stop`; docs say turn-scoped hooks include `PreToolUse`, `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, and `Stop`. | Codex can drive active/waiting/turn-idle state. |
| Codex hooks must have short explicit timeouts. | Codex docs say hook `timeout` is in seconds and omitted timeout defaults to 600 seconds. | PowerNAP installs 2-second hooks and fails open. |
| Codex `prevent_idle_sleep` is not the PowerNAP solution. | Codex config exposes `features.prevent_idle_sleep`; local `pmset -g assertions` inspection earlier showed a normal `PreventUserIdleSystemSleep` assertion. | PowerNAP must still own closed-lid behavior. |
| Claude Code exposes richer hook coverage. | Claude hooks docs list `PermissionRequest`, `StopFailure`, `Elicitation`, `TeammateIdle`, and many other lifecycle points. | PowerNAP should install a broad per-run hook overlay for Claude. |
| Claude `Stop` is turn completion. | Claude docs say `Stop` fires when Claude finishes responding. | Map `Stop` to `turn_idle`, not process exit. |
| Claude supports per-run settings. | Claude CLI docs and local `claude --help` show `--settings <file-or-json>`. | Use temp per-run settings instead of global mutation. |
| Claude `--bare` is incompatible with PowerNAP hooks. | Local `claude --help` says bare mode skips hooks. | Warn users not to pass `--bare`. |
| Claude proxy support is HTTP/HTTPS, not SOCKS. | Claude proxy docs list `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY`, and say SOCKS is unsupported. | Do not default Claude to SOCKS or `ALL_PROXY`. |
| PowerNAP cannot silently turn on iPhone Personal Hotspot through documented public APIs. | Apple Personal Hotspot, Mac Help, and Instant Hotspot docs describe user setup, Bluetooth pairing, USB trust, same-account/family requirements, and Auto-Join settings. | Doctor/setup must validate phone setup; copy must not promise phone-side activation. |
| Auto-Join Hotspot is not a universal older-macOS answer. | Apple Instant Hotspot docs say the Mac "Automatic" Auto-Join setting is available in macOS Tahoe 26 or later. | For older macOS, rely on USB tether or known SSID join when available. |
| Service order alone is not proof of failover. | `networksetup` changes preference order; routing and reachability are separate observable states. | Report failover active only after route/probe verification. |
| A free local-only proxy cannot preserve a broken upstream stream. | A local proxy has loopback and upstream legs; the upstream TCP/TLS/WebSocket/SSE leg can break when the Mac changes networks. | Free improves survival and retry conditions, not exact stream continuity. |
| Vercel is not the relay data plane. | Vercel WebSocket/function docs point users to external realtime providers and function platform limits are not designed for long-lived relay sockets. | Use Vercel only for marketing/control plane. |
| Cloudflare is possible but not the first simple relay. | Cloudflare Workers accept WebSockets and support outbound TCP sockets; docs say inbound direct TCP support is not the general current path. | Consider Cloudflare later; start relay experiments on a VPS/Fly/Hetzner/DigitalOcean-style service. |
| QUIC is relevant for future tunnel work. | RFC 9000 defines connection migration and path validation. | Consider QUIC/MASQUE for future premium roaming tunnel. |

## Local Findings From This Machine

Verified on 2026-04-30:

macOS:

- `sw_vers`: macOS 26.4.1, build 25E253.
- `uname -m`: arm64.
- Network services from `networksetup -listnetworkserviceorder`:
  - Thunderbolt Bridge, `bridge0`
  - Wi-Fi, `en0`
  - iPhone USB, `en8`
  - ProtonVPN

Codex:

- `codex --version`: `codex-cli 0.128.0`.
- `codex features list`:
  - `codex_hooks` stable true.
  - `prevent_idle_sleep` experimental true.
- Earlier local assertion inspection with active Codex showed a normal `PreventUserIdleSystemSleep` assertion named for Codex, not a clamshell override.

Claude Code:

- `claude --version`: `2.1.105 (Claude Code)`.
- `claude --help` shows:
  - `--settings <file-or-json>`
  - `--include-hook-events`
  - `--bare` skips hooks, LSP, plugin sync, attribution, auto-memory, background prefetches, keychain reads, and CLAUDE.md auto-discovery.

PowerNAP:

- `swift test` passes after the latest implementation cleanup.
- `powernap doctor` now checks daemon IPC, watchdog/daemon LaunchAgents, hook binary, Codex/Claude hook readiness, battery/thermal state, iPhone USB presence, service order, default route, and agent HTTPS probes.
- `powernap doctor --hardware-spike` is the explicit clamshell override test.

## Apple And macOS References

- Apple Technical Q&A QA1340, "Registering and unregistering for sleep and wake notifications": https://developer.apple.com/library/archive/qa/qa1340/_index.html
- Apple `kIOPMAssertionTypePreventUserIdleSystemSleep`: https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep
- Apple XNU `RootDomainUserClient.cpp`: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/iokit/Kernel/RootDomainUserClient.cpp
- Apple XNU `IOPMrootDomain.cpp`: https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/iokit/Kernel/IOPMrootDomain.cpp
- Apple Personal Hotspot setup: https://support.apple.com/en-us/111785
- Apple Mac Help, sharing iPhone/iPad internet connection with Mac: https://support.apple.com/guide/mac-help/iphone-internet-connection-mac-mchl7403f0ee/mac
- Apple Instant Hotspot and Auto-Join Hotspot: https://support.apple.com/en-us/109321
- Apple Network Extension: https://developer.apple.com/documentation/networkextension
- Apple NEHotspotConfigurationManager: https://developer.apple.com/documentation/networkextension/nehotspotconfigurationmanager
- Apple CoreWLAN: https://developer.apple.com/documentation/corewlan
- Local `networksetup`, `route`, and `pmset` man pages.

Key implications:

- The default power assertion path is safe but incomplete.
- Closed-lid mode must use the IOKit clamshell path and must be watchdog-protected.
- USB tethering requires phone/Mac trust setup.
- Bluetooth tethering requires Bluetooth enabled, the iPhone discoverable during pairing, and macOS to expose a Bluetooth PAN service.
- Wi-Fi hotspot fallback requires hotspot availability or OS Auto-Join behavior.

## OpenAI Codex References

- Codex docs home: https://developers.openai.com/codex/
- Codex hooks: https://developers.openai.com/codex/hooks
- Codex config reference: https://developers.openai.com/codex/config-reference
- Codex GitHub repo: https://github.com/openai/codex
- Codex Rust client source: https://github.com/openai/codex/blob/main/codex-rs/core/src/client.rs
- Codex network proxy package: https://github.com/openai/codex/tree/main/codex-rs/network-proxy

Key implications:

- Use Codex hooks rather than scraping terminal output.
- Keep hooks inert outside a PowerNAP run.
- Keep hook timeout explicit and short.
- Treat Codex managed-network `proxy_url` and `socks_url` as subprocess/tool traffic settings unless a spike proves they route Codex model traffic.

## Anthropic Claude Code References

- Claude hooks: https://code.claude.com/docs/en/hooks
- Claude CLI reference: https://code.claude.com/docs/en/cli-reference
- Claude proxy docs: https://code.claude.com/docs/en/corporate-proxy

Key implications:

- Use `--settings` for per-run hook overlays.
- Do not use `--bare`.
- Map `PermissionRequest` and `Elicitation` to waiting.
- Map `Stop` and `TeammateIdle` to turn-idle.
- Map `StopFailure` to error.
- Use HTTP/HTTPS proxy environment variables only if a proxy mode is implemented; do not use SOCKS for Claude.

## Relay And Tunnel References

- Vercel WebSocket Functions note: https://vercel.com/kb/guide/do-vercel-serverless-functions-support-websocket-connections
- Vercel platform limits: https://vercel.com/docs/limits
- Cloudflare Workers protocols: https://developers.cloudflare.com/workers/reference/protocols/
- Cloudflare Workers TCP sockets: https://developers.cloudflare.com/workers/runtime-apis/tcp-sockets/
- Cloudflare Durable Object WebSockets: https://developers.cloudflare.com/durable-objects/best-practices/websockets/
- Cloudflare Workers limits: https://developers.cloudflare.com/workers/platform/limits/
- RFC 9000 QUIC: https://www.rfc-editor.org/rfc/rfc9000.html
- WireGuard paper: https://www.wireguard.com/papers/wireguard.pdf
- Tailscale exit nodes: https://tailscale.com/docs/features/exit-nodes

Key implications:

- A hosted relay is the right premium boundary.
- A blind relay may preserve opaque upstream sockets during short local outages.
- A stream-aware relay can provide better semantics but has privacy implications.
- QUIC/MASQUE-style work is future tunnel research, not MVP.

## Networking Principle

Free local mode can do this:

```text
agent process stays alive
Mac stays awake while active
network service order changes
route and HTTPS probes recover
agent/provider retries on new path
```

Free local mode cannot promise this:

```text
the exact same in-flight upstream model stream survives every network transition
```

That stronger guarantee needs a stable remote endpoint or provider-level resume semantics.
