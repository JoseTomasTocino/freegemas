# Scene-only audio regression. It avoids game-start's intentional track restart
# so a gap here is a loader/streaming problem, not the beginning of the song.
. (Join-Path $PSScriptRoot 'fgemu.ps1')
$raw = Join-Path $FG_WORK 'fgscenecheck.raw'
function Scene-Mark($tag) {
    $sec = (Get-Item $raw).Length / 176400.0
    Write-Host ('audio {0:N3}s {1}' -f $sec, $tag)
}
function Expect-State($value) {
    $actual = FG-Word $FG_IDX.State
    if ($actual -ne $value) { throw "state=$actual expected=$value" }
    if ((FG-Word $FG_IDX.MusBad) -ne 0) { throw 'music read error' }
}
FG-Init
try {
    FG-Launch -Audio $raw; FG-WaitUp | Out-Null; FG-Table
    Scene-Mark 'booted'
    $first = FG-Word $FG_IDX.MusOk
    foreach ($delay in @(170, 310, 90)) {
        FG-Write16 $FG_TAB[$FG_IDX.MenuSel] 2
        Start-Sleep -Milliseconds $delay
        Scene-Mark 'before HowTo'
        FG-Key $FG_KEY.SPACE
        Start-Sleep -Milliseconds 1000
        Expect-State 2
        Scene-Mark 'HowTo'
        FG-Shot 'scenecheck_howto' | Out-Null
        FG-Key $FG_KEY.SPACE
        Start-Sleep -Milliseconds 1000
        Expect-State 0
        Scene-Mark 'Title'
    }
    FG-Write16 $FG_TAB[$FG_IDX.MenuSel] 3
    Scene-Mark 'before Options'
    FG-Key $FG_KEY.SPACE
    Start-Sleep -Milliseconds 500
    Expect-State 3
    FG-Shot 'scenecheck_options' | Out-Null
    FG-Key $FG_KEY.S; FG-Key $FG_KEY.S; FG-Key $FG_KEY.SPACE
    Start-Sleep -Milliseconds 500
    Expect-State 0
    FG-Shot 'scenecheck_title' | Out-Null
    $last = FG-Word $FG_IDX.MusOk
    if ($last -le $first) { throw 'music did not advance' }
    Write-Host "music buffers $first -> $last"
    Scene-Mark 'done'
} finally { FG-Quit }
& $FG_PY (Join-Path $PSScriptRoot 'audio_report.py') $raw --window 0.02 --quiet 50
