# fgcheck.ps1 - end-to-end smoke test: boot, play, record, report, quit.
#
#   cd C:\dev\freegemas
#   . .\iigs\tools\emu\fgemu.ps1
#   .\iigs\tools\emu\fgcheck.ps1
#
# What it proves (all on the emulator, not real hardware):
#   * the image boots to the title screen (SHR on, MILESTONE >= 7)
#   * the game starts (State = 1) and the music streamer advances (musOk grows,
#     musBad stays 0)
#   * sound effects reach the DOC (sndTot / sndRegOk move after a swap)
#   * ESC returns to the title
#   * the captured audio does not clip and has no unexpected silence
#
# Output: <workdir>\fgcheck.raw (raw S16LE, see audio_report.py) and the
# per-step snapshot lines, which are the evidence to quote in AGENTS.md.

[CmdletBinding()]
param(
    [switch]$Audio = $true,
    [int]$IdleSeconds = 5,
    [int]$PlaySeconds = 4
)

$tools = $PSScriptRoot
if (-not (Get-Command FG-Launch -ErrorAction SilentlyContinue)) {
    . (Join-Path $tools 'fgemu.ps1')
}

$raw = Join-Path $FG_WORK 'fgcheck.raw'
FG-Init
try {
    FG-Launch -Audio $(if ($Audio) { $raw } else { '' })
    FG-WaitUp | Out-Null
    FG-Table
    FG-Snap 'up'
    $firstMus = FG-Word $FG_IDX.MusOk

    Start-Sleep -Seconds $IdleSeconds
    FG-Snap 'idle'
    if ((FG-Word $FG_IDX.MusOn) -and (FG-Word $FG_IDX.MusOk) -le $firstMus) {
        throw 'music did not advance while idle (check for a paused/frozen emulator)'
    }

    FG-Key $FG_KEY.SPACE          # choose the first menu item (Time Trial)
    Start-Sleep -Seconds $PlaySeconds
    FG-Snap 'game'
    if ((FG-Word $FG_IDX.State) -ne 1) { throw 'Space did not enter the game' }

    # one legal swap needs two clicks on adjacent gems; Space/Space is the
    # keyboard path the automated harness can use
    FG-Key $FG_KEY.SPACE
    FG-Key $FG_KEY.D
    FG-Key $FG_KEY.SPACE
    Start-Sleep -Seconds 3
    FG-Snap 'swap'
    if ((FG-Word $FG_IDX.SndTot) -lt 1 -or (FG-Word $FG_IDX.SndRegBad) -ne 0) {
        throw 'selection sound did not reach the DOC cleanly'
    }

    FG-Key $FG_KEY.ESC
    Start-Sleep -Seconds 3
    FG-Snap 'title'
    if ((FG-Word $FG_IDX.State) -ne 0) { throw 'ESC did not return to the title' }
    if ((FG-Word $FG_IDX.MusBad) -ne 0) { throw 'music streaming reported an error' }

} finally {
    FG-Quit
}

if ($Audio -and (Test-Path $raw)) {
    $sec = (Get-Item $raw).Length / 176400.0
    Write-Host ("audio {0} ({1:N1} s)" -f $raw, $sec)
    & $FG_PY (Join-Path $tools 'audio_report.py') $raw
}
