#!/bin/bash
set -u

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
    arm64)  BIN_DIR="$SCRIPT_DIR/bin/macos-arm64" ;;
    x86_64) BIN_DIR="$SCRIPT_DIR/bin/macos-x64" ;;
    *)      echo "  [ERROR] Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Detect binary (.app bundle or flat)
if [ -f "$BIN_DIR/OpenHuman.app/Contents/MacOS/OpenHuman" ]; then
    OPENHUMAN_BIN="$BIN_DIR/OpenHuman.app/Contents/MacOS/OpenHuman"
    xattr -dr com.apple.quarantine "$BIN_DIR/OpenHuman.app" 2>/dev/null
elif [ -f "$BIN_DIR/openhuman" ]; then
    OPENHUMAN_BIN="$BIN_DIR/openhuman"
    xattr -dr com.apple.quarantine "$OPENHUMAN_BIN" 2>/dev/null
else
    echo "  [ERROR] OpenHuman not found in $BIN_DIR"
    echo "  Run: bash setup.sh"
    exit 1
fi

chmod +x "$OPENHUMAN_BIN" 2>/dev/null

# Create data directories
mkdir -p "$SCRIPT_DIR/data/.openhuman/cef-cache" 2>/dev/null

# First launch: show guide
if [ ! -f "$SCRIPT_DIR/data/.openhuman/.setup-done" ]; then
    echo "  First launch - opening setup guide..."
    open "$SCRIPT_DIR/lib/first-launch.html" 2>/dev/null
    touch "$SCRIPT_DIR/data/.openhuman/.setup-done"
fi

# Set portable environment
export OPENHUMAN_WORKSPACE="$SCRIPT_DIR/data/.openhuman"
export OPENHUMAN_CEF_CACHE_PATH="$SCRIPT_DIR/data/.openhuman/cef-cache"

echo "  Architecture: $ARCH | Data: portable folder"
echo "  Launching OpenHuman..."
echo ""

"$OPENHUMAN_BIN" "$@"
