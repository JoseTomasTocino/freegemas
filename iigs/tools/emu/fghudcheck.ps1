param([string]$Image = (Join-Path $PSScriptRoot '../../merlin32/build/hudtest.2mg'))
. (Join-Path $PSScriptRoot 'fgemu.ps1')
$global:FG_IMG=[IO.Path]::GetFullPath($Image)
$global:FG_TABN=55
function Request-Hud($command,$score=0,$time=120) {
    FG-Write16 $FG_TAB[53] $score
    FG-Write16 $FG_TAB[54] $time
    FG-Write16 $FG_TAB[52] $command
    $deadline=[DateTime]::UtcNow.AddSeconds(12)
    while ((FG-Word 52) -ne 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 30 }
    if ((FG-Word 52) -ne 0) { throw 'HUD render mailbox timed out' }
}
function Capture-Hud($name) {
    [Gs2Cli]::Pause() | Out-Null
    try {
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK "fb_$name.bin"),[Gs2Cli]::ReadMem(0,0x012000,32000))
        $state=@{
            score=[BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[0],2),0)
            time=[BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[1],2),0)
        }
        $state | ConvertTo-Json | Set-Content (Join-Path $FG_WORK "hud_$name.json") -Encoding UTF8
    } finally { [Gs2Cli]::Continue() | Out-Null }
    & $FG_PY (Join-Path $PSScriptRoot 'check_hud_frame.py') $FG_WORK $name
    if ($LASTEXITCODE -ne 0) { throw "HUD pixel check failed: $name" }
}
function Capture-Board {
    FG-Shot parity_game | Out-Null
    [Gs2Cli]::Pause() | Out-Null
    try {
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK 'fb_parity_game.bin'),[Gs2Cli]::ReadMem(0,0x012000,32000))
        [IO.File]::WriteAllBytes((Join-Path $FG_WORK 'parity_board.bin'),[Gs2Cli]::ReadMem(0,$FG_TAB[15],128))
        @{x=-100;y=-100;cursor=[BitConverter]::ToUInt16([Gs2Cli]::ReadMem(0,$FG_TAB[7],2),0)} | ConvertTo-Json | Set-Content (Join-Path $FG_WORK 'parity_pointer.json') -Encoding UTF8
    } finally { [Gs2Cli]::Continue() | Out-Null }
    & $FG_PY (Join-Path $PSScriptRoot 'check_game_frame.py') $FG_WORK
    if ($LASTEXITCODE -ne 0) { throw 'settled board differs after local update' }
}
FG-Init
try {
    FG-Launch; FG-WaitUp | Out-Null; FG-Table; FG-PerfTable
    FG-Write16 $FG_TAB[52] 5
    FG-Burst title_intro 48
    Request-Hud 5
    FG-Shot title_small | Out-Null
    & $FG_PY (Join-Path $PSScriptRoot "check_title_frame.py") $FG_WORK
    if ($LASTEXITCODE -ne 0) { throw "Title frame mismatch" }
    Write-Host "Title intro duration=$(FG-PerfWord 3) frames=$(FG-PerfWord 4) elapsed=$(((FG-PerfWord 6)-(FG-PerfWord 5)) -band 65535)"
    Request-Hud 1
    if ((FG-Word 8) -ne 1) { throw 'game did not start' }
    FG-Write16 $FG_PERF[9] 0 # freeze countdown while checking exact text
    foreach ($remaining in @(120,71,7,0,120)) {
        Request-Hud 2 0 $remaining
        Capture-Hud "time_$remaining"
    }
    foreach ($score in @(1,10,111,12345,65535,0)) {
        Request-Hud 2 $score 120
        Capture-Hud "score_$score"
    }
    FG-Shot 'hud_centered' | Out-Null
    Request-Hud 3
    if ((FG-Word 0) -eq 0) { throw 'cascade fixture did not score' }
    Capture-Hud 'after_cascade'
    Capture-Board
    Request-Hud 4
    FG-Shot parity_gameover | Out-Null
    & $FG_PY (Join-Path $PSScriptRoot 'check_game_frame.py') $FG_WORK --gameover
    if ($LASTEXITCODE -ne 0) { throw 'local drop left stray pixels' }
    if ((FG-Word 36) -ne 0) { throw 'music streaming error' }
    Write-Host 'HUD centering and clean redraw checks passed.'
} finally { FG-Quit }
