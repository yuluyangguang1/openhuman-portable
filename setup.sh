#!/bin/bash
# Local build script — downloads OpenHuman binaries for the current platform
# Usage:
#   bash setup.sh               # current platform
#   bash setup.sh --all          # all platforms (for USB distribution)
#   bash setup.sh --version v0.57.18

set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

REPO="tinyhumansai/openhuman"
VER=""
ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --version) if [ $# -lt 2 ]; then echo "  [!] --version requires a value"; exit 1; fi; VER="$2"; shift 2 ;;
        --all)     ALL=1; shift ;;
        -h|--help)
            cat <<'EOF'
Usage: bash setup.sh [--all] [--version <tag>]

Options:
  --all              Download binaries for all platforms (USB distribution)
  --version <tag>    Specify OpenHuman version (default: latest from GitHub)

Examples:
  bash setup.sh                        # Download for current platform
  bash setup.sh --all                  # Download all platforms
  bash setup.sh --version v0.57.18     # Specific version
EOF
            exit 0
            ;;
        *) echo "  [!] Unknown arg: $1"; exit 1 ;;
    esac
done

if [ -z "$VER" ]; then
    echo "  [info] Resolving latest OpenHuman release..."
    VER=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep -m1 '"tag_name"' | cut -d '"' -f 4)
    if [ -z "$VER" ]; then
        echo "  [!] Failed to resolve latest version. Specify with --version."
        exit 1
    fi
fi
echo "  OpenHuman version: $VER"

# Strip leading 'v' for asset filenames (assets use version without 'v')
VER_NUM="${VER#v}"
BASE="https://github.com/${REPO}/releases/download/${VER}"

# --- Helpers ---

download_file() {
    local target="$1" url="$2"
    mkdir -p "$(dirname "$target")"
    echo "  [download] $(basename "$url") → $target"
    curl -fsSL -o "$target" "$url"
    # SHA256 verification: try .sha256 sidecar
    local sha_url="${url}.sha256"
    local expected
    expected=$(curl -fsSL "$sha_url" 2>/dev/null | awk '{print $1}') || true
    if [ -n "$expected" ]; then
        local actual
        actual=$(shasum -a 256 "$target" | awk '{print $1}')
        if [ "$expected" = "$actual" ]; then
            echo "  [verify] SHA256 OK"
        else
            echo "  [verify] SHA256 MISMATCH! expected=$expected actual=$actual"
            return 1
        fi
    fi
}

download_and_extract_tar() {
    local target_dir="$1" archive_url="$2" archive_name="$3"
    mkdir -p "$target_dir"
    local tmpfile
    tmpfile=$(mktemp)
    echo "  [download] $archive_name → $target_dir/"
    curl -fsSL -o "$tmpfile" "$archive_url"
    # SHA256 verification: try .sha256 sidecar
    local sha_url="${archive_url}.sha256"
    local expected
    expected=$(curl -fsSL "$sha_url" 2>/dev/null | awk '{print $1}') || true
    if [ -n "$expected" ]; then
        local actual
        actual=$(shasum -a 256 "$tmpfile" | awk '{print $1}')
        if [ "$expected" = "$actual" ]; then
            echo "  [verify] SHA256 OK"
        else
            echo "  [verify] SHA256 MISMATCH! expected=$expected actual=$actual"
            rm -f "$tmpfile"
            return 1
        fi
    fi
    tar -xzf "$tmpfile" -C "$target_dir"
    rm -f "$tmpfile"
}

# --- Platform-specific downloads ---

download_macos_arm64() {
    local dest="bin/macos-arm64"
    local asset="OpenHuman_${VER_NUM}_aarch64-apple-darwin.app.tar.gz"
    local url="${BASE}/${asset}"
    echo ""
    echo "  === macOS ARM64 ==="
    download_and_extract_tar "$dest" "$url" "$asset"
    # Extracted tarball contains OpenHuman.app/ directory
    if [ -d "$dest/OpenHuman.app" ]; then
        echo "  [ok] OpenHuman.app extracted to $dest/OpenHuman.app/"
    fi
}

download_macos_x64() {
    local dest="bin/macos-x64"
    local asset="OpenHuman_${VER_NUM}_x86_64-apple-darwin.app.tar.gz"
    local url="${BASE}/${asset}"
    echo ""
    echo "  === macOS x64 ==="
    download_and_extract_tar "$dest" "$url" "$asset"
    if [ -d "$dest/OpenHuman.app" ]; then
        echo "  [ok] OpenHuman.app extracted to $dest/OpenHuman.app/"
    fi
}

download_linux_x64() {
    local dest="bin/linux-x64"
    local asset="OpenHuman_${VER_NUM}_amd64.AppImage"
    local url="${BASE}/${asset}"
    local target="${dest}/OpenHuman.AppImage"
    echo ""
    echo "  === Linux x64 ==="
    download_file "$target" "$url"
    chmod +x "$target"
    echo "  [ok] $target (executable)"
}

download_linux_arm64() {
    local dest="bin/linux-arm64"
    local asset="OpenHuman_${VER_NUM}_aarch64.AppImage"
    local url="${BASE}/${asset}"
    local target="${dest}/OpenHuman.AppImage"
    echo ""
    echo "  === Linux ARM64 ==="
    download_file "$target" "$url"
    chmod +x "$target"
    echo "  [ok] $target (executable)"
}

download_windows_x64() {
    local dest="bin/windows-x64"
    local asset="OpenHuman_${VER_NUM}_x64-setup.exe"
    local url="${BASE}/${asset}"
    echo ""
    echo "  === Windows x64 ==="
    echo "  [info] Downloading NSIS installer — user will run it manually."
    download_file "${dest}/OpenHuman-setup.exe" "$url"
    echo "  [ok] ${dest}/OpenHuman-setup.exe"
}

# --- cc-switch GUI ---
CCS_BASE="https://github.com/yuluyangguang1/openhuman-portable/releases/download/cc-switch-assets"

ccs_download() {
    local target="$1" asset="$2"
    local dir
    dir=$(dirname "$target")
    [ -d "$dir" ] || return 0
    echo "  [download] $asset → $target"
    curl -fsSL -o "$target" "${CCS_BASE}/${asset}" 2>/dev/null || {
        echo "  [warn] cc-switch asset not available, skipping."
        rm -f "$target"
        return 0
    }
    [ "${target##*.}" != "exe" ] && chmod +x "$target"
}

download_cc_switch() {
    echo ""
    echo "  [info] Fetching cc-switch GUI from cc-switch-assets release..."
    if [ "$ALL" = "1" ]; then
        ccs_download bin/macos-arm64/cc-switch     cc-switch-macos
        ccs_download bin/macos-x64/cc-switch       cc-switch-macos
        ccs_download bin/linux-x64/cc-switch       cc-switch-linux-x64
        ccs_download bin/linux-arm64/cc-switch     cc-switch-linux-arm64
        ccs_download bin/windows-x64/cc-switch.exe cc-switch-windows-x64.exe
    else
        case "$OS-$ARCH" in
            Darwin-arm64)   ccs_download bin/macos-arm64/cc-switch cc-switch-macos ;;
            Darwin-x86_64)  ccs_download bin/macos-x64/cc-switch   cc-switch-macos ;;
            Linux-x86_64)   ccs_download bin/linux-x64/cc-switch   cc-switch-linux-x64 ;;
            Linux-aarch64)  ccs_download bin/linux-arm64/cc-switch cc-switch-linux-arm64 ;;
        esac
    fi
}

# --- Main ---

OS="$(uname -s)"
ARCH="$(uname -m)"

if [ "$ALL" = "1" ]; then
    download_macos_arm64
    download_macos_x64
    download_linux_x64
    download_linux_arm64
    download_windows_x64
else
    case "$OS-$ARCH" in
        Darwin-arm64)   download_macos_arm64 ;;
        Darwin-x86_64)  download_macos_x64 ;;
        Linux-x86_64)   download_linux_x64 ;;
        Linux-aarch64)  download_linux_arm64 ;;
        *) echo "  [!] Unsupported platform: $OS-$ARCH"; exit 1 ;;
    esac
fi

download_cc_switch

echo ""
echo "  [done] OpenHuman binaries + cc-switch GUI ready."
echo ""
echo "  Launch with:"
case "$OS" in
    Darwin) echo "    ./OpenHumanPortable.command" ;;
    Linux)  echo "    ./OpenHumanPortable.sh" ;;
    *)      echo "    See platform-specific instructions in README.md" ;;
esac
echo ""

if [ "$ALL" = "1" ]; then
    cat <<'EOF'
  Platform instructions (USB distribution):

    macOS:
      Open OpenHumanPortable.command (double-click in Finder)
      Or: ./bin/macos-arm64/OpenHuman.app/Contents/MacOS/OpenHuman
      Or: ./bin/macos-x64/OpenHuman.app/Contents/MacOS/OpenHuman

    Linux:
      chmod +x OpenHumanPortable.sh && ./OpenHumanPortable.sh
      Or: ./bin/linux-x64/OpenHuman.AppImage
      Or: ./bin/linux-arm64/OpenHuman.AppImage

    Windows:
      Run bin\windows-x64\OpenHuman-setup.exe to install
      Or: OpenHumanPortable.bat
EOF
fi
