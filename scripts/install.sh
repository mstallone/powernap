#!/bin/bash
# Install PowerNAP binaries and LaunchAgent.
set -euo pipefail

INSTALL_DIR="/usr/local/bin"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET_USER="${SUDO_USER:-$(id -un)}"
if [[ "$TARGET_USER" == "root" && "$(id -u)" -ne 0 ]]; then
    TARGET_USER="$(id -un)"
fi
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GROUP="$(id -gn "$TARGET_USER")"
TARGET_HOME="$(dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [[ -z "$TARGET_HOME" ]]; then
    TARGET_HOME="$(eval echo "~$TARGET_USER")"
fi

PLIST_DST="$TARGET_HOME/Library/LaunchAgents/dev.powernap.daemon.plist"
WATCHDOG_PLIST_DST="$TARGET_HOME/Library/LaunchAgents/dev.powernap.watchdog.plist"

BINARIES=(
    "powernap"
    "powernapd"
    "powernap-hook"
    "powernap-watchdog"
)

BUILD_DIR="$REPO_ROOT/.build/release"

if [[ "$(id -u)" -eq 0 && "$TARGET_UID" -ne 0 ]]; then
    for generated_path in "$REPO_ROOT/.build" "$REPO_ROOT/.swiftpm" "$REPO_ROOT/Package.resolved"; do
        if [[ -e "$generated_path" ]]; then
            chown -R "$TARGET_USER:$TARGET_GROUP" "$generated_path" 2>/dev/null || true
        fi
    done
    sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" PATH="$PATH" swift build -c release --package-path "$REPO_ROOT"
else
    swift build -c release --package-path "$REPO_ROOT"
fi

for binary in "${BINARIES[@]}"; do
    if [[ ! -x "$BUILD_DIR/$binary" ]]; then
        printf 'Missing build artifact: %s\n' "$BUILD_DIR/$binary" >&2
        exit 1
    fi
done

if [[ ! -d "$INSTALL_DIR" ]]; then
    if [[ -w "$(dirname "$INSTALL_DIR")" ]]; then
        mkdir -p "$INSTALL_DIR"
    else
        sudo mkdir -p "$INSTALL_DIR"
    fi
fi

if [[ -w "$INSTALL_DIR" ]]; then
    COPY_CMD=(cp)
else
    COPY_CMD=(sudo cp)
fi

installed_paths=()
for binary in "${BINARIES[@]}"; do
    "${COPY_CMD[@]}" "$BUILD_DIR/$binary" "$INSTALL_DIR/$binary"
    installed_paths+=("$INSTALL_DIR/$binary")
done

if [[ "$(id -u)" -eq 0 && "$TARGET_UID" -ne 0 ]]; then
    rm -f /var/root/Library/LaunchAgents/dev.powernap.daemon.plist /var/root/Library/LaunchAgents/dev.powernap.watchdog.plist 2>/dev/null || true
    sudo -u "$TARGET_USER" env HOME="$TARGET_HOME" PATH="$PATH" "$INSTALL_DIR/powernap" install
else
    "$INSTALL_DIR/powernap" install
fi

printf 'Installed PowerNAP binaries:\n'
for path in "${installed_paths[@]}"; do
    printf '  %s\n' "$path"
done
printf 'Installed for user: %s (uid %s)\n' "$TARGET_USER" "$TARGET_UID"
printf 'LaunchAgent plist:\n'
printf '  %s\n' "$PLIST_DST"
printf '  %s\n' "$WATCHDOG_PLIST_DST"
printf 'Next steps:\n'
printf '  powernap hooks install\n'
printf '  powernap status\n'
