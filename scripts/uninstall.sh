#!/bin/bash
# Uninstall PowerNAP binaries and LaunchAgent.
set -euo pipefail

INSTALL_DIR="/usr/local/bin"

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [[ "$TARGET_USER" == "root" && "$(id -u)" -ne 0 ]]; then
    TARGET_USER="$(id -un)"
fi
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [[ -z "$TARGET_HOME" ]]; then
    TARGET_HOME="$(eval echo "~$TARGET_USER")"
fi

PLIST_DST="$TARGET_HOME/Library/LaunchAgents/dev.powernap.daemon.plist"
WATCHDOG_PLIST_DST="$TARGET_HOME/Library/LaunchAgents/dev.powernap.watchdog.plist"
MENU_PLIST_DST="$TARGET_HOME/Library/LaunchAgents/dev.powernap.menu.plist"
CODEX_HOOKS="$TARGET_HOME/.codex/hooks.json"
CODEX_CONFIG="$TARGET_HOME/.codex/config.toml"
ZSHRC_DST="$TARGET_HOME/.zshrc"
SHELL_INIT_LINE='eval "$(powernap shell-init)"'

BINARIES=(
    "powernap"
    "powernapd"
    "powernap-hook"
    "powernap-menu"
    "powernap-watchdog"
)

warn_codex_file() {
    local path="$1"

    if [[ -f "$path" ]] && grep -qi 'powernap' "$path"; then
        printf 'Warning: %s still contains powernap entries. Run `powernap hooks uninstall` before running this script if you want Codex hook cleanup.\n' "$path" >&2
    fi
}

warn_codex_file "$CODEX_HOOKS"
warn_codex_file "$CODEX_CONFIG"

if [[ -x "$INSTALL_DIR/powernap" && "$(id -u)" -eq 0 && "$TARGET_UID" -ne 0 ]]; then
    sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" PATH="$PATH" "$INSTALL_DIR/powernap" uninstall || true
elif [[ -x "$INSTALL_DIR/powernap" ]]; then
    "$INSTALL_DIR/powernap" uninstall || true
else
    launchctl bootout "gui/$TARGET_UID/dev.powernap.daemon" 2>/dev/null || true
    launchctl bootout "gui/$TARGET_UID/dev.powernap.watchdog" 2>/dev/null || true
    launchctl bootout "gui/$TARGET_UID/dev.powernap.menu" 2>/dev/null || true
fi

removed_paths=()
if [[ -e "$PLIST_DST" ]]; then
    removed_paths+=("$PLIST_DST")
fi
if [[ -e "$WATCHDOG_PLIST_DST" ]]; then
    removed_paths+=("$WATCHDOG_PLIST_DST")
fi
if [[ -e "$MENU_PLIST_DST" ]]; then
    removed_paths+=("$MENU_PLIST_DST")
fi
rm -f "$PLIST_DST"
rm -f "$WATCHDOG_PLIST_DST"
rm -f "$MENU_PLIST_DST"

if [[ -f "$ZSHRC_DST" ]] && /usr/bin/grep -Fqx "$SHELL_INIT_LINE" "$ZSHRC_DST"; then
    if [[ "$(id -u)" -eq 0 && "$TARGET_UID" -ne 0 ]]; then
        sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" /bin/bash -c '
            set -euo pipefail
            rc="$1"
            line="$2"
            tmp="$rc.powernap.tmp.$$"
            /usr/bin/grep -Fvx "$line" "$rc" > "$tmp" || true
            /bin/mv "$tmp" "$rc"
        ' _ "$ZSHRC_DST" "$SHELL_INIT_LINE"
    else
        tmp="$ZSHRC_DST.powernap.tmp.$$"
        /usr/bin/grep -Fvx "$SHELL_INIT_LINE" "$ZSHRC_DST" > "$tmp" || true
        /bin/mv "$tmp" "$ZSHRC_DST"
    fi
    removed_paths+=("$ZSHRC_DST (shell init line)")
fi

if [[ -d "$INSTALL_DIR" && ! -w "$INSTALL_DIR" ]]; then
    RM_CMD=(sudo rm -f)
else
    RM_CMD=(rm -f)
fi

for binary in "${BINARIES[@]}"; do
    target="$INSTALL_DIR/$binary"
    if [[ -e "$target" ]]; then
        removed_paths+=("$target")
    fi
    "${RM_CMD[@]}" "$target"
done

printf 'Removed PowerNAP items:\n'
if [[ ${#removed_paths[@]} -eq 0 ]]; then
    printf '  nothing to remove\n'
else
    for path in "${removed_paths[@]}"; do
        printf '  %s\n' "$path"
    done
fi
printf 'User state was kept:\n'
printf '  %s\n' "$TARGET_HOME/Library/Application Support/PowerNAP/"
printf '  %s\n' "$TARGET_HOME/Library/Caches/PowerNAP/"
printf '  %s\n' "$TARGET_HOME/Library/Logs/PowerNAP/"
printf 'Remove those manually if desired:\n'
printf '  rm -rf "%s" "%s" "%s"\n' "$TARGET_HOME/Library/Application Support/PowerNAP" "$TARGET_HOME/Library/Caches/PowerNAP" "$TARGET_HOME/Library/Logs/PowerNAP"
printf 'Codex hook files were not removed. Run `powernap hooks uninstall` before uninstalling if you want to clean ~/.codex/hooks.json and ~/.codex/config.toml.\n'
