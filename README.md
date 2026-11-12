# AutoCua — Rust Windows launcher

This repository contains a Windows x64 Rust launcher for [AutoCua](https://github.com/ComputerUseAgent/AutoCua), plus the upstream project pinned as the `AutoCua/` Git submodule.

## What is built

GitHub Actions builds `autocua.exe` with the stable Rust MSVC toolchain on a Windows runner. The EXE is uploaded as a workflow artifact. Pushing a tag such as `v0.1.0` also publishes the EXE as a GitHub Release asset.

The launcher is a native Rust bootstrapper, **not a complete Rust rewrite of the AutoCua agent**. It downloads Astral's official `uv` tool, installs a private Python 3.13 runtime, installs the published AutoCua package and opens its desktop UI. This avoids requiring Python to be preinstalled by the user. Internet access is required on first launch and a supported model provider/API credential is still required by AutoCua.

## Download

Open **Actions → Build AutoCua Rust EXE → Artifacts** for the latest build, or **Releases** for versioned builds.

## Run

Double-click `autocua.exe`. First launch downloads the runtime and dependencies. User data and credentials are stored separately under `%APPDATA%\AutoCua_data`.

Run `autocua.exe --update` to upgrade the AutoCua package in the private environment.

## Build locally

Install the stable Rust MSVC toolchain and run:

```powershell
cargo build --manifest-path rust-launcher/Cargo.toml --release --target x86_64-pc-windows-msvc
```

Output: `rust-launcher/target/x86_64-pc-windows-msvc/release/autocua.exe`.

## Upstream

- Source: https://github.com/ComputerUseAgent/AutoCua
- Upstream is pinned as the `AutoCua/` submodule. Update it with `git submodule update --remote AutoCua`.
- AutoCua is MIT-licensed. Keep upstream `LICENSE`, `THIRD_PARTY_NOTICES.md` and `THIRD_PARTY_LICENSES.txt` available when redistributing upstream files.
