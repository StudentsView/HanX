# Windows and Linux distribution

This source tree contains Windows and Linux build and packaging support. Installer binaries are produced by native CI jobs; the presence of these scripts does not mean a Windows or Linux build has been executed successfully. macOS packaging continues to use the existing build scripts.

## Windows

The Electron desktop package uses an NSIS installation wizard with destination selection and a per-user installation. The bundled `resources/cli/hanx.exe` works independently of the GUI. The installer appends that folder to the current user's PATH; open a new terminal after installation. Uninstallation removes the entry only if HanX added it. Existing PATH values, variable references, machine PATH and unrelated entries are preserved. An existing user entry is left intact. Installer warnings explain manual PATH recovery if the helper cannot run.

A standalone `hanx-cli-win32-x64.zip` contains the same CLI and runtime DLLs. Extract the entire archive to a permanent folder and add that folder to your user PATH through Windows Settings. Do not copy only `hanx.exe`: Swift runtime DLLs must stay next to it. No developer toolchain is needed to run the staged CLI. x64 is the first CI target; ARM64 launcher support requires a separately built native archive.

For local builds, install the [Swift Windows prerequisites](https://www.swift.org/install/windows/manual/) (Visual Studio C++ build tools, Windows SDK, Python 3.10 and Git), Swift 6.2.1 or compatible, and Node.js 22. Then run in PowerShell from the source root:

```powershell
swift build -c release
./packaging/windows/stage-cli.ps1
./packaging/windows/test-path.ps1
python packaging/smoke-cli.py build/platform/cli/hanx.exe
cd desktop
npm install
npm test
npx electron-builder --win nsis --publish never
```

Staging gathers runtime DLLs from Swift's reported runtime paths and Swift directories on PATH. If your toolchain stores them elsewhere, supply `-RuntimeDirectories @('C:\path\to\runtime\bin')`. Staging fails if `swiftCore.dll` is missing or the executable cannot run with the developer toolchain removed from PATH. The wizard uses `packaging/windows/installer.nsh` and `manage-path.ps1`; both are configured in the desktop builder. Windows packages are unsigned until a maintainer separately arranges code signing.

## Linux

CI targets Ubuntu 22.04 x64, producing an AppImage, a Debian package and an independent CLI tarball. Use a distribution at least as new as the build host because glibc remains a system dependency. The desktop requires the usual Electron system libraries; AppImage may additionally require FUSE 2 (`libfuse2` on Ubuntu 22.04). AppImages are executable files; use `chmod +x HanX*.AppImage` after downloading. Install Debian packages using your package manager so system dependencies are resolved.

For the standalone CLI, extract `hanx-cli-linux-x64.tar.gz`, run `./hanx --version` from the extracted folder, or run `./install-cli.sh` to install under `~/.local`. Ensure `~/.local/bin` is on PATH. An optional prefix argument supports another location. The installer refuses to overwrite an existing CLI. It prints exact uninstall locations. Keep the `hanx` launcher, `hanx-engine` and `lib/` together: the launcher sets the private library search path without changing your shell configuration.

Native Linux build:

```sh
swift build -c release
python3 packaging/linux/stage-cli.py
cp packaging/linux/install-cli.sh build/platform/cli/
python3 packaging/smoke-cli.py build/platform/cli/hanx
cd desktop
npm install
npm test
npx electron-builder --linux AppImage deb --publish never
```

Linux staging copies resolved non-glibc libraries, including the Swift runtime, beside the binary. Missing libraries cause staging to fail. Builds and smoke tests must run on Linux; macOS cannot produce a verified Linux Swift executable. Runtime dependencies and their applicable licenses must be audited before publicly distributing newly generated bundles.

## Optional PDF features

Portable office editing and spreadsheet formulas do not require LibreOffice. PDF export uses LibreOffice's headless conversion; PDF extraction uses Poppler `pdftotext` and `pdfinfo`. Install these separately and ensure the executables are on PATH (Ubuntu: `sudo apt-get install libreoffice poppler-utils`). On Windows, use trusted LibreOffice and Poppler installations and add their executable folders to your user PATH. These applications are not bundled. Capabilities report unavailable features; unsupported rendering is not silently substituted. The original macOS rendering remains available through the macOS application.

## npm and CI artifacts

The npm launcher selects `native/<platform>-<architecture>/hanx` (`hanx.exe` on Windows), with adjacent runtime files. Supported selectors are `darwin`, `linux`, `win32` and `x64`, `arm64`. Selector support does not imply every binary is present: missing builds produce a JSON `native_binary_missing` error identifying the exact expected path. The legacy macOS universal `native/hanx` fallback remains intact. No post-install downloader or cross-platform placeholder executable is used.

The `Native Windows and Linux packages` workflow runs on matching pull requests or manual dispatch. It builds native Swift code, stages runtimes, checks office round trips/conversion and MCP, tests Windows PATH ownership and the npm launcher, and packages the desktop. Artifacts are uploaded to the workflow run, never automatically published as releases or to npm. Each job's npm tarball contains its own built platform; combining platform directories into one npm package is a separate maintainer step. Review Windows wizard install/uninstall and Linux desktop opening/editing/saving on native machines before release. The workflow requires this source checkout to be placed in an authorized GitHub repository before it can run.
