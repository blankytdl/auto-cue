use std::env;
use std::error::Error;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

type AppResult<T> = Result<T, Box<dyn Error>>;

fn install_root() -> AppResult<PathBuf> {
    let exe = env::current_exe()?;
    let parent = exe
        .parent()
        .ok_or("Could not determine the folder containing autocua.exe")?;
    Ok(parent.to_path_buf())
}

fn python_exe(root: &Path) -> PathBuf {
    root.join("runtime").join("python.exe")
}

fn data_root() -> PathBuf {
    let base = env::var_os("APPDATA")
        .map(PathBuf::from)
        .or_else(|| env::var_os("USERPROFILE").map(|p| PathBuf::from(p).join("AppData").join("Roaming")))
        .unwrap_or_else(env::temp_dir);
    base.join("AutoCua_data")
}

fn configure_environment(root: &Path, data: &Path) {
    let runtime = root.join("runtime");
    let site = runtime.join("Lib").join("site-packages");

    // All application dependencies are shipped beside this EXE in the portable
    // release archive. No Python, uv, pip, or AutoCua package download is done
    // on the user's computer.
    env::set_var("PYTHONHOME", &runtime);
    env::set_var("PYTHONPATH", &site);
    env::set_var("PYTHONUTF8", "1");
    env::set_var("AutoCua_DATA_DIR", data);
    env::set_var("AutoCua_ENV_FILE", data.join(".env"));
    env::set_var("AUTOCUA_UI", "webview");

    let mut paths = vec![
        runtime.clone(),
        runtime.join("DLLs"),
        runtime.join("Scripts"),
        site.clone(),
        site.join("pywin32_system32"),
        site.join("PySide6"),
        site.join("PySide6").join("Qt").join("bin"),
    ];
    if let Some(existing) = env::var_os("PATH") {
        paths.extend(env::split_paths(&existing));
    }
    if let Ok(value) = env::join_paths(paths) {
        env::set_var("PATH", value);
    }
}

fn check_bundle(root: &Path, python: &Path) -> AppResult<()> {
    let required = [
        python.to_path_buf(),
        root.join("runtime").join("python313.dll"),
        root.join("runtime").join("Lib").join("site-packages").join("AutoCua"),
    ];
    for path in required {
        if !path.exists() {
            return Err(format!(
                "The portable dependency bundle is incomplete. Missing: {}\n\
                 Extract the entire AutoCua-Windows-x64-Portable.zip; do not copy autocua.exe alone.",
                path.display()
            ).into());
        }
    }

    let status = Command::new(python)
        .args([
            "-c",
            "import AutoCua.agent_launcher, dotenv, webview, PySide6",
        ])
        .current_dir(root)
        .status()?;

    if !status.success() {
        return Err(
            "The bundled Python runtime or one of AutoCua's packaged dependencies failed to import. \
             Re-extract the complete portable ZIP. No dependency download is attempted."
                .into(),
        );
    }
    Ok(())
}

fn launch_ui(python: &Path, root: &Path, data: &Path) -> AppResult<()> {
    println!("[2/2] Starting AutoCua...");
    let code = concat!(
        "from dotenv import load_dotenv; ",
        "import os; load_dotenv(os.environ.get('AutoCua_ENV_FILE')); ",
        "from AutoCua.agent_launcher import run_agent; ",
        "run_agent('computer use', '', '', '', ui=True)"
    );

    let status = Command::new(python)
        .arg("-c")
        .arg(code)
        .current_dir(root)
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
        return Err("This portable build is intended for Windows x64.".into());
    }

    let root = install_root()?;
    let data = data_root();
    std::fs::create_dir_all(&data)?;

    let python = python_exe(&root);
    println!("AutoCua — portable Windows x64\n================================");
    println!("Checking the bundled Python runtime and dependencies...");
    configure_environment(&root, &data);
    check_bundle(&root, &python)?;

    if env::args().skip(1).any(|arg| arg.eq_ignore_ascii_case("--update")) {
        println!("\nThis release is self-contained. To update AutoCua, download and extract the newest portable ZIP.");
        return Ok(());
    }

    println!("[1/2] All bundled dependencies are present.");
    launch_ui(&python, &root, &data)
}

fn main() -> ExitCode {
    match execute() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("\nERROR: {error}");
            eprintln!("\nMake sure you extracted the complete AutoCua-Windows-x64-Portable.zip.");
            eprintln!("The launcher does not download Python or package dependencies.");
            eprintln!("Press Enter to close...");
            let mut input = String::new();
            let _ = std::io::stdin().read_line(&mut input);
            ExitCode::FAILURE
        }
    }
}
