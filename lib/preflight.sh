#!/bin/bash
# ═══════════════════════════════════════════
# Pre-flight self-check for OpenHuman Portable
# Source this from launchers: source "$LIB_DIR/preflight.sh"
# ═══════════════════════════════════════════

preflight_check() {
    local bin_dir="${1:-$BIN_DIR}"
    local data_dir="${2:-$SCRIPT_DIR/data}"
    local app_name="${3:-openhuman}"
    local errors=0
    local warnings=0

    # 1. Binary present and executable
    local # macOS .app bundle detection
if [ -d "$bin_dir/OpenHuman.app" ]; then
    bin_file="$bin_dir/OpenHuman.app/Contents/MacOS/OpenHuman"
else
    bin_file="$bin_dir/$app_name"
fi
    [ "$(uname -s)" = "MINGW"* ] && bin_file="${bin_file}.exe"

    if [ ! -f "$bin_file" ]; then
        echo "  [ERROR] Binary not found: $bin_file"
        errors=$((errors + 1))
    elif [ ! -x "$bin_file" ] && [ "$(uname -s)" != "MINGW"* ]; then
        echo "  [WARN]  Binary not executable: $bin_file"
        chmod +x "$bin_file" 2>/dev/null
        warnings=$((warnings + 1))
    fi

    # 2. Python3 available (for config center)
    local has_python=0
    if [ -x "$bin_dir/python3" ] || [ -x "$bin_dir/python/python.exe" ]; then
        has_python=1
    elif command -v python3 &>/dev/null || command -v python &>/dev/null; then
        has_python=1
    fi
    if [ "$has_python" = "0" ]; then
        echo "  [WARN]  No Python found — config center will not start"
        warnings=$((warnings + 1))
    fi

    # 3. Data directory writable
    if [ ! -d "$data_dir" ]; then
        mkdir -p "$data_dir" 2>/dev/null
    fi
    if [ ! -w "$data_dir" ]; then
        echo "  [ERROR] Data directory not writable: $data_dir"
        errors=$((errors + 1))
    fi

    # 4. Disk free space (>500MB for OpenHuman)
    local free_mb
    if command -v df &>/dev/null; then
        free_mb=$(df -m "$data_dir" 2>/dev/null | awk 'NR==2{print $4}')
        if [ -n "$free_mb" ] && [ "$free_mb" -lt 500 ] 2>/dev/null; then
            echo "  [WARN]  Low disk space: ${free_mb}MB free (< 500MB)"
            warnings=$((warnings + 1))
        fi
    fi

    # 5. Port 17600 available
    local port_busy=0
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep -q ":17600 " && port_busy=1
    elif command -v lsof &>/dev/null; then
        lsof -i :17600 &>/dev/null && port_busy=1
    elif command -v netstat &>/dev/null; then
        netstat -an 2>/dev/null | grep -q ":17600.*LISTEN" && port_busy=1
    else
        echo "  [WARN]  No port-checking tool found (ss/lsof/netstat)"
        warnings=$((warnings + 1))
    fi
    if [ "$port_busy" = "1" ]; then
        echo "  [WARN]  Port 17600 already in use"
        warnings=$((warnings + 1))
    fi

    # 6. Config file integrity
    local CONFIG_FILE="$data_dir/.openhuman/config.json"
    if [ -f "$CONFIG_FILE" ]; then
        if command -v python3 &>/dev/null; then
            if ! python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$CONFIG_FILE" 2>/dev/null; then
                echo "  [WARN]  config.json parse failed: $CONFIG_FILE"
                echo "          Config center will auto-recover from backups"
                warnings=$((warnings + 1))
            fi
        fi
    fi

    # 7. Binary actually runs (--version smoke test, with timeout)
    if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
        local BIN_VER=""
        if command -v timeout &>/dev/null; then
            BIN_VER=$(timeout 5 "$bin_file" --version 2>&1 || true)
        elif command -v perl &>/dev/null; then
            # macOS has perl but not timeout — use alarm
            BIN_VER=$(perl -e 'alarm 5; exec @ARGV' -- "$bin_file" --version 2>&1 || true)
        else
            # Last resort: background + manual kill after 5s
            "$bin_file" --version &>/tmp/oh-pf-$$ &
            local _pf_pid=$!
            (sleep 5 && kill "$_pf_pid" 2>/dev/null) &
            local _watchdog=$!
            wait "$_pf_pid" 2>/dev/null
            BIN_VER=$(cat /tmp/oh-pf-$$ 2>/dev/null)
            kill "$_watchdog" 2>/dev/null
            rm -f /tmp/oh-pf-$$
        fi
        if [ -z "$BIN_VER" ]; then
            echo "  [WARN]  Binary found but won't run: $bin_file"
            echo "          USB files may be corrupted"
            warnings=$((warnings + 1))
        fi
    fi

    # 8. cc-switch if present (optional — not an error if missing)
    local ccswitch="$bin_dir/cc-switch"
    [ "$(uname -s)" = "MINGW"* ] && ccswitch="${ccswitch}.exe"
    if [ -f "$ccswitch" ]; then
        if [ ! -x "$ccswitch" ] && [ "$(uname -s)" != "MINGW"* ]; then
            echo "  [WARN]  cc-switch not executable: $ccswitch"
            chmod +x "$ccswitch" 2>/dev/null
            warnings=$((warnings + 1))
        fi
    else
        echo "  [INFO]  cc-switch not found (optional)"
    fi

    # Summary
    if [ "$errors" -gt 0 ]; then
        echo "  [FAIL] $errors error(s), $warnings warning(s)"
        return 1
    fi
    if [ "$warnings" -gt 0 ]; then
        echo "  [ok] Pre-flight passed with $warnings warning(s)"
    fi
    return 0
}
