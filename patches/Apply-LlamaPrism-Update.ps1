param(
    [string]$InstallDir
)

$ErrorActionPreference = "Stop"

$payload = Join-Path $PSScriptRoot "payload\runtime\Lib\site-packages\AutoCua\llm_provider\ollama\service.py"
if (!(Test-Path -LiteralPath $payload)) {
    throw "Patch payload is missing: $payload. Extract the complete update ZIP first."
}

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if (Test-Path (Join-Path $PSScriptRoot "autocua.exe")) {
        $InstallDir = $PSScriptRoot
    } else {
        Write-Host "Enter the folder where you extracted the existing AutoCua portable build."
        $InstallDir = Read-Host "AutoCua folder"
    }
}

$InstallDir = [System.IO.Path]::GetFullPath($InstallDir.Trim('"'))
$exe = Join-Path $InstallDir "autocua.exe"
$target = Join-Path $InstallDir "runtime\Lib\site-packages\AutoCua\llm_provider\ollama\service.py"

if (!(Test-Path -LiteralPath $exe)) {
    throw "autocua.exe was not found in '$InstallDir'. Point -InstallDir to the root of your existing extracted AutoCua portable build."
}
if (!(Test-Path -LiteralPath $target)) {
    throw "The existing AutoCua Ollama provider was not found at '$target'. This update requires the previous full portable build."
}

$backup = "$target.before-llama-prism.bak"
if (!(Test-Path -LiteralPath $backup)) {
    Copy-Item -LiteralPath $target -Destination $backup
}
Copy-Item -LiteralPath $payload -Destination $target -Force

# Use the Llama Prism endpoint the portable setup expects, but never
# overwrite an endpoint the user has already configured.
$dataDir = Join-Path $env:APPDATA "AutoCua_data"
New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
$envFile = Join-Path $dataDir ".env"
$envLines = @()
if (Test-Path -LiteralPath $envFile) {
    $envLines = @(Get-Content -LiteralPath $envFile)
}
if (-not ($envLines | Where-Object { $_ -match '^\s*OLLAMA_HOST\s*=' })) {
    Add-Content -LiteralPath $envFile -Value "OLLAMA_HOST=127.0.0.1:8080" -Encoding utf8
    Write-Host "Configured OLLAMA_HOST=127.0.0.1:8080 in $envFile"
} else {
    Write-Host "Kept your existing OLLAMA_HOST setting in $envFile"
}

Write-Host ""
Write-Host "Llama Prism compatibility installed successfully."
Write-Host "Previous provider backup: $backup"
Write-Host "Existing Python runtime and dependencies were left untouched."
Write-Host ""
Write-Host "Next: add OLLAMA_HOST=127.0.0.1:8080 to %APPDATA%\AutoCua_data\.env,"
Write-Host "start llama-prism/llama-server with --jinja, and restart AutoCua."
