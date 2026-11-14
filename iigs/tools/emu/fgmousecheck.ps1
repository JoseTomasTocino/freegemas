# Run against the --ports variant produced by make_mousetest.py. Only hardware
# loads are substituted; the shipping byte polling, decode and UI handlers run.
param([string]$Image = (Join-Path $PSScriptRoot '../../merlin32/build/mtest.2mg'))
. (Join-Path $PSScriptRoot 'fgemu.ps1')
$global:FG_IMG = [IO.Path]::GetFullPath($Image)
$global:FG_TABN = 55
$script:failures = 0
function Check($name, $actual, $expected) {
    if ($actual -ne $expected) {
        Write-Host "FAIL $name : got $actual expected $expected"
        $script:failures++
    } else { Write-Host "PASS $name : $actual" }
}
function Seed($x, $y) {
    FG-Write16 $FG_TAB[11] $x
    FG-Write16 $FG_TAB[12] $y
}
function Wait-State($expected) {
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        $actual = FG-Word 8
        if ($actual -eq $expected) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    Check 'state ready' $actual $expected
}
function Push($xbyte, $ybyte, $axes = 3) {
    [Gs2Cli]::Pause()
    try {
        [Gs2Cli]::WriteMem(0, $FG_TAB[53], [BitConverter]::GetBytes([uint16]$xbyte))
        [Gs2Cli]::WriteMem(0, $FG_TAB[54], [BitConverter]::GetBytes([uint16]$ybyte))
        [Gs2Cli]::WriteMem(0, $FG_TAB[52], [BitConverter]::GetBytes([uint16]$axes))
    } finally { [Gs2Cli]::Continue() }
    Start-Sleep -Milliseconds 150
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    do {
        $pending = FG-Word 52
        if ($pending -eq 0) { break }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $deadline)
    Check 'packet consumed' $pending 0
    # A packet can be consumed before the synchronous swap/drop/reset handler
    # finishes. Wait for another mousePoll rather than assuming a fixed delay.
    $poll = FG-Word 42
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        Start-Sleep -Milliseconds 30
        $nextPoll = FG-Word 42
        if ($nextPoll -ne $poll) { break }
    } while ([DateTime]::UtcNow -lt $deadline)
    Check 'input handler completed' ($nextPoll -ne $poll) $true
}
function Read-Board {
    [Gs2Cli]::Pause()
    try { $board = [Gs2Cli]::ReadMem(0, $FG_TAB[15], 128) }
    finally { [Gs2Cli]::Continue() }
    return ,$board
}
function Drag-Board {
    # No initial runs, and adjacent swaps used below do not make a match.
    $board = [byte[]]::new(128)
    foreach ($row in 0..7) {
        foreach ($col in 0..7) { $board[2 * ($row * 8 + $col)] = (($row * 2 + $col) % 7) + 1 }
    }
    return ,$board
}
function Load-DragBoard([byte[]]$board) {
    Push 0x80 0x80
    FG-Write16 $FG_TAB[6] 65535
    FG-Write16 $FG_TAB[0] 0
    [Gs2Cli]::Pause()
    try { [Gs2Cli]::WriteMem(0, $FG_TAB[15], $board) }
    finally { [Gs2Cli]::Continue() }
}
function Press-Cell($cell) {
    Seed (109 + 26 * ($cell % 8)) (25 + 22 * [math]::Floor($cell / 8))
    Push 0x80 0x00
}
function Hold-Cell($cell) {
    Seed (109 + 26 * ($cell % 8)) (24 + 22 * [math]::Floor($cell / 8))
    Push 0x80 0x01 # one pixel of real motion, left button stays held
}
function Check-Board($name, [byte[]]$expected) {
    Check $name ([Convert]::ToBase64String((Read-Board)) -eq [Convert]::ToBase64String($expected)) $true
}
function Click-At($x, $y) {
    Push 0x80 0x80
    Seed $x $y
    Push 0x80 0x00
}
try {
    FG-Init; FG-Launch; FG-WaitUp | Out-Null; FG-Table
    foreach ($case in @(
        @(3, 0x85, 0x83, 165, 103), # pair: X +5, Y +3
        @(3, 0xFF, 0xFF, 159, 99),  # -1 is 7-bit two's complement
        @(3, 0xC1, 0xC1, 97, 37),   # -63
        @(3, 0xC0, 0xC0, 96, 36),   # -64
        @(1, 0xFF, 0x80, 159, 100), # split packet, X only
        @(2, 0x80, 0xFF, 160, 99)   # split packet, Y only
    )) {
        Seed 160 100
        Push $case[1] $case[2] $case[0]
        Check 'X' (FG-Word 11) $case[3]
        Check 'Y' (FG-Word 12) $case[4]
    }
    Seed 1 1; Push 0xFF 0xFF
    Check 'left clamp' (FG-Word 11) 0
    Check 'top clamp' (FG-Word 12) 0
    Seed 318 198; Push 0xBF 0xBF
    Check 'right clamp' (FG-Word 11) 319
    Check 'bottom clamp' (FG-Word 12) 199
    Seed 160 131; Push 0x80 0x81
    Check 'hover Endless' (FG-Word 10) 1
    Seed 160 117; Push 0x80 0x00 # left button is carried by Y
    Start-Sleep -Seconds 2
    Check 'mouse starts game' (FG-Word 8) 1
    Push 0x80 0x80
    Seed 109 25; Push 0x80 0x00
    Check 'select cell 0' (FG-Word 6) 0
    Push 0x80 0x00
    Check 'held button does not click again' (FG-Word 6) 0
    Push 0x80 0x80
    Seed 135 25; Push 0x80 0x00
    Start-Sleep -Seconds 2
    Check 'second click attempts swap' (FG-Word 6) 65535
    Check 'music errors' (FG-Word 36) 0

    $fixture = Drag-Board
    Load-DragBoard $fixture
    Press-Cell 0
    Hold-Cell 0
    Check 'same-cell hold keeps selection' (FG-Word 6) 0
    Hold-Cell 9
    Check 'diagonal drag does not swap' (FG-Word 6) 0
    Hold-Cell 2
    Check 'distant drag does not swap' (FG-Word 6) 0
    Seed 20 20; Push 0x80 0x01
    Check 'drag outside board does not swap' (FG-Word 6) 0
    Hold-Cell 1
    Check 'drag right attempts swap before release' (FG-Word 6) 65535
    Check-Board 'invalid drag swaps back' $fixture
    Check 'invalid drag scores zero' (FG-Word 0) 0
    Hold-Cell 2
    Check 'held gesture cannot select again' (FG-Word 6) 65535
    Check-Board 'held gesture cannot swap again' $fixture
    foreach ($pair in @(@(2,1), @(0,8), @(8,0))) {
        Load-DragBoard $fixture
        Press-Cell $pair[0]; Hold-Cell $pair[1]
        Check 'drag left/down/up attempts swap' (FG-Word 6) 65535
        Check-Board 'non-winning neighbour reverts' $fixture
    }
    Load-DragBoard $fixture
    Press-Cell 7; Hold-Cell 8
    Check 'row wrap is not a neighbour' (FG-Word 6) 7
    Check-Board 'row wrap leaves board unchanged' $fixture
    Load-DragBoard $fixture
    Press-Cell 0; Push 0x80 0x80
    Seed 135 24; Push 0x80 0x81
    Check 'release cancels dragging, preserves click selection' (FG-Word 6) 0
    # Pressing an already selected gem may clear it as a click, but a drag
    # from that same press must still work.
    Press-Cell 0; Hold-Cell 1
    Check 'drag from an already selected gem' (FG-Word 6) 65535
    Check-Board 'selected-origin invalid swap reverts' $fixture
    Load-DragBoard $fixture
    Press-Cell 0
    FG-Key $FG_KEY.R
    Start-Sleep -Milliseconds 500
    Hold-Cell 1
    Check 'reset cancels a held drag' (FG-Word 6) 65535

    # Upward drag 9 -> 1 puts gem 1 into the middle of row 0's 1,2,1.
    $winning = Drag-Board
    $winning[0] = 1; $winning[2] = 2; $winning[4] = 1
    $winning[18] = 1; $winning[20] = 4
    Load-DragBoard $winning
    Press-Cell 9; Hold-Cell 1
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $selection = FG-Word 6
        if ($selection -eq 65535) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    Check 'winning drag finishes without releasing' $selection 65535
    Check 'winning drag scores' ((FG-Word 0) -gt 0) $true
    Check 'winning drag changes board' ([Convert]::ToBase64String((Read-Board)) -ne [Convert]::ToBase64String($winning)) $true
    $scoreAfterDrag = FG-Word 0
    $boardAfterDrag = Read-Board
    Hold-Cell 2; Hold-Cell 10
    Check 'holding after cascade does not score again' (FG-Word 0) $scoreAfterDrag
    Check-Board 'holding after cascade does not swap again' $boardAfterDrag
    Check 'music errors after dragging/cascade' (FG-Word 36) 0
    Push 0x80 0x80
    FG-Write16 $FG_TAB[0] 1234
    foreach ($point in @(@(6,157), @(85,157), @(40,150), @(40,165), @(40,178))) {
        Click-At $point[0] $point[1]
        Check 'outside sidebar hitboxes does not reset' (FG-Word 0) 1234
        Check 'outside sidebar hitboxes stays in game' (FG-Word 8) 1
    }
    Push 0x80 0x80
    Seed 40 156; Push 0x80 0x81
    Check 'hover Reset does not activate it' (FG-Word 0) 1234
    Click-At 40 142
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        $hintUsed = FG-Word 5
        if ($hintUsed -eq 1) { break }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    Check 'Show hint click activates hint' $hintUsed 1
    Check 'hint identifies a legal first cell' ((FG-Word 3) -lt 64) $true
    Check 'hint identifies a legal second cell' ((FG-Word 4) -lt 64) $true
    FG-Shot 'mousecheck_sidebar_hint' | Out-Null
    Click-At 40 157
    Start-Sleep -Milliseconds 700
    Check 'Reset click clears score' (FG-Word 0) 0
    Check 'Reset click restores timer' ((FG-Word 1) -ge 118) $true
    Check 'Reset click clears hint' (FG-Word 5) 0
    Check 'Reset click clears selection' (FG-Word 6) 65535
    Hold-Cell 0
    Check 'holding Reset then moving to board does not select' (FG-Word 6) 65535
    FG-Shot 'mousecheck_game' | Out-Null
    Click-At 40 185
    Wait-State 0
    Check 'Exit click returns Title' (FG-Word 8) 0
    Push 0x80 0x80
    FG-Write16 $FG_TAB[10] 0
    FG-Key $FG_KEY.SPACE
    Wait-State 1
    FG-Write16 $FG_TAB[2] 1 # exercise the Game Over input dispatch
    FG-Write16 $FG_TAB[0] 4321
    Click-At 40 142
    Check 'Game Over Hint does not restart' (FG-Word 2) 1
    Check 'Game Over Hint leaves score' (FG-Word 0) 4321
    Click-At 40 157
    Start-Sleep -Milliseconds 700
    Check 'Game Over Reset starts a fresh round' (FG-Word 2) 0
    Check 'Game Over Reset clears score' (FG-Word 0) 0
    FG-Write16 $FG_TAB[2] 1
    Click-At 40 185
    Wait-State 0
    Check 'Game Over Exit returns Title' (FG-Word 8) 0
    Push 0x80 0x80
    FG-Shot 'mousecheck_title' | Out-Null
    FG-Write16 $FG_TAB[10] 3
    FG-Key $FG_KEY.SPACE
    Wait-State 3
    $musicBefore = FG-Word 33
    $soundBefore = FG-Word 27
    Seed 160 129; Push 0x80 0x81
    Check 'hover Sound' (FG-Word 28) 1
    Check 'hover does not toggle Sound' (FG-Word 27) $soundBefore
    Seed 160 114; Push 0x80 0x81
    Check 'gap keeps selection' (FG-Word 28) 1
    Seed 20 91; Push 0x80 0x81
    Check 'outside X keeps selection' (FG-Word 28) 1
    Push 0x80 0x00
    Check 'outside click does not toggle Music' (FG-Word 33) $musicBefore
    Push 0x80 0x80
    Seed 160 91; Push 0x80 0x81
    Check 'hover Music' (FG-Word 28) 0
    Check 'hover does not toggle Music' (FG-Word 33) $musicBefore
    FG-Key $FG_KEY.S
    Check 'keyboard moves selection with stationary mouse' (FG-Word 28) 1
    Start-Sleep -Milliseconds 200
    Check 'stationary mouse does not steal selection' (FG-Word 28) 1
    Push 0x80 0x00
    Check 'click uses hovered row' (FG-Word 28) 0
    Check 'click toggles Music' (FG-Word 33) (1 - $musicBefore)
    Push 0x80 0x80; Push 0x80 0x00; Push 0x80 0x80
    Check 'second click restores Music' (FG-Word 33) $musicBefore
    Seed 160 167; Push 0x80 0x81
    Check 'hover Back' (FG-Word 28) 2
    FG-Shot 'mousecheck_options_hover' | Out-Null
    Push 0x80 0x00
    Check 'click Back returns title' (FG-Word 8) 0
    Push 0x80 0x80
    FG-Key $FG_KEY.ESC
    Start-Sleep -Seconds 5
    [Gs2Cli]::Pause()
    try { $nv = [Gs2Cli]::ReadMem(0, 0x01C029, 1) } finally { [Gs2Cli]::Continue() }
    Check 'Quit restores desktop' ([int]$nv[0]) 0xC1
} finally { FG-Quit }
if ($script:failures) { throw "$script:failures mouse regression checks failed" }
Write-Host 'Mouse polling regression passed (emulator, substituted I/O ports).'
