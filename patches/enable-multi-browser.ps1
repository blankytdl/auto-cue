$ErrorActionPreference = "Stop"

$rustPath = Join-Path $PSScriptRoot "..\AutoCua\AutoCua\web\browser\browser.rs"
$pythonPath = Join-Path $PSScriptRoot "..\AutoCua\AutoCua\utils\chrome.py"

foreach ($path in @($rustPath, $pythonPath)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Pinned AutoCua source file was not found: $path" }
}

$rust = [System.IO.File]::ReadAllText($rustPath)
if (!$rust.Contains("AUTOCUA_MULTI_BROWSER_SUPPORT")) {
    $relativePattern = '(?ms)^const CHROME_RELATIVE_WIN:.*?^];'
    $relativeReplacement = @'
const AUTOCUA_BROWSER_ENV: &str = "AUTOCUA_BROWSER";

// Chromium-family browser paths checked under Program Files / LOCALAPPDATA.
// Chrome remains the default; AUTOCUA_BROWSER lets the user choose another.
const CHROME_RELATIVE_WIN: &[&str] = &[
    r"Google\Chrome\Application\chrome.exe",
    r"Microsoft\Edge\Application\msedge.exe",
    r"BraveSoftware\Brave-Browser\Application\brave.exe",
    r"Chromium\Application\chrome.exe",
    r"Vivaldi\Application\vivaldi.exe",
    r"Opera\opera.exe",
    r"Programs\Opera\opera.exe",
    r"Opera GX\opera.exe",
    r"Programs\Opera GX\opera.exe",
    r"Yandex\YandexBrowser\Application\browser.exe",
];
'@

    $patched = [regex]::Replace(
        $rust, $relativePattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $relativeReplacement }, 1
    )
    if ($patched -eq $rust) { throw "Could not locate CHROME_RELATIVE_WIN in browser.rs; upstream source layout changed." }

    $findPattern = '(?ms)^pub\(crate\) fn find_chrome\(\) -> SResult<PathBuf> \{.*?(?=^/// The user agent)'
    $findReplacement = @'
pub(crate) fn find_chrome() -> SResult<PathBuf> {
    // AUTOCUA_MULTI_BROWSER_SUPPORT: an explicit path wins over auto-detection.
    if let Some(value) = std::env::var_os(AUTOCUA_BROWSER_ENV).filter(|v| !v.is_empty()) {
        let path = PathBuf::from(value);
        if path.is_file() {
            return Ok(path);
        }
        return Err(ScanErr::s(format!(
            "AUTOCUA_BROWSER points to a missing executable: {}",
            path.display()
        )));
    }

    for path in chrome_candidates() {
        if path.is_file() {
            return Ok(path);
        }
    }
    // Linux and custom Windows installs may expose a browser launcher on PATH.
    which("google-chrome")
        .or_else(|| which("google-chrome-stable"))
        .or_else(|| which("msedge"))
        .or_else(|| which("brave"))
        .or_else(|| which("chromium"))
        .or_else(|| which("chrome"))
        .or_else(|| which("vivaldi"))
        .or_else(|| which("opera"))
        .or_else(|| which("browser"))
        .ok_or_else(|| ScanErr::s(
            "no supported Chromium-based browser found; install Edge, Brave, Chrome, Chromium, Vivaldi, Opera or Yandex Browser"
        ))
}
'@

    $patched2 = [regex]::Replace(
        $patched, $findPattern,
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $findReplacement }, 1
    )
    if ($patched2 -eq $patched) { throw "Could not locate find_chrome in browser.rs; upstream source layout changed." }

    $rust = "// AUTOCUA_MULTI_BROWSER_SUPPORT" + [Environment]::NewLine + $patched2
    [System.IO.File]::WriteAllText($rustPath, $rust, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Patched the native browser selector."
} else {
    Write-Host "Native multi-browser patch is already applied."
}

$pythonSource = @'
"""Find an installed Chromium-family browser for AutoCua's CDP/extension agent."""

import os
import shutil
import sys
from pathlib import Path

BROWSER_ENV = "AUTOCUA_BROWSER"
MISSING = (
    "No supported Chromium-based browser was found. Install Microsoft Edge, "
    "Brave, Google Chrome, Chromium, Vivaldi, Opera or Yandex Browser."
)
POPUP = "No supported Chromium-based browser was found. Please install Edge, Brave or Chrome."
SAID = "AutoCua_BROWSER_MISSING_SAID"

_WIN_RELATIVE = (
    r"Google\Chrome\Application\chrome.exe",
    r"Microsoft\Edge\Application\msedge.exe",
    r"BraveSoftware\Brave-Browser\Application\brave.exe",
    r"Chromium\Application\chrome.exe",
    r"Vivaldi\Application\vivaldi.exe",
    r"Opera\opera.exe",
    r"Programs\Opera\opera.exe",
    r"Opera GX\opera.exe",
    r"Programs\Opera GX\opera.exe",
    r"Yandex\YandexBrowser\Application\browser.exe",
)


def _configured_path():
    value = (os.environ.get(BROWSER_ENV) or "").strip().strip('"')
    if not value:
        return None
    return Path(os.path.expandvars(os.path.expanduser(value)))


def _registry_candidates():
    """Find registered browser executables, including non-default install paths."""
    try:
        import winreg
    except ImportError:
        return []

    names = ("chrome.exe", "msedge.exe", "brave.exe", "vivaldi.exe",
             "opera.exe", "browser.exe")
    hives = (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE)
    views = tuple(dict.fromkeys((
        getattr(winreg, "KEY_WOW64_64KEY", 0),
        getattr(winreg, "KEY_WOW64_32KEY", 0),
        0,
    )))
    found = []
    seen = set()
    for hive in hives:
        for name in names:
            key_path = rf"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\{name}"
            for view in views:
                try:
                    with winreg.OpenKey(hive, key_path, 0, winreg.KEY_READ | view) as key:
                        value, _ = winreg.QueryValueEx(key, "")
                    candidate = Path(os.path.expandvars(str(value).strip().strip('"')))
                    marker = str(candidate).casefold()
                    if marker not in seen:
                        found.append(candidate)
                        seen.add(marker)
                except OSError:
                    pass
    return found


def _candidates():
    """Common install locations, registry registrations and PATH launchers."""
    if sys.platform == "win32":
        roots = [os.environ.get(k) for k in
                 ("ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA")]
        found = [Path(root) / relative
                 for relative in _WIN_RELATIVE
                 for root in roots if root]
        found.extend(_registry_candidates())
        for name in ("chrome", "msedge", "brave", "chromium", "vivaldi", "opera", "browser"):
            path = shutil.which(name)
            if path:
                found.append(Path(path))
        return found

    if sys.platform == "darwin":
        return [
            Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            Path("/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"),
            Path("/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"),
            Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
            Path("/Applications/Vivaldi.app/Contents/MacOS/Vivaldi"),
            Path.home() / "Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        ]

    found = []
    for name in ("google-chrome", "google-chrome-stable", "microsoft-edge",
                 "msedge", "brave-browser", "brave", "chromium", "chromium-browser",
                 "vivaldi", "opera"):
        path = shutil.which(name)
        if path:
            found.append(Path(path))
    return found + [Path("/opt/google/chrome/chrome"), Path("/usr/bin/google-chrome")]


def find_chrome():
    """Return the selected Chromium browser executable, or None."""
    configured = _configured_path()
    if configured is not None:
        return str(configured) if configured.is_file() else None
    for candidate in _candidates():
        if candidate.is_file():
            return str(candidate)
    return None


def _say(text):
    """Print safely even when stdout uses the Windows legacy code page."""
    try:
        print(text, flush=True)
    except UnicodeEncodeError:
        print(text.encode("ascii", "replace").decode("ascii"), flush=True)


def ensure_chrome():
    """Return a supported browser and pass its exact path to the Rust CDP layer."""
    configured = _configured_path()
    found = find_chrome()
    if found:
        os.environ[BROWSER_ENV] = found
        return found

    if not os.environ.get(SAID):
        os.environ[SAID] = "1"
        if configured is not None:
            _say(f"{BROWSER_ENV} points to a missing executable: {configured}")
        else:
            _say(f"{MISSING} (https://www.google.com/chrome/).")
    return None


if __name__ == "__main__":
    print(ensure_chrome() or "no supported Chromium browser")
'@

[System.IO.File]::WriteAllText($pythonPath, $pythonSource, [System.Text.UTF8Encoding]::new($false))
Write-Host "Updated Python browser discovery for Edge, Brave and other Chromium browsers."
