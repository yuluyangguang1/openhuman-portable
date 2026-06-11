#!/bin/bash
# ═══════════════════════════════════════════
# OpenHuman Portable · Linux
# ═══════════════════════════════════════════

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

# Resolve python3: bundled > system
resolve_python3() {
    local _arch
    _arch="$(uname -m)"
    local _bin_dir="$SCRIPT_DIR/bin/linux-x64"
    case "$_arch" in
        arm64|aarch64) _bin_dir="$SCRIPT_DIR/bin/linux-arm64" ;;
        *)             _bin_dir="$SCRIPT_DIR/bin/linux-x64" ;;
    esac
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
echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║                                           ║"
echo "  ║     O P E N H U M A N   P O R T A B L E   ║"
echo "  ║                                           ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""

# Architecture detection
case "$ARCH" in
    x86_64|amd64) BIN_DIR="$SCRIPT_DIR/bin/linux-x64" ;;
    aarch64|arm64)
        echo "[ERROR] Linux ARM64 is not yet supported."
        echo "  Please use on x86_64 Linux, or check for future releases."
        exit 1
        ;;
    *) echo "[ERROR] Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Check for AppImage or binary
OPENHUMAN_BIN=""
if [ -f "$BIN_DIR/openhuman" ]; then
    OPENHUMAN_BIN="$BIN_DIR/openhuman"
elif [ -f "$BIN_DIR/OpenHuman.AppImage" ]; then
    OPENHUMAN_BIN="$BIN_DIR/OpenHuman.AppImage"
fi

if [ -z "$OPENHUMAN_BIN" ]; then
    echo "[ERROR] OpenHuman not found in: $BIN_DIR"
    echo "  Expected: openhuman or OpenHuman.AppImage"
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
ORPHAN_PID=$(lsof -ti :17600 2>/dev/null || ss -tlnp 2>/dev/null | grep ':17600' | grep -oP 'pid=\K\d+' || true)
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
