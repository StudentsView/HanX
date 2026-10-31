# Windows and Linux distribution

HanX 2.9 uses the same local Swift document, spreadsheet, conversion and MCP engine on macOS, Windows and Linux. macOS retains its native AppKit application. Windows and Linux use an Electron application with a sandboxed renderer and a narrow IPC interface to the native engine.

## Install

```sh
npm install -g @juyoungsuh/hanx
hanx setup
```

The setup screen offers CLI, GUI or both. Use `hanx setup --components all --yes` for unattended installation; `cli` and `gui` are also accepted. Ordinary npm lifecycle output is usually not a terminal, so it installs the CLI and prints the setup command rather than waiting for invisible input. Homebrew uses the same setup launcher after `brew install StudentsView/tap/hanx`. Homebrew is available on macOS and Linux; Windows uses npm or the native setup wizard.

GUI-only retains the small `hanx setup` / `hanx gui` launcher and disables terminal document commands. The GUI keeps its private native engine for editing and AI connections. Setup downloads matching versioned release files and verifies SHA256 before installation. Existing unowned files are preserved.

## Windows x64

`HanX-2.9.0-win32-x64-Setup.exe` is a per-user NSIS wizard with GUI/CLI/both selection. Silent installation accepts `/S /COMPONENTS=cli`, `gui` or `all`. CLI-only omits Electron. GUI-only does not expose the private engine on PATH. Uninstall removes only PATH entries owned by HanX and preserves unrelated entries. Open a new terminal after installation.

`HanX-CLI-2.9.0-win32-x64.zip` contains the standalone CLI, Swift runtime DLLs, documentation and notices. Extract the whole archive to a permanent folder and add that folder to user PATH. Runtime DLLs must stay beside `hanx.exe`; no Swift developer toolchain is required. Windows packages are unsigned.

For a native build, install Swift 6.2.1 with its Windows prerequisites and Node.js 22, then run:

```powershell
swift build -c release
./packaging/windows/stage-cli.ps1
./packaging/windows/test-path.ps1
python packaging/windows/test-console.py build/platform/cli/hanx.exe
python packaging/smoke-cli.py build/platform/cli/hanx.exe --pdf
cd desktop
npm ci
npm test
npx electron-builder --win nsis --publish never
```

Staging includes the runtime dependency closure and tests execution with developer tools removed from PATH. Native CI also checks console arrows, Korean dropped paths, cancellation, all installer component choices, PATH ownership and uninstall.

## Linux x64

The initial build targets Ubuntu 22.04 x64 or a compatible newer system. glibc and Electron system libraries remain system dependencies. AppImage may require FUSE 2 (`libfuse2` on Ubuntu 22.04). The release contains `HanX-2.9.0-linux-x64.AppImage`, a `.deb`, and `HanX-CLI-2.9.0-linux-x64.tar.gz`. ARM64 Windows/Linux binaries are not included in this release.

Extract the CLI archive and run `./install-cli.sh`; it offers CLI, GUI or both. Unattended CLI installation accepts `--components cli --yes --prefix /path/to/prefix`. The default prefix is `~/.local`; add `~/.local/bin` to PATH. Keep the launcher, `hanx-engine` and `lib/` together. The launcher resolves installed symlinks and selects its own runtime libraries. GUI setup installs a per-user AppImage and desktop entry. Debian packages install the desktop and private engine; independent CLI installation remains available through setup.

```sh
swift build -c release
python3 packaging/linux/stage-cli.py
python3 packaging/linux/test-installer.py
python3 packaging/smoke-cli.py build/platform/cli/hanx --pdf
cd desktop
npm ci
npm test
xvfb-run -a node_modules/.bin/electron . --no-sandbox --smoke-test
npx electron-builder --linux AppImage deb --publish never
```

## PDF and AI tools

Windows/Linux PDF output uses a local LibreOffice installation. PDF text import uses Poppler (`pdfinfo`, `pdftotext`). They are separate optional applications. Setup installs them only when selected, or with `--pdf-dependencies`; Debian/Ubuntu users can also run `sudo apt-get install libreoffice poppler-utils fonts-noto-cjk`. Use `hanx capabilities --pretty` to check availability. macOS native builds include their existing PDF processing.

`hanx mcp` and the desktop AI connection panel expose the local engine to compatible AI agents. No cloud document upload or built-in model account is required. The CLI archive includes its guide and examples so MCP guide paths work outside the source checkout.

## Verification and release

`.github/workflows/platforms.yml` builds on Windows 2022 and Ubuntu 22.04. It verifies office round trips, Korean paths, PDF conversion, formulas, MCP, native GUI editing/saving, runtime staging and installation choices before producing release candidates. `verify-release.yml` checks the published npm installation and downloaded GUI on the same platforms. Public assets and `hanx-install-manifest.json` must share the exact package version and filenames; Homebrew hashes are generated from those tested assets.
