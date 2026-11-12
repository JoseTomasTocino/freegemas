param(
    [string]$Sdk = $env:LLVM_MOS_SDK
)
$ErrorActionPreference = "Stop"
if (-not $Sdk) { throw "LLVM-MOS SDK bin directory not specified. Pass -Sdk <llvm-mos-sdk>/bin or set LLVM_MOS_SDK." }
$root = Split-Path -Parent $PSScriptRoot
$here = $PSScriptRoot
$src = Join-Path $here "src"
$build = Join-Path $here "build"
$hostfs = Join-Path $here "hostfs"

$clang = Join-Path $Sdk "mos-cx16-clang.bat"
if (-not (Test-Path $clang)) { throw "mos-cx16-clang.bat not found under $Sdk" }
$env:PATH = "$Sdk;" + $env:PATH

Remove-Item $build -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $hostfs -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $build | Out-Null
New-Item -ItemType Directory -Force $hostfs | Out-Null

python (Join-Path $here "tools\build_assets.py")
python (Join-Path $here "tools\build_effects.py")

$base = @("-Oz", "-mcpu=mosw65c02", "-DVERA_BASE=0x9F20", "-I$src")
$link3 = Join-Path $src "link3000.ld"
$link2 = Join-Path $src "link2000.ld"

function Build-Overlay([string]$name, [string[]]$sources, [string[]]$defines = @()) {
    $map = "-Wl,-Map=$build\$name.bin.map"
    & $clang @base @defines -T $link3 -o "$build\$name.bin" @sources $map
    if ($LASTEXITCODE -ne 0) { throw "link failed: $name" }
}

$game = @("$src\main.c", "$src\board.c", "$src\effects.c", "$src\music.c",
          "$src\sound.c", "$src\menu_mouse.c",
          "$src\x16_input.c", "$src\x16_disk.c", "$src\x16_platform.s",
          "$src\pcm_feed.S")
$menus = @("$src\menu_screen.c", "$src\menu_mouse.c", "$src\x16_input.c",
           "$src\x16_platform.s")

Build-Overlay "game" $game
Build-Overlay "title" @("$src\title.c", "$src\menu_mouse.c", "$src\x16_input.c",
                        "$src\x16_platform.s")
Build-Overlay "howto" $menus
Build-Overlay "options" $menus @("-DOPTIONS_SCREEN")
Build-Overlay "intro" @("$src\intro.c", "$src\x16_input.c", "$src\x16_platform.s")

& $clang @base -T $link2 -o "$build\loader.bin" @("$src\loader.c", "$src\x16_platform.s") "-Wl,-Map=$build\loader.bin.map"
if ($LASTEXITCODE -ne 0) { throw "link failed: loader" }

# HostFS is case-sensitive: every name the KERNAL sees is lower-case.
Copy-Item "$build\loader.bin" "$hostfs\loader"
foreach ($n in @("game", "title", "howto", "options", "intro")) {
    Copy-Item "$build\$n.bin" "$hostfs\$n"
}
python (Join-Path $here "tools\make_boot.py")

# ZCM music.  It streams from HostFS, so the name must be lower-case.
Copy-Item "$here\assets\music.zcm" "$hostfs\music.zcm"

Write-Host ""
Get-ChildItem $build\*.bin | ForEach-Object { "{0,-12} {1,7} bytes" -f $_.Name, $_.Length }
Write-Host ("music.zcm    {0,7} bytes" -f (Get-Item "$here\assets\music.zcm").Length)
Write-Host "hostfs: $hostfs"
