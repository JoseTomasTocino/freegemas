# Real-time countdown and animation/audio exercise, on the shipping image.
param([int]$Seconds = 120, [switch]$Capture, [switch]$Expire)
. (Join-Path $PSScriptRoot 'fgemu.ps1')
$raw = Join-Path $FG_WORK 'fgparitycheck.raw'
function Wait-Play {
    $limit = [DateTime]::UtcNow.AddSeconds(12)
    while ((FG-Word 8) -ne 1 -and [DateTime]::UtcNow -lt $limit) { Start-Sleep -Milliseconds 100 }
    if ((FG-Word 8) -ne 1) { throw 'game did not start' }
}
function Motion-Report($tag) {
    $duration = FG-PerfWord 3; $frames = FG-PerfWord 4
    $elapsed = ((FG-PerfWord 6) - (FG-PerfWord 5)) -band 65535
    Write-Host ("profile erase/draw/music={0}/{1}/{2}" -f (FG-PerfWord 11),(FG-PerfWord 12),(FG-PerfWord 13))
    Write-Host ("motion {0}: target={1} ticks actual={2} frames={3} fps={4:N1}" -f $tag,$duration,$elapsed,$frames,(60.0*$frames/[math]::Max(1,$elapsed)))
}
function Move-Cell([int]$target) {
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    do {
        $cell=FG-Word 7
        if ($cell -eq $target) { return }
        if ([math]::Floor($cell/8) -lt [math]::Floor($target/8)) { FG-Key $FG_KEY.S }
        elseif ([math]::Floor($cell/8) -gt [math]::Floor($target/8)) { FG-Key $FG_KEY.W }
        elseif (($cell%8) -lt ($target%8)) { FG-Key $FG_KEY.D }
        else { FG-Key $FG_KEY.A }
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'cursor did not reach the target cell'
}
function Capture-SettledBoard([string]$name) {
    FG-Shot $name | Out-Null
    [Gs2Cli]::Pause() | Out-Null
    try {
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK 'fb_parity_game.bin'), [Gs2Cli]::ReadMem(0,0x012000,32000))
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK 'parity_board.bin'), [Gs2Cli]::ReadMem(0,$FG_TAB[15],128))
        $pointerState = @{
            x = [BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[11],2),0)
            y = [BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[12],2),0)
            cursor = [BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[7],2),0)
        }
        $pointerState | ConvertTo-Json | Set-Content (Join-Path $FG_WORK 'parity_pointer.json') -Encoding UTF8
    }
    finally { [Gs2Cli]::Continue() | Out-Null }
    & $FG_PY (Join-Path $PSScriptRoot 'check_game_frame.py') $FG_WORK
    if ($LASTEXITCODE -ne 0) { throw 'settled board contains incorrect gem pixels' }
}
FG-Init
try {
    FG-Launch -Audio $raw; FG-WaitUp | Out-Null; FG-Table; FG-PerfTable
    if ((FG-PerfWord 1) -lt 2 -or (FG-PerfWord 2) -ne 0) { throw ('banked graphics did not load: error='+ (FG-PerfWord 2)) }
    [Gs2Cli]::Pause() | Out-Null
    try { $speedByte=[Gs2Cli]::ReadMem(0,0x01C036,1); Write-Host ('CPU speed register: {0:X2}' -f $speedByte[0]) }
    finally { [Gs2Cli]::Continue() | Out-Null }
    FG-Write16 $FG_TAB[10] 0
    FG-Write16 $FG_TAB[11] 160
    FG-Write16 $FG_TAB[12] 92
    FG-Key $FG_KEY.SPACE; Wait-Play
    Motion-Report 'appearance'
    if ((FG-PerfWord 4) -lt 12) { throw 'whole-board appearance rendered too few frames' }
    Capture-SettledBoard parity_game
    [Gs2Cli]::Pause()
    try {
        $left = [BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[1],2),0)
        $base = [BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_PERF[10],2),0)
    } finally { [Gs2Cli]::Continue() }
    $start = ($base - (120-$left)*60) -band 65535
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $iteration=0; $maxError=0
    do {
        Start-Sleep -Seconds 4
        if ((FG-Word 2) -eq 0 -and (FG-Word 1) -gt 4) {
            $selected=FG-Word 6
            if ($selected -lt 64) { Move-Cell $selected; FG-Key $FG_KEY.SPACE }
            FG-Key $FG_KEY.H
            $a=FG-Word 3; $b=FG-Word 4
            if ($a -lt 64 -and $b -lt 64) {
                Move-Cell $a; FG-Key $FG_KEY.SPACE
                Move-Cell $b; FG-Key $FG_KEY.SPACE
                if ($Capture -and $iteration -eq 0) { FG-Burst 'match' 28 }
                $settledDeadline=[DateTime]::UtcNow.AddSeconds(12)
                while ((FG-Word 6) -ne 65535 -and [DateTime]::UtcNow -lt $settledDeadline) { Start-Sleep -Milliseconds 50 }
                if ((FG-Word 6) -ne 65535) { throw 'cascade did not settle' }
                Start-Sleep -Milliseconds 100
                Capture-SettledBoard parity_settled
            }
        }
        [Gs2Cli]::Pause()
        try {
            $tick=[BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_SYS_TICK,2),0)
            $left=[BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[1],2),0)
        } finally { [Gs2Cli]::Continue() }
        $elapsed=(($tick-$start) -band 65535)/60.0
        $expected=[math]::Max(0,120-[math]::Floor($elapsed))
        $countdownError=[math]::Abs($left-$expected); $maxError=[math]::Max($maxError,$countdownError)
        Write-Host ('time system={0:N2}s wall={1:N2}s remaining={2} expected={3} error={4} mus={5}/{6}' -f $elapsed,$watch.Elapsed.TotalSeconds,$left,$expected,$countdownError,(FG-Word 35),(FG-Word 36))
        Motion-Report 'last fall'
        if ($countdownError -gt 1) { throw 'countdown lost elapsed time during rendering/audio' }
        if ((FG-Word 36) -ne 0) { throw 'music streaming error' }
        $iteration++
    } while ($left -gt 0 -and $elapsed -lt $Seconds)
    if ($Expire) {
        Write-Host 'Forcing the remaining-time fixture to one second for game-over rendering.'
        FG-Write16 $FG_TAB[1] 1
        $expiryDeadline = [DateTime]::UtcNow.AddSeconds(10)
        do {
            Start-Sleep -Milliseconds 200
            $left=FG-Word 1
        } while ($left -ne 0 -and [DateTime]::UtcNow -lt $expiryDeadline)
        Write-Host ('expiry remaining={0} over={1} clockActive={2}' -f $left,(FG-Word 2),(FG-PerfWord 9))
        $left = FG-Word 1
    }
    if ($Seconds -ge 120 -or $Expire) {
        if ($left -ne 0) { throw 'two-minute countdown did not expire' }
        Start-Sleep -Seconds 2
        if ((FG-Word 2) -ne 1) { throw 'Game Over did not follow the completed cascade' }
        Motion-Report 'game over drop'
        FG-Shot 'parity_gameover' | Out-Null
        & $FG_PY (Join-Path $PSScriptRoot 'check_game_frame.py') $FG_WORK --gameover
        if ($LASTEXITCODE -ne 0) { throw 'whole-board drop left stray pixels' }
    }
    Write-Host "maximum countdown error=$maxError second(s)"
    if ($Capture) {
        # Game Over accepts replay via Space; R is the live-game reset key.
        if ((FG-Word 2) -ne 0) { FG-Key $FG_KEY.SPACE }
        else { FG-Key $FG_KEY.R }
        FG-Burst 'reset' 60
        $resetDeadline = [DateTime]::UtcNow.AddSeconds(6)
        while ((FG-PerfWord 9) -eq 0 -and [DateTime]::UtcNow -lt $resetDeadline) { Start-Sleep -Milliseconds 100 }
        if ((FG-Word 2) -ne 0 -or (FG-Word 0) -ne 0 -or (FG-Word 1) -lt 118) { throw 'replay/reset did not start a fresh game' }
        Motion-Report 'reset appearance'
    }
} finally { FG-Quit }
& $FG_PY (Join-Path $PSScriptRoot 'audio_report.py') $raw --window 0.02 --quiet 50
