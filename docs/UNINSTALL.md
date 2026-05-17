# Uninstallation

## Remove Hooks

If you want to remove Codex hook entries first:

```bash
powernap hooks uninstall
```

This removes PowerNAP-managed Codex hooks and cleans stale Claude per-run overlays. It preserves other user hooks and does not force `hooks = false`.

## Remove LaunchAgents And Binaries

```bash
./scripts/uninstall.sh
```

The script unloads:

- `dev.powernap.daemon`
- `dev.powernap.watchdog`
- `dev.powernap.menu`

Then it removes:

- `/usr/local/bin/powernap`
- `/usr/local/bin/powernapd`
- `/usr/local/bin/powernap-hook`
- `/usr/local/bin/powernap-menu`
- `/usr/local/bin/powernap-watchdog`
- `~/Library/LaunchAgents/dev.powernap.daemon.plist`
- `~/Library/LaunchAgents/dev.powernap.watchdog.plist`
- `~/Library/LaunchAgents/dev.powernap.menu.plist`
- the exact PowerNAP shell alias line from `~/.zshrc`

## Remove State And Logs

State is preserved by default. Remove it manually only if you are done debugging:

```bash
rm -rf "$HOME/Library/Application Support/PowerNAP"
rm -rf "$HOME/Library/Caches/PowerNAP"
rm -rf "$HOME/Library/Logs/PowerNAP"
rm -rf "$TMPDIR/PowerNAP"
```
