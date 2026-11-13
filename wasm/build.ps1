param(
    [string]$BuildDir = "build-wasm",
    [string]$Configuration = "Release",
    [string]$Emsdk = $env:EMSDK
)

$ErrorActionPreference = "Continue"
# Native tools such as emcmake write progress to stderr. Handle failures
# through $LASTEXITCODE instead of treating stderr as a terminating error.
$PSNativeCommandUseErrorActionPreference = $false

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($BuildDir)) {
    $BuildDir = Join-Path $RepoRoot $BuildDir
}

if ($Emsdk) {
    $envScript = Join-Path $Emsdk "emsdk_env.ps1"
    if (Test-Path $envScript) {
        # emsdk_env writes progress to stderr; don't turn that into a
        # terminating NativeCommandError under ErrorActionPreference=Stop.
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $envScript
        $ErrorActionPreference = $previousErrorAction
    }
}

if (-not (Get-Command emcmake -ErrorAction SilentlyContinue)) {
    throw "emcmake was not found. Install/activate the Emscripten SDK first (emsdk install latest; emsdk activate latest) and set EMSDK."
}
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw "cmake was not found. Install CMake 3.28 or newer and add it to PATH."
}
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    Write-Host "Ninja was not found; falling back to the default CMake generator."
}

New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

Push-Location $RepoRoot
try {
    $generator = @()
    if (Get-Command ninja -ErrorAction SilentlyContinue) {
        $generator = @("-G", "Ninja")
    }
    & emcmake cmake -S $RepoRoot -B $BuildDir @generator "-DCMAKE_BUILD_TYPE=$Configuration"
    if ($LASTEXITCODE -ne 0) { throw "CMake configuration failed." }

    & cmake --build $BuildDir --parallel
    if ($LASTEXITCODE -ne 0) { throw "Build failed." }
} finally {
    Pop-Location
}

$entry = Join-Path $BuildDir "freegemas.html"
if (-not (Test-Path $entry)) {
    throw "Expected build output at $entry"
}
Write-Host ""
Write-Host "Built: $entry"
Write-Host "Serve the directory over HTTP, for example:"
Write-Host "  python -m http.server 8000 --directory `"$BuildDir`""
Write-Host "Then open http://127.0.0.1:8000/freegemas.html"
