#!/bin/bash
set -u
set -o pipefail

echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║                                           ║"
echo "  ║     O P E N H U M A N   P O R T A B L E   ║"
echo "  ║                                           ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)  BIN_DIR="$SCRIPT_DIR/bin/linux-x64" ;;
    aarch64|arm64) BIN_DIR="$SCRIPT_DIR/bin/linux-arm64" ;;
    *)       echo "  [ERROR] Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Detect binary (native or AppImage)
if [ -f "$BIN_DIR/openhuman" ]; then
    OPENHUMAN_BIN="$BIN_DIR/openhuman"
elif [ -f "$BIN_DIR/OpenHuman.AppImage" ]; then
    OPENHUMAN_BIN="$BIN_DIR/OpenHuman.AppImage"
else
    echo "  [ERROR] OpenHuman not found in $BIN_DIR"
    echo "  Run: bash setup.sh"
    exit 1
fi

chmod +x "$OPENHUMAN_BIN" 2>/dev/null

# Create portable home (zero host pollution)
mkdir -p "$SCRIPT_DIR/data/.home" 2>/dev/null
mkdir -p "$SCRIPT_DIR/data/.openhuman/cef-cache" 2>/dev/null

# First launch: show guide
if [ ! -f "$SCRIPT_DIR/data/.openhuman/.setup-done" ]; then
    echo "  First launch - opening setup guide..."
    if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$SCRIPT_DIR/lib/first-launch.html" 2>/dev/null
    elif command -v sensible-browser >/dev/null 2>&1; then
        sensible-browser "$SCRIPT_DIR/lib/first-launch.html" 2>/dev/null
    else
        echo "  [i] Open this guide manually: $SCRIPT_DIR/lib/first-launch.html"
    fi
    touch "$SCRIPT_DIR/data/.openhuman/.setup-done"
fi

# Portable environment — all paths stay inside the portable folder
export HOME="$SCRIPT_DIR/data/.home"
export OPENHUMAN_WORKSPACE="$SCRIPT_DIR/data/.openhuman"
export OPENHUMAN_CEF_CACHE_PATH="$SCRIPT_DIR/data/.openhuman/cef-cache"

echo "  Architecture: $ARCH | Data: portable folder"
echo "  Launching OpenHuman..."
echo ""

"$OPENHUMAN_BIN" "$@"
