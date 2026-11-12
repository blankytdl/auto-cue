use reqwest::blocking::Client;
use std::env;
use std::error::Error;
use std::fs::{self, File};
use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::time::Duration;
use zip::ZipArchive;

type AppResult<T> = Result<T, Box<dyn Error>>;

const UV_WINDOWS_ZIP: &str =
    "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip";
const PYTHON_VERSION: &str = "3.13";
const PACKAGE: &str = "AutoCua";

fn app_dir() -> AppResult<PathBuf> {
    let local = env::var_os("LOCALAPPDATA")
        .ok_or("LOCALAPPDATA is not set; this launcher is intended for Windows 10/11 x64")?;
    Ok(PathBuf::from(local).join("AutoCua-Rust"))
}

fn run(program: &Path, args: &[String], cwd: &Path) -> AppResult<()> {
    println!("\n> {} {}", program.display(), args.join(" "));
    let status = Command::new(program)
        .args(args)
        .current_dir(cwd)
        .env("UV_CACHE_DIR", cwd.join("cache"))
        .env("UV_PYTHON_INSTALL_DIR", cwd.join("python"))
        .env("UV_PYTHON_DOWNLOADS", "automatic")
        .status()?;

    if !status.success() {
        return Err(format!("Command failed with exit code: {}", status).into());
    }
    Ok(())
}

fn download_uv(destination: &Path) -> AppResult<()> {
    println!("[1/4] Downloading the official Astral uv Windows x64 tool...");
    let client = Client::builder()
        .user_agent("AutoCua-Rust-Launcher/0.1")
        .timeout(Duration::from_secs(180))
        .build()?;
    let response = client.get(UV_WINDOWS_ZIP).send()?.error_for_status()?;
    let bytes = response.bytes()?;
    let mut archive = ZipArchive::new(Cursor::new(bytes))?;

    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        let name = entry.name().replace('\\', "/");
        if name == "uv.exe" || name.ends_with("/uv.exe") {
            let mut output = File::create(destination)?;
            std::io::copy(&mut entry, &mut output)?;
            output.flush()?;
            println!("[OK] uv saved to {}", destination.display());
            return Ok(());
        }
    }

    Err("The official uv archive did not contain uv.exe".into())
}

fn set_autocua_environment(data_dir: &Path) {
    // Keep credentials, conversations and browser profiles separate from the
    // launcher/venv so runtime upgrades never erase user data.
    env::set_var("AutoCua_DATA_DIR", data_dir);
    env::set_var("AutoCua_ENV_FILE", data_dir.join(".env"));

    // Use AutoCua's pywebview desktop shell instead of downloading Electron.
    env::set_var("AUTOCUA_UI", "webview");
    env::set_var("PYTHONUTF8", "1");
}

fn python_exe(venv: &Path) -> PathBuf {
    venv.join("Scripts").join("python.exe")
}

fn python_can_import(python: &Path, cwd: &Path) -> bool {
    Command::new(python)
        .args(["-c", "import AutoCua.agent_launcher, dotenv"])
        .current_dir(cwd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn install_or_update(uv: &Path, base: &Path, venv: &Path, update: bool) -> AppResult<()> {
    println!("[2/4] Preparing a private Python {PYTHON_VERSION} runtime...");
    run(
        uv,
        &[
            "python".to_string(),
            "install".to_string(),
            PYTHON_VERSION.to_string(),
        ],
        base,
    )?;

    println!("[3/4] Preparing AutoCua and its Windows dependencies...");
    run(
        uv,
        &[
            "venv".to_string(),
            "--python".to_string(),
            PYTHON_VERSION.to_string(),
            venv.to_string_lossy().into_owned(),
        ],
        base,
    )?;

    let python = python_exe(venv);
    if update || !python_can_import(&python, base) {
        run(
            uv,
            &[
                "pip".to_string(),
                "install".to_string(),
                "--python".to_string(),
                python.to_string_lossy().into_owned(),
                "--upgrade".to_string(),
                PACKAGE.to_string(),
            ],
            base,
        )?;
    } else {
        println!("[OK] AutoCua is already installed. Use --update to upgrade it.");
    }

    if !python_can_import(&python, base) {
        return Err(
            "AutoCua was installed, but its Python modules could not be imported. \
             Run autocua.exe --update and inspect the installation error above."
                .into(),
        );
    }

    Ok(())
}

fn launch_ui(python: &Path, base: &Path, data: &Path) -> AppResult<()> {
    println!("[4/4] Starting the AutoCua desktop UI...");
    let code = concat!(
        "import os; from dotenv import load_dotenv; ",
        "load_dotenv(os.environ.get('AutoCua_ENV_FILE')); ",
        "from AutoCua.agent_launcher import run_agent; ",
        "run_agent('computer use', '', '', '', ui=True)"
    );

    let status = Command::new(python)
        .arg("-c")
        .arg(code)
        .current_dir(base)
        .env("AutoCua_DATA_DIR", data)
        .env("AutoCua_ENV_FILE", data.join(".env"))
        .env("AUTOCUA_UI", "webview")
        .env("PYTHONUTF8", "1")
        .status()?;

    if !status.success() {
        return Err(format!("AutoCua exited with status {status}").into());
    }

    Ok(())
}

fn execute() -> AppResult<()> {
    if !cfg!(all(target_os = "windows", target_arch = "x86_64")) {
        return Err("This build is intended for Windows x64 only.".into());
    }

    let update = env::args().skip(1).any(|arg| {
        arg.eq_ignore_ascii_case("--update") || arg.eq_ignore_ascii_case("/update")
    });

    let base = app_dir()?;
    let data = env::var_os("APPDATA")
        .map(PathBuf::from)
        .unwrap_or_else(|| base.clone())
        .join("AutoCua_data");

    fs::create_dir_all(&base)?;
    fs::create_dir_all(&data)?;
    fs::create_dir_all(base.join("cache"))?;
    set_autocua_environment(&data);

    let uv = base.join("uv.exe");
    if !uv.is_file() {
        download_uv(&uv)?;
    }

    let venv = base.join("venv");
    install_or_update(&uv, &base, &venv, update)?;
    launch_ui(&python_exe(&venv), &base, &data)
}

fn main() -> ExitCode {
    println!("AutoCua — Rust Windows launcher\n================================");
    println!("First launch requires Internet to download the private runtime and dependencies.");

    match execute() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("\nERROR: {error}");
            eprintln!("Tip: run autocua.exe --update to repair/update the AutoCua environment.");
            eprintln!("Press Enter to close...");
            let mut input = String::new();
            let _ = std::io::stdin().read_line(&mut input);
            ExitCode::FAILURE
        }
    }
}
