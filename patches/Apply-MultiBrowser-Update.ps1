param([string]$InstallDir)

$ErrorActionPreference = "Stop"
$payloadRoot = Join-Path $PSScriptRoot "payload\runtime\Lib\site-packages\AutoCua"
$payloadNative = Join-Path $payloadRoot "agent_native.pyd"
$payloadBrowser = Join-Path $payloadRoot "utils\chrome.py"

foreach ($path in @($payloadNative, $payloadBrowser)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Update payload is missing: $path. Extract the complete ZIP first." }
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if (Test-Path (Join-Path $PSScriptRoot "autocua.exe")) {
        $InstallDir = $PSScriptRoot
    } else {
        Write-Host "Enter the folder containing your existing autocua.exe."
        $InstallDir = Read-Host "AutoCua folder"
    }
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir.Trim('"'))
$exe = Join-Path $InstallDir "autocua.exe"
$targetRoot = Join-Path $InstallDir "runtime\Lib\site-packages\AutoCua"
$targetNative = Join-Path $targetRoot "agent_native.pyd"
$targetBrowser = Join-Path $targetRoot "utils\chrome.py"

if (!(Test-Path -LiteralPath $exe)) {
    throw "autocua.exe was not found in '$InstallDir'. Select the root of the existing portable installation."
}
foreach ($path in @($targetNative, $targetBrowser)) {
    if (!(Test-Path -LiteralPath $path)) {
        throw "The expected AutoCua runtime file was not found: $path. This update requires the earlier full portable build."
    }
}

if (Get-Process -Name "autocua" -ErrorAction SilentlyContinue) {
    throw "Close AutoCua completely before applying this update, then run the updater again."
}

$backupNative = "$targetNative.before-multi-browser.bak"
$backupBrowser = "$targetBrowser.before-multi-browser.bak"
if (!(Test-Path -LiteralPath $backupNative)) { Copy-Item -LiteralPath $targetNative -Destination $backupNative }
if (!(Test-Path -LiteralPath $backupBrowser)) { Copy-Item -LiteralPath $targetBrowser -Destination $backupBrowser }

Copy-Item -LiteralPath $payloadNative -Destination $targetNative -Force
Copy-Item -LiteralPath $payloadBrowser -Destination $targetBrowser -Force

Write-Host ""
Write-Host "Multi-browser support installed successfully."
Write-Host "Only the native browser module and browser-discovery helper were replaced."
Write-Host "Your Python runtime and installed dependencies were left untouched."
Write-Host "Backups: $backupNative ; $backupBrowser"
Write-Host ""
Write-Host "Auto-detection checks Chrome, Edge, Brave, Chromium, Vivaldi, Opera and Yandex."
Write-Host "To explicitly select one browser, add this line to %APPDATA%\AutoCua_data\.env:"
Write-Host '  AUTOCUA_BROWSER=C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe'
Write-Host "Use the actual executable path for your preferred browser."
Write-Host "Firefox and Safari are not supported by this Chromium DevTools/extension backend."
