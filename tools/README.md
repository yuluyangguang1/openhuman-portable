# Tools

## setup.sh

Downloads OpenHuman binaries for the current platform (or all platforms).

### Usage

```bash
# Download for current platform (auto-resolves latest version)
bash setup.sh

# Download for all platforms (USB distribution)
bash setup.sh --all

# Specify a version
bash setup.sh --version v0.57.18

# Help
bash setup.sh --help
```

### What it downloads

| Platform   | Asset                                         | Destination                            |
|-----------|-----------------------------------------------|----------------------------------------|
| macOS ARM64 | `OpenHuman_{ver}_aarch64-apple-darwin.app.tar.gz` | `bin/macos-arm64/OpenHuman.app/`      |
| macOS x64   | `OpenHuman_{ver}_x86_64-apple-darwin.app.tar.gz`  | `bin/macos-x64/OpenHuman.app/`        |
| Linux x64   | `OpenHuman_{ver}_amd64.AppImage`                | `bin/linux-x64/OpenHuman.AppImage`    |
| Linux ARM64 | `OpenHuman_{ver}_aarch64.AppImage`              | `bin/linux-arm64/OpenHuman.AppImage`  |
| Windows x64 | `OpenHuman_{ver}_x64-setup.exe`                 | `bin/windows-x64/OpenHuman-setup.exe` |

It also downloads **cc-switch** GUI for each platform if available from the
`cc-switch-assets` release.

### After running

- **macOS**: double-click `OpenHumanPortable.command` or run `./OpenHumanPortable.command`
- **Linux**: run `./OpenHumanPortable.sh`
- **Windows**: run `bin\windows-x64\OpenHuman-setup.exe` or `OpenHumanPortable.bat`

### Notes

- Version auto-resolution uses the GitHub API (`tinyhumansai/openhuman` latest release).
- Fallback: specify `--version` manually if the API is unreachable.
- Upstream repo: https://github.com/tinyhumansai/openhuman
