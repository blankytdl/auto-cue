# AutoCua — portable Rust Windows launcher

This repository packages [AutoCua](https://github.com/ComputerUseAgent/AutoCua) with a native Rust Windows x64 launcher.

## Llama Prism update (small download)

For an existing installation of the earlier **AutoCua-Windows-x64-Portable** bundle, use the latest workflow artifact **AutoCua-LlamaPrism-Update** instead of downloading the full runtime again.

The update ZIP contains only the changed `service.py` module, an updater PowerShell script, and instructions. It does not contain Python, the `runtime/` directory, DLLs, pip packages, or the Rust launcher.

1. Download `AutoCua-LlamaPrism-Update.zip` from the latest [Build AutoCua Llama Prism Update workflow](https://github.com/blankytdl/auto-cue/actions/workflows/build-rust-exe.yml).
2. Extract it to a temporary folder (or directly into your existing AutoCua folder).
3. Run `Apply-LlamaPrism-Update.ps1`. When asked, enter the folder containing your existing `autocua.exe`.
4. The updater backs up and replaces only the Ollama provider module in your existing Python runtime.

No runtime dependencies are downloaded or reinstalled. This update is not a fresh standalone install; it requires the previous full portable build to already be extracted on the PC.

For local llama.cpp / Llama Prism, put `OLLAMA_HOST=127.0.0.1:8080` in `%APPDATA%\AutoCua_data\.env`, start llama-prism with a tool-capable chat template (usually `--jinja`), then restart AutoCua and choose provider `ollama`.

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

## Use a local llama-prism / llama.cpp server

The portable build includes a compatibility patch for the existing **ollama** provider. It can discover models from the OpenAI-compatible `/v1/models` route and send chat/tool/image requests to a local `llama-server.exe`. You do not need to install or run Ollama.

1. Start your Llama Prism server on the same PC, listening on `127.0.0.1:8080`. For computer-use tool calls, start it with `--jinja` so the server uses the model's tool-aware chat template.
2. Verify its model list in PowerShell:

   ```powershell
   curl.exe http://127.0.0.1:8080/v1/models
   ```

3. Open `%APPDATA%\AutoCua_data\.env` and add:

   ```dotenv
   OLLAMA_HOST=127.0.0.1:8080
   ```

   If your server was started with an API key, also add `OLLAMA_API_KEY=your-key`. Do not put a key in the repository or share it.

4. Restart AutoCua. In **Settings → Model Selection**, choose provider **ollama** and then select the exact model ID shown by `/v1/models`.

For screen/desktop automation, choose a vision-capable GGUF and load its matching mmproj. For tool use, the model's chat template must support tool calls; `--jinja` enables llama.cpp's OpenAI-style function-calling path, but some model templates are more reliable than others. The compatibility layer can list models but cannot make a text-only model understand screenshots or give a model a missing tool-use template.

The local endpoint is kept on loopback (`127.0.0.1`); the API key is optional unless you enabled server authentication.

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
