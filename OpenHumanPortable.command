#!/bin/bash
# ═══════════════════════════════════════════
# OpenHuman Portable · macOS
# ═══════════════════════════════════════════

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

# Resolve python3: bundled > system
resolve_python3() {
    local _arch
    _arch="$(uname -m)"
    local _bin_dir="$SCRIPT_DIR/bin/macos-x64"
    [ "$_arch" = "arm64" ] && _bin_dir="$SCRIPT_DIR/bin/macos-arm64"
    # 1. Bundled python3 (inside portable package)
    if [ -x "$_bin_dir/python3" ]; then
        echo "$_bin_dir/python3"
        return 0
    fi
    # 2. System python3
    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
        return 0
    fi
    return 1
}

# Handle --config parameter
if [ "${1:-}" = "--config" ]; then
    CONFIG_SERVER="$SCRIPT_DIR/lib/config_server.py"
    if PY3=$(resolve_python3) && [ -f "$CONFIG_SERVER" ]; then
        echo "  Opening config center http://127.0.0.1:17600 ..."
        exec "$PY3" "$CONFIG_SERVER"
    else
        echo "  [!] python3 or config_server.py not found"
        exit 1
    fi
fi

# Banner
CYAN='\033[38;5;45m'
BLUE='\033[38;5;33m'
DIM='\033[38;5;240m'
NC='\033[0m'
echo ""
echo -e "${CYAN}  ╔═══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}  ║                                           ║${NC}"
echo -e "${BLUE}  ║     O P E N H U M A N   P O R T A B L E   ║${NC}"
echo -e "${BLUE}  ║                                           ║${NC}"
echo -e "${DIM}  ╚═══════════════════════════════════════════╝${NC}"
echo ""

# Architecture detection
case "$ARCH" in
    arm64)  BIN_DIR="$SCRIPT_DIR/bin/macos-arm64" ;;
    x86_64) BIN_DIR="$SCRIPT_DIR/bin/macos-x64" ;;
    *)      echo "[ERROR] Unsupported architecture: $ARCH"; exit 1 ;;
esac

if [ -f "$BIN_DIR/OpenHuman.app/Contents/MacOS/OpenHuman" ]; then
    OPENHUMAN_BIN="$BIN_DIR/OpenHuman.app/Contents/MacOS/OpenHuman"
    xattr -dr com.apple.quarantine "$BIN_DIR/OpenHuman.app" 2>/dev/null
elif [ -f "$BIN_DIR/openhuman" ]; then
    OPENHUMAN_BIN="$BIN_DIR/openhuman"
    xattr -dr com.apple.quarantine "$OPENHUMAN_BIN" 2>/dev/null
else
    echo "[ERROR] OpenHuman not found in $BIN_DIR"
    echo "  Expected: OpenHuman.app/Contents/MacOS/OpenHuman or openhuman"
    exit 1
fi

chmod +x "$OPENHUMAN_BIN" 2>/dev/null

# ═══════════════════════════════════════════
# Single-instance lock (atomic mkdir)
# ═══════════════════════════════════════════
RUN_LOCK="$SCRIPT_DIR/data/.running"
mkdir -p "$SCRIPT_DIR/data"
if [ -d "$RUN_LOCK" ]; then
    PREV_PID=""
    [ -f "$RUN_LOCK/pid" ] && PREV_PID=$(cat "$RUN_LOCK/pid" 2>/dev/null | tr -d '[:space:]')
    if [ -n "${PREV_PID:-}" ] && kill -0 "$PREV_PID" 2>/dev/null; then
        echo "  [info] Another instance is already running (PID $PREV_PID)."
        echo "  If incorrect, delete: $RUN_LOCK"
        exit 1
    fi
    rm -rf "$RUN_LOCK" 2>/dev/null
fi
if ! mkdir "$RUN_LOCK" 2>/dev/null; then
    echo "  [info] Another instance is already running (concurrent start)."
    echo "  If incorrect, delete: $RUN_LOCK"
    exit 1
fi
echo $$ > "$RUN_LOCK/pid"

# ═══════════════════════════════════════════
# Portable directories
# ═══════════════════════════════════════════
PORTABLE_DATA="$SCRIPT_DIR/data"
PORTABLE_OPENHUMAN="$PORTABLE_DATA/.openhuman"
LIB_DIR="$SCRIPT_DIR/lib"

mkdir -p "$PORTABLE_OPENHUMAN/cef-cache"

# Cleanup on exit
cleanup() {
    [ -d "$RUN_LOCK" ] && rm -rf "$RUN_LOCK"
}
trap cleanup EXIT INT TERM

# ═══════════════════════════════════════════
# Kill orphaned config server on port 17600
# ═══════════════════════════════════════════
ORPHAN_PID=$(lsof -ti :17600 2>/dev/null)
if [ -n "${ORPHAN_PID:-}" ]; then
    echo "  [info] Stopping orphaned config server (PID $ORPHAN_PID)..."
    kill $ORPHAN_PID 2>/dev/null
    sleep 1
fi

# ═══════════════════════════════════════════
# Start config center (foreground, blocking)
# ═══════════════════════════════════════════
CONFIG_SERVER="$LIB_DIR/config_server.py"

if PY3=$(resolve_python3) && [ -f "$CONFIG_SERVER" ]; then
    echo "  Testing Python..."
    if ! "$PY3" -c "import sys; print('Python', sys.version)" 2>&1; then
        echo "  [!] Python test FAILED. Cannot start config center."
        echo "  Press Enter to continue without config center..."
        read -r _
    else
        echo "  Starting config center http://127.0.0.1:17600 ..."
        echo "  Configure provider and key, then click 'Start OpenHuman'."
        echo ""
        # Run config center in foreground (blocking) - waits for user to click "Start"
        "$PY3" "$CONFIG_SERVER"
        echo "  Config center closed. Starting OpenHuman..."
        echo ""
    fi
else
    echo "  [!] No Python found. Config center cannot start."
    echo "  Continuing with existing config..."
    sleep 2
fi

# ═══════════════════════════════════════════
# Launch OpenHuman GUI
# ═══════════════════════════════════════════
echo "  Architecture: $ARCH | Data: portable folder"
echo ""

export OPENHUMAN_WORKSPACE="$PORTABLE_OPENHUMAN"
export OPENHUMAN_CEF_CACHE_PATH="$PORTABLE_OPENHUMAN/cef-cache"

"$OPENHUMAN_BIN" "$@"
OPENHUMAN_EXIT=$?

# Early cleanup (don't rely on trap)
[ -d "$RUN_LOCK" ] && rm -rf "$RUN_LOCK"

if [ $OPENHUMAN_EXIT -ne 0 ]; then
    echo ""
    echo "  OpenHuman exit code: $OPENHUMAN_EXIT"
    read -rp "  Press Enter to close window... " _
fi
exit $OPENHUMAN_EXIT
