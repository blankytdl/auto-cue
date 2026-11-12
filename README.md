# AutoCua — portable Rust Windows launcher

This repository packages [AutoCua](https://github.com/ComputerUseAgent/AutoCua) with a native Rust Windows x64 launcher.

## Full portable download

Open **Actions → Build AutoCua Portable Windows App → Artifacts** and download **AutoCua-Windows-x64-Portable**. Extract the entire ZIP folder and run `autocua.exe`.

**Python 3.13, AutoCua itself, its compiled Rust/PyO3 extension, and the Windows Python dependencies are installed by GitHub Actions and included in the portable ZIP.** The first launch does not download Python, uv, pip packages, or AutoCua. Do not copy only the EXE out of the folder: it expects the adjacent `runtime/` directory.

Versioned releases are published automatically when a `v*` tag is pushed. The release includes the portable ZIP and its SHA-256 checksum.

## What is and is not bundled

Bundled:
- CPython 3.13 runtime
- AutoCua from the upstream submodule pinned in this repository
- AutoCua's maturin-built native Rust extension
- Upstream Windows requirements and Python dependencies, including the desktop UI toolkit and image/recording libraries
- Rust `autocua.exe` launcher

Not bundled:
- Model-provider API keys or accounts. Configure credentials in the AutoCua UI or `%APPDATA%\AutoCua_data\.env`.
- Google Chrome. Upstream AutoCua does not install Chrome; install it separately only for browser/web-agent use.
- Windows WebView2 Runtime, which is an OS-level webview prerequisite.

The portable package contains the upstream license and third-party notices. Kernel-level optional drivers are not silently installed.

## User data

Credentials, conversations, browser profiles and settings are stored outside the extracted application folder:

```text
%APPDATA%\AutoCua_data\
```

You can move the extracted app folder; user data stays in the Windows profile. To update the application, download and extract the newest portable ZIP.

## Build

GitHub Actions builds on `windows-latest`:
1. Checks out this repo and the pinned `AutoCua/` submodule.
2. Installs Rust and a packaging-only Python 3.13.
3. Builds AutoCua's PyO3 extension and installs all Windows runtime dependencies into the copied Python runtime.
4. Smoke-tests imports using the copied runtime.
5. Builds the Rust launcher and creates the portable ZIP.

Local launcher build:

```powershell
cargo build --manifest-path rust-launcher/Cargo.toml --release --target x86_64-pc-windows-msvc
```

## Upstream source

- https://github.com/ComputerUseAgent/AutoCua
- Pinned as the `AutoCua/` Git submodule.
- Upstream AutoCua is MIT licensed. See `LICENSE-AutoCua.txt`, `THIRD_PARTY_NOTICES.md` and `THIRD_PARTY_LICENSES.txt` in the portable distribution.
