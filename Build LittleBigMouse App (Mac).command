#!/usr/bin/env bash
#
# Build LittleBigMouse App (Mac).command — double-click in Finder to build
# LittleBigMouse.app (and a .dmg to share), then optionally install it in
# /Applications.
#
# Needs Rust and the .NET SDK: double-click "Run LittleBigMouse (Mac).command" once
# first if this Mac has never built the project; it installs them.

set -uo pipefail
cd "$(dirname "$0")" || exit 1
ROOT="$PWD"
LOG="$HOME/Desktop/LittleBigMouse-app-build.log"

B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; N=$'\033[0m'

finish() {
    echo
    read -n 1 -s -r -p "Press any key to close this window."
    echo
    exit "${1:-0}"
}

[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
for d in /usr/local/share/dotnet /opt/homebrew/bin "$HOME/.dotnet"; do
    [[ -d "$d" && ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

if ! command -v cargo >/dev/null 2>&1 || ! command -v dotnet >/dev/null 2>&1; then
    echo "${R}Rust or the .NET SDK is missing.${N} Double-click \"Run LittleBigMouse (Mac).command\""
    echo "once first: it installs them. Then run this again."
    finish 1
fi

git -C "$ROOT" submodule update --init --recursive --quiet 2>/dev/null

echo "${B}Building LittleBigMouse.app${N} (this takes a few minutes; full log: $LOG)"
"$ROOT/packaging/macos/build-app.sh" "$@" 2>&1 | tee "$LOG" | grep -E '^==>|\.dmg$| error |error:'
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "${R}${B}The build failed.${N} The errors are in $LOG"
    finish 1
fi

ARCH=$([[ "$(uname -m)" == "arm64" ]] && echo arm64 || echo x64)
APP="$ROOT/dist/$ARCH/LittleBigMouse.app"
echo
echo "${G}${B}Built:${N} $APP"
ls -1 "$ROOT"/dist/*.dmg 2>/dev/null | sed 's/^/       /'

echo
read -r -p "Install it in /Applications now? [y/N] " answer
if [[ "$answer" =~ ^[Yy] ]]; then
    # Quit a running copy first so the bundle can be replaced.
    pkill -f "LittleBigMouse.Ui.Avalonia" 2>/dev/null
    pkill -x lbm-hook 2>/dev/null
    sleep 1
    rm -rf "/Applications/LittleBigMouse.app"
    if cp -R "$APP" /Applications/; then
        echo "${G}Installed.${N} Opening it…"
        echo
        echo "Accessibility: macOS now gives the permission to ${B}LittleBigMouse${N} itself"
        echo "(not Terminal). Switch it on when asked. After an update, if the engine"
        echo "won't start, remove LittleBigMouse from the Accessibility list with − and"
        echo "add it again: every build has a new signature."
        open "/Applications/LittleBigMouse.app"
    else
        echo "${R}Couldn't copy to /Applications.${N} Drag the app there from Finder instead."
        open -R "$APP"
    fi
else
    open -R "$APP"
fi

finish 0
