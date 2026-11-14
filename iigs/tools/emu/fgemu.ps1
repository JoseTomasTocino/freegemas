# fgemu.ps1 - portable helpers for driving GSSquared with a Freegemas IIGS image.
#
# Dot-source it first:
#   . .\iigs\tools\emu\fgemu.ps1
#   FG-Init; FG-Launch; FG-WaitUp; FG-Snap; FG-Key $FG_KEY.SPACE; FG-Quit
#
# Every machine path can be overridden with an environment variable, so the
# same scripts work on another PC:
#   FG_GS2    GSSquared.exe            (default C:\dev\emu\gssquared\GSSquared.exe)
#   FG_GS2CFG machine config .gs2      (default %USERPROFILE%\Documents\GSSquared\IIgs.gs2)
#   FG_IMG    2mg image to boot        (default <repo>\iigs\merlin32\build\freegemas.2mg)
#   FG_WORK   scratch dir + socket dir (default %TEMP%\fgemu)
#   FG_SOCK   socket file name         (default gs2-auto.sock)
#   FG_PYTHON python interpreter       (default python)
#
# The socket directory must be FG_WORK because Windows AF_UNIX binds with a
# parent path (the emulator is started with FG_WORK as its working directory).

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is only set at file scope; config lives in $global: so every
# function and every calling script sees the same values.
$global:FG_DIR = $PSScriptRoot

$global:FG_GS2   = if ($env:FG_GS2)    { $env:FG_GS2 }    else { 'C:\dev\emu\gssquared\GSSquared.exe' }
$global:FG_GS2CFG = if ($env:FG_GS2CFG) { $env:FG_GS2CFG } else { Join-Path $env:USERPROFILE 'Documents\GSSquared\IIgs.gs2' }
$global:FG_IMG   = if ($env:FG_IMG)    { $env:FG_IMG }    else { Join-Path $PSScriptRoot '..\..\merlin32\build\freegemas.2mg' }
$global:FG_WORK  = if ($env:FG_WORK)   { $env:FG_WORK }   else { Join-Path $env:TEMP 'fgemu' }
$global:FG_SOCK  = if ($env:FG_SOCK)   { $env:FG_SOCK }   else { 'gs2-auto.sock' }
$global:FG_PY    = if ($env:FG_PYTHON) { $env:FG_PYTHON } else { 'python' }

# SDL scancodes used by the game.
$global:FG_KEY = @{ W = 26; A = 4; S = 22; D = 7; H = 11; R = 21; SPACE = 44; ESC = 41 }

# dbgTab indices (0-based) as documented in iigs/AGENTS.md.
# Keep $global:FG_TABN in sync with the entry count in main.s (dbgTab).
$global:FG_TABN = 52
$global:FG_IDX = @{
    Score = 0; State = 8; MenuSel = 10; MouseX = 11; MouseY = 12; MCell = 14; cellgem = 15
    SndTot = 19; SndOk = 20; SndBad = 21; SndRegOk = 22; SndRegBad = 23
    SoundOn = 27; OptSel = 28; PtrOn = 32
    MusOn = 33; MusState = 34; MusOk = 35; MusBad = 36; MusBuf = 37; MusTotal = 38
    MusTick16 = 39; MusRead = 40; MusGuard = 41; MLogIdx = 42; MLogS = 43
    TrN = 44; TrB = 45; TrY0 = 46; TrY1 = 47; TrTick = 48; MusRestart = 49; EmOn = 50; EmBank = 51
}

function FG-Log([string]$m) { Write-Host ("[{0:HH:mm:ss}] {1}" -f (Get-Date), $m) }

function FG-Init {
    New-Item -ItemType Directory -Force $global:FG_WORK | Out-Null
    Add-Type -Path (Join-Path $global:FG_DIR 'gs2cli.cs')
    Get-Process GSSquared -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    Remove-Item (Join-Path $global:FG_WORK $global:FG_SOCK) -ErrorAction SilentlyContinue
    if (-not (Test-Path $global:FG_GS2)) { throw "GSSquared not found: $($global:FG_GS2) (set FG_GS2)" }
    if (-not (Test-Path $global:FG_IMG)) { throw "image not found: $($global:FG_IMG) (set FG_IMG)" }
}

# FG-Launch [-Audio <wav>] : boot the image; -Audio records the emulator output
# through SDL's disk driver (S16LE, 2 channels, 44100 Hz -> 176400 B/s).
function FG-Launch {
    param([string]$Audio = '')
    $env:SDL_AUDIODRIVER = $null
    $env:SDL_AUDIO_DISK_OUTPUT_FILE = $null
    if ($Audio) {
        $env:SDL_AUDIODRIVER = 'disk'
        $env:SDL_AUDIO_DISK_OUTPUT_FILE = $Audio
        Remove-Item $Audio -ErrorAction SilentlyContinue
    }
    $log = Join-Path $global:FG_WORK 'gs2.log'
    Start-Process $global:FG_GS2 -ArgumentList @(
        $global:FG_GS2CFG,
        "-ds7d1=$($global:FG_IMG)",
        '--debug', $global:FG_SOCK, '--no-quit-confirm') `
        -WorkingDirectory $global:FG_WORK -RedirectStandardOutput $log | Out-Null
    $ok = $false
    for ($i = 0; $i -lt 300 -and -not $ok; $i++) {
        try { if ([Gs2Cli]::ConnectAttempt($true, $global:FG_WORK, $global:FG_SOCK) -ge 0) { $ok = $true } } catch { }
        if (-not $ok) { Start-Sleep -Milliseconds 150 }
    }
    if (-not $ok) { throw "could not connect to the debug socket in $($global:FG_WORK)" }
    [Gs2Cli]::Hello() | Out-Null
}

# FG-WaitUp [-TimeoutSec 90] : wait until the game is live.
# Ready = NEWVIDEO $E1 (SHR on) and MILESTONE >= 7 ($019CFF, written by the game).
function FG-WaitUp {
    param([int]$TimeoutSec = 90)
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $TimeoutSec) {
        [Gs2Cli]::Pause() | Out-Null
        $nv = [Gs2Cli]::ReadMem(0, [uint32]0x01C029, 1)
        $ms = [Gs2Cli]::ReadMem(0, [uint32]0x019CFF, 1)
        [Gs2Cli]::Continue() | Out-Null
        if ($nv -and $ms -and [int]$nv[0] -eq 0xE1 -and [int]$ms[0] -ge 7) {
            $s = ((Get-Date) - $t0).TotalSeconds
            FG-Log ("up at {0:N1}s" -f $s)
            return $s
        }
        Start-Sleep -Milliseconds 700
    }
    throw 'game never reached SHR + MILESTONE 7'
}

# FG-Table : locate dbgTab (magic DE AD BE EF) and collect the 24-bit entry
# addresses. Entries are adrl values, so every read must dereference them.
function FG-Table {
    $magic = [byte[]](0xDE, 0xAD, 0xBE, 0xEF)
    $hits = @()
    # CPU-domain FINDMEM calls mmu->read(), including I/O side effects. Never
    # sweep $00/$01:C000-CFFF: that touches the speaker, DOC and soft switches.
    # Search ordinary RAM first; low-bank fallback excludes the I/O windows.
    $ranges = @(foreach ($b in 2..15) { ,@(($b * 65536), 65536) })
    foreach ($b in 0..1) {
        $ranges += ,@(($b * 65536), 0xC000)
        $ranges += ,@(($b * 65536 + 0xD000), 0x3000)
    }
    [Gs2Cli]::Pause() | Out-Null
    try {
        foreach ($range in $ranges) {
            $hits = [Gs2Cli]::FindMem(0, [uint32]$range[0], [uint32]$range[1], [uint32]1, $magic)
            if ($hits.Length -gt 0) { break }
        }
        if ($hits.Length -eq 0) { throw 'dbgTab magic not found (banks 0-15, excluding I/O)' }
        $global:FG_TABBASE = [uint32]$hits[0]
        $raw = [Gs2Cli]::ReadMem(0, [uint32]($global:FG_TABBASE + 4), $global:FG_TABN * 4)
    } finally { [Gs2Cli]::Continue() | Out-Null }
    $global:FG_TAB = @()
    for ($i = 0; $i -lt $global:FG_TABN; $i++) {
        $o = $i * 4
        $global:FG_TAB += ([uint32]$raw[$o] -bor ([uint32]$raw[$o + 1] -shl 8) -bor ([uint32]$raw[$o + 2] -shl 16))
    }
    FG-Log ("dbgTab at 0x{0:X6}, {1} entries" -f $global:FG_TABBASE, $global:FG_TAB.Count)
}

function FG-Word([int]$idx) {
    [Gs2Cli]::Pause() | Out-Null
    $r = [Gs2Cli]::ReadMem(0, [uint32]$global:FG_TAB[$idx], 2)
    [Gs2Cli]::Continue() | Out-Null
    return ([int]$r[0] + 256 * [int]$r[1])
}

# Additional 15-entry performance anchor; the stable 52-entry gameplay table stays intact.
function FG-PerfTable {
    [Gs2Cli]::Pause() | Out-Null
    try {
        $hits = @()
        foreach ($bank in 2..15) {
            $hits = [Gs2Cli]::FindMem(0, [uint32]($bank*65536), 65536, 1, [byte[]](70,71,80,50))
            if ($hits.Length) { break }
        }
        if (-not $hits.Length) { throw 'FGP2 performance anchor not found' }
        $raw = [Gs2Cli]::ReadMem(0, [uint32]($hits[0]+4), 60)
        $global:FG_PERF = @(for ($i=0; $i -lt 15; $i++) {
            [BitConverter]::ToUInt32($raw,$i*4) -band 0xFFFFFF
        })
        $ptr = [Gs2Cli]::ReadMem(0, $FG_PERF[0], 4)
        $global:FG_SYS_TICK = [BitConverter]::ToUInt32($ptr,0) -band 0xFFFFFF
    } finally { [Gs2Cli]::Continue() | Out-Null }
}

function FG-PerfWord([int]$idx) {
    [Gs2Cli]::Pause() | Out-Null
    try { $r = [Gs2Cli]::ReadMem(0, $FG_PERF[$idx], 2) }
    finally { [Gs2Cli]::Continue() | Out-Null }
    return [BitConverter]::ToUInt16($r,0)
}

function FG-Burst([string]$name, [int]$frames = 24) {
    $ticks = @()
    [Gs2Cli]::Pause() | Out-Null
    try {
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK "burst_$name.pal"), [Gs2Cli]::ReadMem(0,0x019E00,512))
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK "burst_$name.scb"), [Gs2Cli]::ReadMem(0,0x019D00,200))
    } finally { [Gs2Cli]::Continue() | Out-Null }
    for ($frame=0; $frame -lt $frames; $frame++) {
        [Gs2Cli]::Pause() | Out-Null
        try {
            $tick = [Gs2Cli]::ReadMem(0,$FG_SYS_TICK,2)
            $ticks += [BitConverter]::ToUInt16($tick,0)
            $fb = [Gs2Cli]::ReadMem(0,0x012000,32000)
        } finally { [Gs2Cli]::Continue() | Out-Null }
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK ('burst_{0}_{1:D3}.bin' -f $name,$frame)), $fb)
        Start-Sleep -Milliseconds 25
    }
    $ticks | ConvertTo-Json | Set-Content (Join-Path $FG_WORK "burst_$name.json") -Encoding ASCII
}

function FG-Byte([int]$idx) {
    [Gs2Cli]::Pause() | Out-Null
    $r = [Gs2Cli]::ReadMem(0, [uint32]$global:FG_TAB[$idx], 1)
    [Gs2Cli]::Continue() | Out-Null
    return [int]$r[0]
}

# FG-Write16 <address> <value> : poke a game variable (Pause/Continue paired).
function FG-Write16([uint32]$addr, [int]$value) {
    [Gs2Cli]::Pause() | Out-Null
    [Gs2Cli]::WriteMem(0, $addr, [byte[]]@([byte]($value -band 0xFF), [byte](($value -shr 8) -band 0xFF))) | Out-Null
    [Gs2Cli]::Continue() | Out-Null
}

# FG-Snap : one-line health snapshot (all reads paired with Pause/Continue).
function FG-Snap([string]$tag = 'snap') {
    [Gs2Cli]::Pause() | Out-Null
    $nv = [Gs2Cli]::ReadMem(0, [uint32]0x01C029, 1)
    $ms = [Gs2Cli]::ReadMem(0, [uint32]0x019CFF, 1)
    $ec = [Gs2Cli]::ReadMem(0, [uint32]0x019CFC, 2)
    [Gs2Cli]::Continue() | Out-Null
    $line = "{0}: ms={1} nv={2:X2} err={3} state={4} score={5} mouse=({6},{7}) snd={8}/{9}/{10} mus={11}/{12}/{13}/{14} tot={15} tick={16} read={17}" -f `
        $tag, [int]$ms[0], [int]$nv[0], ([int]$ec[0] + 256 * [int]$ec[1]), `
        (FG-Word $FG_IDX.State), (FG-Word $FG_IDX.Score), (FG-Word $FG_IDX.MouseX), (FG-Word $FG_IDX.MouseY), `
        (FG-Word $FG_IDX.SndTot), (FG-Word $FG_IDX.SndRegOk), (FG-Word $FG_IDX.SndRegBad), `
        (FG-Word $FG_IDX.MusOn), (FG-Word $FG_IDX.MusState), (FG-Word $FG_IDX.MusOk), (FG-Word $FG_IDX.MusBad), `
        (FG-Word $FG_IDX.MusTotal), (FG-Word $FG_IDX.MusTick16), (FG-Word $FG_IDX.MusRead)
    FG-Log $line
    return $line
}

# FG-Key <scancode> : press and release.
function FG-Key([int]$code) {
    [Gs2Cli]::Key($true, $code, 0) | Out-Null
    Start-Sleep -Milliseconds 70
    [Gs2Cli]::Key($false, $code, 0) | Out-Null
    Start-Sleep -Milliseconds 150
}

# FG-Shot <name> : dump SHR frame + palette + SCB and render a PNG into FG_WORK.
function FG-Shot([string]$name) {
    $fb = Join-Path $global:FG_WORK "fb_$name.bin"
    $pal = Join-Path $global:FG_WORK "pal_$name.bin"
    $scb = Join-Path $global:FG_WORK "scb_$name.bin"
    $png = Join-Path $global:FG_WORK "shot_$name.png"
    [Gs2Cli]::Pause() | Out-Null
    [IO.File]::WriteAllBytes($fb, [Gs2Cli]::ReadMem(0, [uint32]0x012000, 32000))
    [IO.File]::WriteAllBytes($pal, [Gs2Cli]::ReadMem(0, [uint32]0x019E00, 512))
    [IO.File]::WriteAllBytes($scb, [Gs2Cli]::ReadMem(0, [uint32]0x019D00, 200))
    [Gs2Cli]::Continue() | Out-Null
    & $global:FG_PY (Join-Path $global:FG_DIR 'render_shot.py') --fb $fb --pal $pal --scb $scb --out $png | Out-Null
    FG-Log "shot -> $png"
    return $png
}

function FG-Quit {
    try { [Gs2Cli]::Quit() | Out-Null } catch { }
    Start-Sleep -Milliseconds 600
    Get-Process GSSquared -ErrorAction SilentlyContinue | Stop-Process -Force
}
