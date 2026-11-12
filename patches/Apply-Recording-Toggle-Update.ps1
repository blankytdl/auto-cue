param(
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"
$payloadRoot = Join-Path $PSScriptRoot "payload\runtime\Lib\site-packages\AutoCua\ui"

$relativeFiles = @(
    "service.py",
    "script.js",
    "css\style.css"
)
foreach ($relative in $relativeFiles) {
    if (!(Test-Path -LiteralPath (Join-Path $payloadRoot $relative))) {
        throw "Update payload is missing: $relative. Extract the complete ZIP first."
    }
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
if (!(Test-Path -LiteralPath (Join-Path $InstallDir "autocua.exe"))) {
    throw "autocua.exe was not found in '$InstallDir'. Choose the portable app's root folder."
}

$targetRoot = Join-Path $InstallDir "runtime\Lib\site-packages\AutoCua\ui"
if (!(Test-Path -LiteralPath (Join-Path $targetRoot "service.py"))) {
    throw "The packaged AutoCua UI was not found at '$targetRoot'. This update requires the full portable build."
}

foreach ($relative in $relativeFiles) {
    $source = Join-Path $payloadRoot $relative
    $target = Join-Path $targetRoot $relative
    $parent = Split-Path -Parent $target
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    $backup = "$target.before-recording-toggle.bak"
    if (!(Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $target -Destination $backup
    }
    Copy-Item -LiteralPath $source -Destination $target -Force
    Write-Host "Updated $relative"
}

Write-Host ""
Write-Host "Recording switch update installed."
Write-Host "Restart AutoCua and open Settings → Recording."
Write-Host "Recording is OFF by default. Existing recordings have not been deleted."
Write-Host "Backups are stored beside the updated files with .before-recording-toggle.bak."
