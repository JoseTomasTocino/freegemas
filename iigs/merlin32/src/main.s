* Freegemas Apple IIGS -- M2 scene port.
*
* GS/OS S16, 65816 native mode, SHR 320x200 4bpp. On boot the program streams
* the full 320x200 scene (logo, left panel, score/time panels, buttons, board)
* from SCENE4.RAW straight into screen RAM while the SHR display is off, then
* installs the generated scanline palettes and SCB, draws the gems and HUD
* digits, and finally turns SHR on. The match engine (scan/remove/collapse/
* cascade) is unchanged from the M2 slice.
*
* Layout contract with tools/build_iigs_assets.py (see generated/gs2_offsets.json):
*   board cells 26x22 at (96,14), gems 24x20 blitted at cell origin +161 bytes
*   (one row down for the 1px horizontal grid, one byte right for the 2px
*   vertical grid). Score digits: 6 slots, right edge x=79, y=42, cyan slot 14.
*   Time digits: 5 slots, right edge x=76, y=78. Both sit on flat panel-mid
*   (slot 15) rectangles, so erase is a plain $FF fill.
*
* Build: iigs/merlin32/Makefile.  Run from iigs/merlin32 so generated/gem_data.s
* resolves and Merlin32 writes FREEGEM.S16 next to this source.

         rel
                  dsk    ../build/FREEGEM.S16
         typ S16
         mx %00
         xc
         xc

FREEGEM  START
         phk
         plb
         clc
         xce
         rep #$30
         longa on
         longi on
         jsr clockInit            ; MiscTools GetAddr(5): interrupt-maintained 60Hz clock

* Keep the loader-set D and S untouched. With no direct-page/stack load
* segment in the OMF, GS/OS allocates a 4KB block: D = first byte, S = last
* byte (GS/OS Reference ch.2). The DP page (D..D+$FF) hosts the digit
* blitter's slots $F0-$F3 ; the stack grows down from the top of the same
* block, thousands of bytes away. The old prologue moved S below the block,
* sending the stack through unallocated bank-00 memory in violation of the
* documented contract.

* Display stays in the GS/OS text mode (NEWVIDEO $41) while the scene streams,
* so the old palette never shows new pixels. SHADOWR matches TimePilot-IIgs.
         sep #$20
         longa off
         lda #$00
                  sta    >SHADOWR           ; shadowing ON, as TimePilot-IIgs
         lda #$41
                  sta    >NEWVIDEO           ; SHR display off, bank 01 still writable
         rep #$20
         longa on

* Boot into the title/menu screen: stream TITLE.RAW into screen RAM while the
* SHR display is still off, install its own palettes and SCB, draw the menu and
* only then turn SHR on. The game scene (SCENE4.RAW for Time Trial,
* SCENE4E.RAW for Endless) is streamed when a mode is chosen.
*
* The pathname is relative, so it resolves against the prefix of the directory
* FREEGEM.S16 was launched from.
*
* Breadcrumbs for GSBug forensics (screen bytes, survive any crash):
*   $019CFE = call in flight (1 Open, 2 Read, 3 Close)
*   $019CFC-D = GS/OS error word when a call returns with carry set
*   $019CFF = MILESTONE boot marker (set from sceneOK onward)
         jsr saveScreenSet
         jsr gfxInit
         jsr loadSounds           ; DOC waves ride through SCREEN before the title
         lda #nmTitle
         sta dPathPtr
         jsr loadScene
         jsr loadHiscore
         jsr installTitlePal
         jsr installTitleScb
         jsr saveTitleMenu
         sep #$20
         longa off
         lda #1
                  sta    >MILESTONE
         rep #$20
         longa on
         lda #0
         sta dState
         sta dMode
         sta dMenuSel
         jsr mouseInit
         jsr titleDraw
         jsr shrOn
         jsr musStart             ; background music (M5) rides through every state
         jsr titleIntro
         sep #$20
         longa off
         lda #7
                  sta    >MILESTONE
         rep #$20
         longa on
         brl gameExit

* Main loop: VSYNC edge drives the 1-second timer ; mouse polling runs first so
* every state handler sees this frame's pointer/button ; WASD moves the
* selector, Space selects/swaps, ESC quits to GS/OS.
* Every handler ends its frame here: the pointer is restored, re-snapshotted
* at the new mouse position and painted, so nothing draws over it.
gameExit jsr ptrStep
         brl gameLoop

gameLoop jsr vsyncPoll
         jsr musStep              ; stream the next slice of MUSIC.PCM, if any
         jsr mousePoll
         lda dState
         bne gsNotTitle
         brl stateTitle
gsNotTitle
         cmp #1
         beq gsPlay
         cmp #2
         beq gsHowto
         brl stateOptions
gsHowto  brl stateHowto
gsPlay
         lda dTimedOut
         beq gsCheckOver
         lda dOver
         bne gsCheckOver
         jsr gameOver            ; the previous cascade finished before this dispatch
gsCheckOver
         lda dOver
         bne overKeys
         sep #$20
         longa off
         lda #8
                  sta    >MILESTONE
                  lda    >KBD
         bmi keyDown
         rep #$20
         longa on
         lda dMouseClick        ; left button: click/swap the gem under it
         bne gmClick
         lda dMouseMoved        ; hover: the white frame follows the pointer
         bne gmHover
         brl gameExit
gmClick  brl mouseClick
gmHover  brl mouseHover

* Game over: only Space (play again), ESC (quit) and a mouse click are
* accepted ; the click restarts like Space does.
overKeys sep #$20
         longa off
         lda #8
                  sta    >MILESTONE
                  lda    >KBD
         bmi overKeyDown
         rep #$20
         longa on
         lda dMouseClick
         bne ovClick
         brl gameExit
ovClick  brl mouseClick          ; sidebar buttons keep their meaning at Game Over
overKeyDown
         sep #$20               ; assembler must know A is 8-bit here too,
         longa off              ; otherwise cmp #$20 becomes a 3-byte BRK
                  sta    >KBDSTRB
         and #$7F
         cmp #$1B                ; ESC returns to the title menu
         bne overNotEsc
         brl toTitle
overNotEsc
         cmp #$20                ; Space restarts a fresh Time Trial game
         bne overOther
         rep #$20
         longa on
         jsr resetGame
         brl gameExit
overOther
         rep #$20
         longa on
         brl gameExit

* Clear the keyboard strobe with a one-byte store: in 16-bit mode STA.L
* would also write A's high byte to $01C011, which is a RAMWRT switch.
keyDown
         sep #$20
         longa off
                  sta    >KBDSTRB
         and #$7F
         cmp #$1B                ; ESC returns to the title menu
         bne notEsc
         brl toTitle
notEsc   cmp #$20                ; Space selects a gem / swaps an adjacent pair
         beq isSpace
         cmp #$0B
         beq kdArrowUp
         cmp #$08
         beq kdArrowLeft
         cmp #$0A
         beq kdArrowDown
         cmp #$15
         beq kdArrowRight
         and #$DF                ; fold letters so both W and w work
         cmp #'W'
         bne kdA
         brl moveUp
kdA      cmp #'A'
         bne kdS
         brl moveLeft
kdS      cmp #'S'
         bne kdD
         brl moveDown
kdD      cmp #'D'
         bne kdH
         brl moveRight
kdH      cmp #'H'                ; H shows the first legal swap (green frames)
         bne kdR
         brl keyHint
kdR      cmp #'R'                ; R restarts a fresh board, score and timer
         bne kdNone
         brl keyReset
kdNone   rep #$20
         longa on
         brl gameExit
kdArrowUp rep #$20
         longa on
         brl moveUp
kdArrowLeft rep #$20
         longa on
         brl moveLeft
kdArrowDown rep #$20
         longa on
         brl moveDown
kdArrowRight rep #$20
         longa on
         brl moveRight

keyHint  rep #$20
         longa on
         jsr showHint
         brl gameExit
keyReset rep #$20
         longa on
         jsr resetGame
         brl gameExit

isSpace  rep #$20
         longa on
         brl spaceKey

moveUp   rep #$20
         longa on
         lda dCursor
         cmp #8
         bcs upGo
         clc
         adc #56                 ; row 0 -> row 7 (wrap like the original)
         sta dNewCursor
         brl moveCursor
upGo     sec
         sbc #8
         sta dNewCursor
         brl moveCursor

moveLeft rep #$20
         longa on
         lda dCursor
         and #$0007
         bne leftGo
         lda dCursor
         clc
         adc #7                  ; column 0 -> column 7
         sta dNewCursor
         brl moveCursor
leftGo   lda dCursor
         dec a
         sta dNewCursor
         brl moveCursor

moveRight rep #$20
         longa on
         lda dCursor
         and #$0007
         cmp #7
         bne rightGo
         lda dCursor
         sec
         sbc #7                  ; column 7 -> column 0
         sta dNewCursor
         brl moveCursor
rightGo  lda dCursor
         inc a
         sta dNewCursor
         brl moveCursor

moveDown rep #$20
         longa on
         lda dCursor
         cmp #56
         bcc downGo
         sec
         sbc #56                 ; row 7 -> row 0
         sta dNewCursor
         brl moveCursor
downGo   clc
         adc #8
         sta dNewCursor

moveCursor anop
         jsr cursorMove
         brl gameExit

* Repaint the old cursor cell, draw the white frame at dNewCursor and put the
* blue mark back when a gem is selected.  The mouse click path calls this
* directly so the old frame is erased before spaceKey runs.
cursorMove anop
         jsr clearHint
         lda dCursor
         sta dOldCursor
         lda dOldCursor
         jsr drawCellIndex
         lda dNewCursor
         sta dCursor
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
         lda dSelCell             ; keep the marked gem framed in blue
         cmp #$FFFF
         beq moveCursorDone
         jsr setFrameCell
         jsr frameMark
         jsr drawFrame
moveCursorDone
         rts

quitGame anop
         jsr mouseRestore        ; GS/OS needs the mouse interrupt back
         jsr restoreScreenSet    ; and its desktop palette / scanline table
         jsr musStop             ; stop the music stream and close MUSIC.PCM
         jsr audioStop           ; no oscillator may be left running on exit
         jsr musDisposeCache     ; unlock/free the large cross-bank PCM handle first
         jsr gfxDispose
         sep #$20
         longa off
         lda #$41                ; display off / linear map, as GS/OS expects
                  sta    >NEWVIDEO
         rep #$20
         longa on
         jsl $E100A8             ; GS/OS _Quit (does not return)
         dw  $2029
         adrl quitpb

*-----------------------------------------------------------------------------
* Missing scene file: paint the whole screen with the wood slot so the HUD,
* board and frames still render something sane.
*-----------------------------------------------------------------------------
fallbackFill anop
         lda #$BBBB
         ldx #0
ffLoop            sta    >SCREEN,x
         inx
         inx
         cpx #32000
         bne ffLoop
         rts

*-----------------------------------------------------------------------------
* VSYNC: poll $C019 bit 7 for a 0->1 edge (60 per second). Every 60 edges the
* Time Trial timer drops by one second and the time digits are redrawn. At
* zero the timer holds (game-over handling arrives with M3).
*-----------------------------------------------------------------------------
* Banked masked rasters: 16 palettes x 7 gems x 20 rows x 24 bytes.
gemtiles equ $0000
gfxInit anop
         pea $0000
         ldx #$0202             ; MMStartUp -> an application memory ID
         jsl $E10000
         pla
         sta dGfxUserID
         pea $0000
         pea $0000              ; returned handle
         pea $0001
         pea $0000              ; 65536 bytes
         lda dGfxUserID
         pha
         pea $C010              ; locked, fixed, cannot cross a bank
         pea $0000
         pea $0000              ; no preferred location
         ldx #$0902             ; NewHandle
         jsl $E10000
         sta dGfxError
         pla
         sta dGfxHandle
         sta $E0
         pla
         sta dGfxHandle+2
         sta $E2
         bcc gfAllocated
         rts
gfAllocated
         lda [$E0]
         sta pbGfxRead+4
         ldy #2
         lda [$E0],y
         sta pbGfxRead+6
         and #$00FF
         sta dGfxBank
         sep #$20
         longa off
         sta dgCall+3
         sta titleGemCall+3
         rep #$20
         longa on
         jsl $E100A8
         dw $2010
         adrl pbGfxOpen
         bcc gfOpenReady
         brl gfFailed
gfOpenReady anop
         lda pbGfxOpen+2
         sta pbGfxRead+2
         sta pbGfxClose+2
         jsl $E100A8
         dw $2012
         adrl pbGfxRead
         sta dGfxError
         php
         jsl $E100A8
         dw $2014
         adrl pbGfxClose
         plp
         bcc gfReady
         stz dGfxBank
gfReady  lda dGfxBank
         beq gfInitDone
         lda #nmGfxFast0
         jsr gfxLoadFast
         sta dGfxFastBanks
         lda #nmGfxFast1
         jsr gfxLoadFast
         sta dGfxFastBanks+2
         lda #nmGfxFast2
         jsr gfxLoadFast
         sta dGfxFastBanks+4
gfInitDone rts

* Load a full compiled-blitter bank. All handles share dGfxUserID and are
* disposed together on Quit. A=GS/OS pathname; returns allocated bank or zero.
gfxLoadFast sta pbGfxFastOpen+4
         sep #$20
         longa off
         phk
         pla
         sta pbGfxFastOpen+6
         rep #$20
         longa on
         pea $0000
         pea $0000
         pea $0001
         pea $0000
         lda dGfxUserID
         pha
         pea $C010
         pea $0000
         pea $0000
         ldx #$0902
         jsl $E10000
         sta dGfxError
         pla
         sta $E0
         pla
         sta $E2
         bcs gfFastFail
         lda [$E0]
         sta pbGfxFastRead+4
         ldy #2
         lda [$E0],y
         sta pbGfxFastRead+6
         and #$00FF
         sta dGfxFastLoaded
         jsl $E100A8
         dw $2010
         adrl pbGfxFastOpen
         bcs gfFastFail
         lda pbGfxFastOpen+2
         sta pbGfxFastRead+2
         sta pbGfxClose+2
         jsl $E100A8
         dw $2012
         adrl pbGfxFastRead
         sta dGfxError
         php
         jsl $E100A8
         dw $2014
         adrl pbGfxClose
         plp
         bcs gfFastFail
         lda dGfxFastLoaded
         rts
gfFastFail sta dGfxError
         lda #0
         rts

gfFailed sta dGfxError
         stz dGfxBank
         rts

gfxDispose anop
         lda dGfxUserID
         beq gdOut
         pha
         ldx #$0302             ; MMShutDown releases the ID's locked block
         jsl $E10000
         stz dGfxUserID
gdOut    rts

clockInit anop
         pea $0000
         pea $0000              ; space for returned pointer
         pea $0005              ; documented tick counter address
         ldx #$1603             ; Miscellaneous Tools GetAddr
         jsl $E10000
         pla
         sta ckLoad+1
         sta dClockPtr
         pla
         sta dClockPtr+2
         sep #$20
         longa off
         sta ckLoad+3
         rep #$20
         longa on
         rts

clockRead anop
         php
         sei                    ; the ROM heartbeat must not split the word read
ckLoad   lda >$000000
         plp
         rts

* Service elapsed ticks, not observed VBL edges. Safe inside the renderer:
* only clock variables change here; redraw and Game Over wait for gameLoop.
clockAdvance anop
         jsr clockRead
         sta dClockNow
         asl a
         asl a
         asl a
         asl a
         sta dMusTick16
         lda dClockActive
         beq caOut
         lda dMode
         bne caOut
         lda dOver
         bne caOut
         lda dClockNow
         sec
         sbc dGameTickBase
caSeconds cmp #98
         bcc caOut
         sec
         sbc #60
         sta dClockDelta
         lda dGameTickBase
         clc
         adc #60
         sta dGameTickBase
         lda dTimeLeft
         beq caExpired
         dec dTimeLeft
         lda #1
         sta dTimeDirty
         lda dTimeLeft
         beq caExpired
         lda dClockDelta
         bra caSeconds
caExpired lda #1
         sta dTimedOut
         stz dClockActive
caOut    rts

vsyncPoll anop
         jsr clockAdvance
         lda dTimeDirty
         beq vsOut
         stz dTimeDirty
         jsr drawTime
vsOut    rts

*-----------------------------------------------------------------------------
* Space: first press marks a gem, second press on an adjacent gem swaps them.
* The mark frame uses the blue panel slot ; the white frame follows the cursor.
*-----------------------------------------------------------------------------
spaceKey anop
         jsr clearHint
         lda dSelCell
         cmp #$FFFF
         beq selectGem
         cmp dCursor             ; Space on the marked gem clears the mark
         beq clearSel
         lda dCursor
         sec
         sbc dSelCell
         sta dDiff
         cmp #$0008
         beq swapAdj
         cmp #$FFF8
         beq swapAdj
         cmp #$0001
         beq stepRight
         cmp #$FFFF
         beq stepLeft
         brl clearSel            ; not a neighbour: drop the mark

stepRight
         lda dSelCell
         and #7
         cmp #7                  ; row wrap 7 -> 0 is not adjacency
         beq clearSel
         brl swapAdj
stepLeft
         lda dCursor
         and #7
         cmp #7
         beq clearSel
         brl swapAdj

selectGem
         lda dCursor
         sta dSelCell
         jsr setFrameCell
         jsr frameMark
         jsr drawFrame
         lda #0                   ; select.wav
         jsr playSound
         brl gameExit

clearSel
         lda dSelCell
         jsr drawCellIndex       ; repaint the marked cell, erasing its frame
         lda #$FFFF
         sta dSelCell
         lda dCursor
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
         brl gameExit

swapAdj anop
         lda dSelCell
         cmp dCursor
         bcc aLower
         sta dSwapB
         lda dCursor
         sta dSwapA
         brl swapStore
aLower
         sta dSwapA
         lda dCursor
         sta dSwapB
swapStore
         jsr animSwap
         jsr swapCells            ; tentative swap
         jsr scanBoard
         lda dMatchCnt
         bne swapResolve
* No match anywhere: animate back, then restore the logical board.
         jsr animSwap
         jsr swapCells
         lda #$FFFF
         sta dSelCell
         lda dCursor
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
         brl gameExit
swapResolve
         jsr resolveBoard         ; remove, score, drop, refill, cascade
         lda #$FFFF
         sta dSelCell
         lda dOver               ; no-moves in Endless may have drawn Game Over
         bne swrDone             ; do not restore the active selector over its panel
         lda dCursor              ; the frame follows the cursor again
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
swrDone
         brl gameExit

*-----------------------------------------------------------------------------
* Swap the two gems named by dSwapA/dSwapB and repaint both cells.
*-----------------------------------------------------------------------------
swapCells
         lda dSwapA
         asl a
         tax
         lda cellgem,x
         sta dTempGem
         lda dSwapB
         asl a
         tay
         lda cellgem,y
         sta cellgem,x
         lda dTempGem
         sta cellgem,y
         lda dSwapA
         jsr drawCellIndex
         lda dSwapB
         jsr drawCellIndex
         rts

*-----------------------------------------------------------------------------
* Frame colours. The full byte paints the top/bottom rows, the hi/lo nibbles
* touch the left/right edge pixels without disturbing the other pixel.
* White follows the cursor ; blue marks the gem selected for a swap.
*-----------------------------------------------------------------------------
frameWhite
         lda #$0011
         sta dFrameByte
         lda #$0010
         sta dFrameHi
         lda #$0001
         sta dFrameLo
         rts

frameMark
         lda #$00BB
         sta dFrameByte
         lda #$00B0
         sta dFrameHi
         lda #$000B
         sta dFrameLo
         rts

frameHint
         lda #$00DD
         sta dFrameByte
         lda #$00D0
         sta dFrameHi
         lda #$000D
         sta dFrameLo
         rts

*-----------------------------------------------------------------------------
* ADB mouse (M3).  $C024 returns one movement byte per read ; $C027 bit 1 says
* whether the next read is X (0) or Y (1) and bit 7 says the register holds a
* fresh pair.  Byte layout (Cortland ADB ERS, see a2gsemu-ia Docs/ADB.md):
*   bit 7    button, 1 = up / 0 = pressed (X byte carries button 1, the Y byte
*            carries button 0 = left, which is the only button on an Apple
*            Desktop Mouse)
*   bit 6    delta sign, 1 = negative
*   bits 6-0 signed two's-complement delta, -64..63
* GS/OS enables the mouse interrupt and its own handler eats the pair, so the
* game clears bit 6 of $C027 while it owns the pointer and restores the saved
* status before quitting.  Polling (not the interrupt) drives the whole game.
* mouseEmInit (below) is what makes GSSquared feed motion without F1 capture.
mouseInit anop
         sep #$20
         longa off
         lda >ADBSTAT
         sta dMouseStat
         and #$BF                ; mouse interrupt off: GS/OS stops reading $C024
         sta >ADBSTAT
         rep #$20
         longa on
         stz dMouseBtn
         stz dMousePrev
         stz dMouseClick
         stz dMouseMoved
         lda #$FFFF
         sta dDragCell
                   jsr    mouseEmInit
         jsr mouseEmFeed         ; seed closed-loop feedback before the first packet
         rts

mouseRestore anop
         rep #$20
         longa on
         lda dMouseStat
         and #$00FF
         sep #$20
         longa off
         sta >ADBSTAT              ; hand the mouse interrupt back to the Finder
         lda dEmTlSave             ; and put the Tool Locator / EM cursor back
         sta >$E103C8
         lda dEmTlSave+1
         sta >$E103C9
         lda dEmTlSave+2
         sta >$E103CA
         lda dEmPosSave
         sta >$E10190
         lda dEmPosSave+1
         sta >$E10191
         lda dEmPosSave+2
         sta >$E10192
         lda dEmPosSave+3
         sta >$E10193
         rep #$20
         longa on
         rts

*-----------------------------------------------------------------------------
* Host-cursor mode: convince GSSquared that the Event Manager is running.
*
* GSSquared (src/devices/adb/keygloo_mouse_sync.hpp, compute_em_active) only
* feeds ADB mouse motion while it believes the GS/OS Event Manager is up: it
* reads the Tool Locator global pointer at $E1/03C8 and then requires a non-zero
* word at pointer+24.  A SetStart boot never runs Event Manager, so that word is
* $0000 and the emulator generates no packet at all -- the pointer stays frozen
* until F1 capture, which is the "mouse is dead in GSSquared" report.
*
* Pointing the global at a scratch word of our own (dEmTools+24 = $1B00, the
* same value GS/OS leaves there) makes the host cursor drive the emulated ADB
* mouse, so the packet stream mousePoll already decodes starts flowing.  The
* emulator's closed loop reads the Event Manager cursor at $E1/0190-0193 for
* feedback, so mouseEmFeed publishes our pointer there every frame; without it
* the stepper would keep injecting the whole delta measured from (0,0).
*
* The pointer is only ours while this app runs: mouseRestore writes every saved
* byte back before Quit.  GSSquared prints "KeyGloo: Event Manager active" when
* the trick is live (gs2.log).
*-----------------------------------------------------------------------------
mouseEmInit        anop
                   sep    #$20
                   longa  off
                   lda    >$E103C8           ; Tool Locator pointer low word
                   sta    dEmTlSave
                   lda    >$E103C9
                   sta    dEmTlSave+1
                   lda    >$E103CA           ; ... and its bank byte
                   sta    dEmTlSave+2
                   lda    >$E10190           ; Event Manager cursor feed-back
                   sta    dEmPosSave
                   lda    >$E10191
                   sta    dEmPosSave+1
                   lda    >$E10192
                   sta    dEmPosSave+2
                   lda    >$E10193
                   sta    dEmPosSave+3
                   stz    dEmOn
                   phk
                   pla
                   sta    dEmBank             ; low byte = program bank
                   cmp    #2
                   bcc    meiOut              ; loaded in bank 0/1: cannot fake
                   rep    #$20
                   longa  on
                   lda    #dEmTools
                   sta    >$E103C8            ; Tool Locator -> our scratch block
                   sep    #$20
                   longa  off
                   lda    dEmBank
                   sta    >$E103CA
                   rep    #$20
                   longa  on
                   lda    #$1B00
                   sta    dEmTools+24         ; non-zero = Event Manager active
                   lda    #1
                   sta    dEmOn
meiOut             rep    #$20
                   longa  on
                   rts

* Publish the game pointer as the Event Manager cursor so the emulator's
* closed-loop stepper measures its next delta from where we really are.
mouseEmFeed        anop
                   lda    dEmOn
                   beq    mefOut
                   sep    #$20
                   longa  off
                   lda    dMouseX
                   sta    >$E10190
                   lda    dMouseX+1
                   sta    >$E10192
                   lda    dMouseY
                   sta    >$E10191
                   lda    dMouseY+1
                   sta    >$E10193
mefOut             rep    #$20
                   longa  on
                   rts

* Take at most two bytes per poll and fold each one into the pointer.
* $C027 bit 7 says a byte is waiting ; bit 1 says which axis it belongs to.
* The Cortland mouse doc is BACKWARDS here (Docs/AppleIIgsDiagnostics.md):
* bit1=0 -> X is the next byte, bit1=1 -> Y.  The earlier code had this
* inverted, so a horizontal move was applied to Y and vice versa - the
* "pointer runs the wrong way / jumps" bug.  Do NOT read two bytes blindly:
* right after a packet starts arriving only one byte is present, so the second
* read returns a stale value, which used to overwrite the *other* axis.  Two
* bytes per poll bounds the burst, so a stuck bit 7 can never lock the loop.
mousePoll anop
         stz dMouseClick
         stz dMouseMoved
         stz dMNewX
         stz dMNewY
         lda dMLogIdx             ; DEBUG: advance the status ring
         inc a
         and #$001F
         sta dMLogIdx
                  sep    #$20
                  longa  off
                  lda    >ADBSTAT
                  ldx    dMLogIdx
                  sta    dMLogS,x             ; DEBUG: exactly what bit7/bit1 looked like
                  lda    #0
                  sta    dMLogB,x             ; DEBUG: slot starts empty
                  sta    dMLogC,x
                  lda    >ADBSTAT
                  and    #$80                 ; mouse data register full?
                  beq    mpNone
                  lda    >ADBSTAT
                  and    #$02
                  bne    mp1Y                 ; bit1=1 -> Y is waiting, 0 -> X
                  lda    >MOUSEDAT           ; X
                  ldx    dMLogIdx
                  sta    dMLogB,x             ; DEBUG
         sta dMByteX
         lda #1
         sta dMNewX
                  bra    mpByte2
mp1Y              lda    >MOUSEDAT           ; Y
                  ldx    dMLogIdx
                  sta    dMLogB,x             ; DEBUG
         sta dMByteY
         lda #1
         sta dMNewY
mpByte2           lda    >ADBSTAT
                  and    #$80
                  beq    mpHave
                  lda    >ADBSTAT
                  and    #$02
                  bne    mp2Y                 ; bit1=1 -> Y is waiting, 0 -> X
                  lda    >MOUSEDAT           ; X
                  ldx    dMLogIdx
                  sta    dMLogC,x             ; DEBUG
                  sta    dMByteX
                  lda    #1
                  sta    dMNewX
         bra mpHave
mp2Y              lda    >MOUSEDAT           ; Y
                  ldx    dMLogIdx
                  sta    dMLogC,x             ; DEBUG
                  sta    dMByteY
                  lda    #1
                  sta    dMNewY
         bra mpHave             ; a complete X/Y packet must reach the decoder
mpNone            rep    #$20
         longa on
                  rts                         ; nothing new: leave $C024 alone
mpHave   rep #$20
         longa on
         stz dMDx                ; only a fresh byte contributes a delta
         stz dMDy
         lda dMNewX
         beq mpXDone
         lda dMByteX
         and #$00FF
         sta dMTmp
         and #$0040
         beq mpXPos
         lda dMTmp
         ora #$FF80             ; sign-extend the seven-bit delta (-1 = $7F)
         sta dMDx
         bra mpXDone
mpXPos   lda dMTmp
         and #$003F
         sta dMDx
mpXDone  lda dMNewY
         beq mpYDone
         lda dMByteY
         and #$00FF
         sta dMTmp
         and #$0040
         beq mpYPos
         lda dMTmp
         ora #$FF80
         sta dMDy
         bra mpYDone
mpYPos   lda dMTmp
         and #$003F
         sta dMDy
* The two button bits ride in different data bytes (button 1 in the X byte,
* button 0 in the Y byte).  Latch each one only when its own byte is fresh:
* testing a stale byte made a button look held and then produced a phantom
* press -> missed/duplicate clicks.  Keeping the latches per axis means a
* one-byte poll can never invent a click, and a real press edge is still
* reported exactly once.
mpYDone  lda dMNewX
         beq mpNoBtnX
         lda dMByteX
         and #$0080
         bne mpBtn1Up
         lda #1
         bra mpBtn1Done
mpBtn1Up lda #0
mpBtn1Done sta dMBtn1
mpNoBtnX lda dMNewY
         beq mpNoBtnY
         lda dMByteY
         and #$0080
         bne mpBtn0Up
         lda #1
         bra mpBtn0Done
mpBtn0Up lda #0
mpBtn0Done sta dMBtn0
mpNoBtnY lda dMBtn0
         bne mpKeepDrag
         lda #$FFFF
         sta dDragCell           ; releasing the left button ends this gesture
mpKeepDrag lda dMDx
         bne mpMoved
         lda dMDy
         beq mpNoMove
mpMoved  lda #1
         sta dMouseMoved
mpNoMove lda dMouseX
         clc
         adc dMDx
         bpl mpXNotNeg
         lda #0
         bra mpXStored
mpXNotNeg cmp #320
         bcc mpXStored
         lda #319
mpXStored sta dMouseX
         lda dMouseY
         clc
         adc dMDy
         bpl mpYNotNeg
         lda #0
         bra mpYStored
mpYNotNeg cmp #200
         bcc mpYStored
         lda #199
mpYStored sta dMouseY
         lda dMBtn0
         ora dMBtn1
         bne mpBtnDown
         stz dMouseBtn
         stz dMousePrev
         bra mpOut
mpBtnDown lda #1
         sta dMouseBtn
         lda dMousePrev
         bne mpOut             ; already down: no new click
         lda #1
         sta dMousePrev
         sta dMouseClick
mpOut    jsr mouseEmFeed         ; publish the pointer as the EM cursor
         longa on
         rts

* Map dMouseX/dMouseY to a board cell.  Carry set = on the board, dMCell holds
* row*8+col.  The board is 8 cells of 26x22 at (96,14).
mouseHit anop
         lda dMouseX
         sec
                  sbc    #{96}
         bcc mhMiss
                  cmp    #{208}
         bcs mhMiss
         sta dMTmp
         stz dMCol
mhColLp  lda dMTmp
                  cmp    #{26}
         bcc mhColOk
         sec
                  sbc    #{26}
         sta dMTmp
         inc dMCol
         bra mhColLp
mhColOk  lda dMouseY
         sec
                  sbc    #{14}
         bcc mhMiss
                  cmp    #{176}
         bcs mhMiss
         sta dMTmp
         stz dMRow
mhRowLp  lda dMTmp
                  cmp    #{22}
         bcc mhRowOk
         sec
                  sbc    #{22}
         sta dMTmp
         inc dMRow
         bra mhRowLp
mhRowOk  lda dMRow
         asl a
         asl a
         asl a
         clc
         adc dMCol
         sta dMCell
         sec
         rts
mhMiss   clc
         rts

* Pointer hover: the white frame follows the mouse, like the original.
mouseHover anop
         lda dMBtn0
         beq mhPointer
         lda dDragCell
         cmp #$FFFF
         beq mhPointer
         brl mouseDrag
mhPointer
         jsr mouseHit
         bcc mhOut
         lda dSelCell
         cmp #$FFFF
         bne mhOut             ; a marked gem keeps the frame where it is
         lda dMCell
         cmp dCursor
         beq mhOut
         sta dNewCursor
         jsr cursorMove
mhOut    brl gameExit

* Left click: move the frame there and run the Space handler, so click-click is
* exactly the keyboard swap path (first click marks, second click on a
* neighbour swaps, click on the marked gem clears it).
mouseClick anop
         stz dMouseClick
         lda #$FFFF
         sta dDragCell
* Sidebar plaques share the generator's layout: x=7..84, height 14.
* Check these before the board; they use the same handlers as H/R/ESC.
         lda dMouseX
         cmp #7
         bcc mcBoard
         cmp #85
         bcs mcBoard
         ldx #0
mcButtonRow lda dMouseY
         sec
         sbc gameBtnY,x
         cmp #14
         bcc mcButtonHit
         inx
         inx
         cpx #8
         bcc mcButtonRow
         bra mcBoard
mcButtonHit
         cpx #0
         bne mcNotHint
         brl keyHint
mcNotHint cpx #2
         bne mcExitButton
         brl keyReset
mcExitButton
         brl toTitle
mcBoard  lda dOver
         beq mcGem
         jsr resetGame           ; preserve the existing Game Over click-to-restart
         brl gameExit
mcGem
         jsr mouseHit
         bcc mcOut
* Arm only a press that selects a new origin (or presses the selected gem).
* A second click on another gem already attempts the click-click swap, so it
* must not also start a second exchange while the same button remains down.
         lda dMBtn0
         beq mcMove
         lda dSelCell
         cmp #$FFFF
         beq mcArm
         cmp dMCell
         bne mcMove
mcArm    lda dMCell
         sta dDragCell
mcMove
         lda dMCell
         cmp dCursor
         beq mcAct
         sta dNewCursor
         jsr cursorMove
mcAct    brl spaceKey
mcOut    brl gameExit

* Drag from the press origin to one orthogonal neighbour. Diagonal/distant
* cells and the 7->8 row wrap do not exchange. Consume the gesture before
* entering the normal Space path, including when an illegal swap is undone.
mouseDrag anop
         jsr mouseHit
         bcc mdOut
         lda dMCell
         sec
         sbc dDragCell
         cmp #8
         beq mdSwap
         cmp #$FFF8
         beq mdSwap
         cmp #1
         beq mdRight
         cmp #$FFFF
         beq mdLeft
         bra mdOut
mdRight  lda dDragCell
         and #7
         cmp #7
         beq mdOut
         bra mdSwap
mdLeft   lda dDragCell
         and #7
         beq mdOut
mdSwap   lda dDragCell
         sta dSelCell
         lda #$FFFF
         sta dDragCell
         lda dMCell
         cmp dCursor
         beq mdAct
         sta dNewCursor
         jsr cursorMove
mdAct    brl spaceKey
mdOut    brl gameExit

*-----------------------------------------------------------------------------
* Visible mouse pointer: the VERA-style 16x16 masked glove, painted into SHR.
*
* No hardware sprite exists, so ptrStep keeps three 128-byte row blocks per
* frame:  dPtrSave  = the bytes that were under the glove
*         dPtrPaint = the bytes the glove wrote
*         dPtrKeep/dPtrVal = generated 4bpp glove mask and ink
*
* The restore is compare-guarded: a byte is only written back when it still
* holds the exact value the arrow painted. Anything the game repainted on top
* of the arrow (cell redraw, HUD, full-screen scene) is therefore left alone.
*-----------------------------------------------------------------------------
PTR_BYTES equ 128
PTR_ROWS  equ 16

ptrStep anop
         lda dPtrOn
         bne psOn
         brl psSnap
psOn
* A software cursor must not be erased and redrawn on every busy-loop pass:
* that exposes the background for a few instructions and looks like blinking.
* Keep it untouched while its snapped position and the pixels underneath it
* are unchanged. The pixel check still catches game redraws under a stationary
* pointer, so the overlay can be rebuilt without flashing during idle.
         lda dMouseX
         cmp #305
         bcc psCheckX
         lda #304
psCheckX and #$FFFE
         sta dPrtNewX
         lda dMouseY
         cmp #185
         bcc psCheckY
         lda #184
psCheckY sta dPrtNewY
         cmp dPtrY
         bne psErase
         lda dPrtNewX
         cmp dPtrX
         bne psErase
         lda dPtrOff
         sta dDst
         ldy #0
psCheckR ldx dDst
         lda #8
         sta dPrtCnt
psCheckB sep #$20
         longa off
         lda >SCREEN,x
         cmp dPtrPaint,y
         rep #$20
         longa on
         bne psErase
         inx
         iny
         dec dPrtCnt
         bne psCheckB
         lda dDst
         clc
         adc #160
         sta dDst
         cpy #PTR_BYTES
         bcc psCheckR
         rts
psErase  lda dPtrOff
         sta dDst
         ldy #0
psEraseR ldx dDst
         lda #8
         sta dPrtCnt
psEraseB jsr ptrRestoreByte
         inx
         iny
         dec dPrtCnt
         bne psEraseB
         lda dDst
         clc
         adc #160
         sta dDst
                  cpy    #{PTR_BYTES}
         bne psEraseR

* Clamp to the screen and align the glove's left edge to a byte boundary.
psSnap   lda dMouseX
         cmp #305
         bcc psXOk
         lda #304
psXOk    and #$FFFE
         sta dPtrX
         lda dMouseY
         cmp #185
         bcc psYOk
         lda #184
psYOk    sta dPtrY

* dPtrOff = y*160 + x/2  (160 = 128+32, built with shifts so no multiply table)
         asl a
         asl a
         asl a
         asl a
         asl a                  ; y*32
         sta dPrtT
         lda dPtrY
         asl a
         asl a
         asl a
         asl a
         asl a
         asl a
         asl a                  ; y*128
         clc
         adc dPrtT              ; y*160
         sta dPrtT
         lda dPtrX
         lsr a
         clc
         adc dPrtT
         sta dPtrOff
         sta dDst

         ldy #0
psPaintR ldx dDst
         lda #8
         sta dPrtCnt
psPaintB sep #$20
         longa off
                  lda    >SCREEN,x
         sta dPtrSave,y
         and dPtrKeep,y
         ora dPtrVal,y
                  sta    >SCREEN,x
         sta dPtrPaint,y
         rep #$20
         longa on
         inx
         iny
         dec dPrtCnt
         bne psPaintB
         lda dDst
         clc
         adc #160
         sta dDst
                  cpy    #{PTR_BYTES}
         bne psPaintR
         lda #1
         sta dPtrOn
* The pointer is normally the topmost software layer, but its opaque pixels
* can hide selector/hint borders when it sits on a cell edge. Repaint active
* board frames over it, then record the composed pixels as the cursor paint so
* the idle comparison and guarded restore continue to work without flashing.
         lda dState
         cmp #1
         bne psPaintRecord
         lda dOver
         bne psPaintRecord        ; Game Over has no active board selector frame
         lda dCursor
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
         lda dSelCell
         cmp #$FFFF
         beq psPaintHint
         jsr setFrameCell
         jsr frameMark
         jsr drawFrame
psPaintHint lda dHintA
         cmp #$FFFF
         beq psPaintRecord
         jsr setFrameCell
         jsr frameHint
         jsr drawFrame
         lda dHintB
         jsr setFrameCell
         jsr drawFrame
psPaintRecord
         lda dPtrOff
         sta dDst
         ldy #0
psRecordR ldx dDst
         lda #8
         sta dPrtCnt
psRecordB sep #$20
         longa off
         lda >SCREEN,x
         sta dPtrPaint,y
         rep #$20
         longa on
         inx
         iny
         dec dPrtCnt
         bne psRecordB
         lda dDst
         clc
         adc #160
         sta dDst
         cpy #PTR_BYTES
         bcc psRecordR
         rts

* Restore each 4bpp pixel independently. A game redraw can change one nibble
* (for example, a frame's side pixel) while the other nibble still contains
* our glove; whole-byte compare/skip leaves that glove pixel as a residue.
ptrRestoreByte anop
         sep #$20
         longa off
         lda >SCREEN,x
         sta dPrtCur
         and #$F0
         sta dPrtNib
         lda dPtrPaint,y
         and #$F0
         cmp dPrtNib
         bne prbLow
         lda dPrtCur
         and #$0F
         sta dPrtCur
         lda dPtrSave,y
         and #$F0
         ora dPrtCur
         sta dPrtCur
prbLow  lda dPrtCur
         and #$0F
         sta dPrtNib
         lda dPtrPaint,y
         and #$0F
         cmp dPrtNib
         bne prbStore
         lda dPrtCur
         and #$F0
         sta dPrtCur
         lda dPtrSave,y
         and #$0F
         ora dPrtCur
         sta dPrtCur
prbStore lda dPrtCur
         sta >SCREEN,x
         rep #$20
         longa on
         rts

* Title menu: the pointer selects the item under it and a click chooses it.
titleMouse anop
         lda dMouseX
         cmp #98
         bcc tmOut
         cmp #222
         bcs tmOut
         stz dMTmp
tmLp     lda dMTmp
         cmp #5
         beq tmOut
         asl a
         tax
         lda dMouseY
         sec
         sbc menuYTab,x
         clc
         adc #2
         cmp #11
         bcc tmHit
         inc dMTmp
         bra tmLp
tmHit    lda dMTmp
         cmp dMenuSel
         beq tmNoRedraw
         sta dMenuSel
         jsr titleRedrawMenu
tmNoRedraw lda dMouseClick
         beq tmOut
         stz dMouseClick
         brl tkChoose
tmOut    brl gameExit

*-----------------------------------------------------------------------------
* Hint / reset / game over, and the 5x7 text renderer they need.
*-----------------------------------------------------------------------------
showHint anop
         lda dOver
         bne shRts
         lda dSelCell            ; the original only hints in the steady state
         cmp #$FFFF
         bne shRts
         jsr clearHint
         jsr findHint
         lda dHintA
         cmp #$FFFF
         beq shRts
         jsr setFrameCell
         jsr frameHint
         jsr drawFrame
         lda dHintB
         jsr setFrameCell
         jsr drawFrame
         lda #1
         sta dHintUsed           ; the hinted move scores 0 (original rule)
shRts    rts

clearHint anop
         lda dHintA
         cmp #$FFFF
         beq chRts
         jsr drawCellIndex       ; repaint both cells, erasing the green frames
         lda dHintB
         jsr drawCellIndex
         lda #$FFFF
         sta dHintA
         sta dHintB
chRts    rts

*-----------------------------------------------------------------------------
* First legal swap: tentatively swap in memory, rescan, swap back.
* Returns dHintA/dHintB (or $FFFF) and carry set when a hint was found.
*-----------------------------------------------------------------------------
findHint anop
         lda #$FFFF
         sta dHintA
         sta dHintB
         lda #0
         sta dHCell
fhCell   jsr musYield            ; exhaustive no-move searches can span many tables
         lda dHCell
         and #7
         cmp #7                  ; right neighbour must stay on the same row
         beq fhDown
         lda dHCell
         sta dHa
         inc a
         sta dHb
         jsr hintTest
         bcs fhFound
fhDown   lda dHCell
         cmp #56
         bcs fhNext
         lda dHCell
         sta dHa
         clc
         adc #8
         sta dHb
         jsr hintTest
         bcs fhFound
fhNext   inc dHCell
         lda dHCell
         cmp #64
         bcc fhCell
         clc
         rts
fhFound  lda dHa
         sta dHintA
         lda dHb
         sta dHintB
         sec
         rts

hintTest anop
         lda dHa
         asl a
         tax
         lda dHb
         asl a
         tay
         lda cellgem,x
         sta dTempGem
         lda cellgem,y
         sta cellgem,x
         lda dTempGem
         sta cellgem,y
         jsr scanBoard
         lda dHa
         asl a
         tax
         lda dHb
         asl a
         tay
         lda cellgem,x
         sta dTempGem
         lda cellgem,y
         sta cellgem,x
         lda dTempGem
         sta cellgem,y
         lda dMatchCnt
         beq htNo
         sec
         rts
htNo     clc
         rts

*-----------------------------------------------------------------------------
* Fresh board: no starting match, and at least one legal swap.
*-----------------------------------------------------------------------------
genBoard anop
         jsr seedRandom
         lda #0
         sta dGenTries
gbFill   ldx #0
gbFillLp jsr nextRandom
         sta cellgem,x
         inx
         inx
         cpx #128
         bne gbFillLp
         lda #0
         sta dGenFix
gbSettle jsr musYield            ; board generation/retries must keep streaming
         jsr scanBoard
         lda dMatchCnt
         beq gbCheck
         ldx #0
gbRepl   lda dMark,x
         beq gbReplN
         jsr nextRandom
         sta cellgem,x
gbReplN  inx
         inx
         cpx #128
         bne gbRepl
         inc dGenFix
         lda dGenFix
         cmp #40
         bcc gbSettle
         bra gbRetry
gbCheck  jsr findHint
         lda dHintA
         cmp #$FFFF
         bne gbDone
gbRetry  inc dGenTries
         lda dGenTries
         cmp #40
         bcc gbFill
gbDone   lda #$FFFF
         sta dHintA
         sta dHintB
         rts

resetGame anop
         stz dClockActive
         stz dTimedOut
         stz dTimeDirty
         lda #$FFFF
         sta dDragCell
         jsr clearHint
         lda dState
         cmp #1
         bne rgNoDrop
         lda dOver
         bne rgNoDrop
         jsr dropBoard
rgNoDrop
         lda #$FFFF
         sta dSelCell
         lda #0
         sta dOver
         sta dHintUsed
         sta dScore
         sta dTick60
         sta dHiNew
         lda #120
         sta dTimeLeft
         jsr genBoard
         jsr drawScore
         lda dMode                ; Endless scene has no time panel
         bne rgAfterTime
         jsr drawTime
rgAfterTime
         jsr animAppear           ; original board appearance from above
         lda dCursor
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
         jsr clockRead
         sta dGameTickBase
         lda #1
         sta dClockActive
         jsr musRestart
         rts

*-----------------------------------------------------------------------------
* Game over: dark panel inside the board rectangle (so a plain drawBoard can
* restore it) with heading, final score and the restart/quit keys.
*-----------------------------------------------------------------------------
gameOver anop
         stz dClockActive
         lda #$FFFF
         sta dDragCell
         lda #1
         sta dOver
         lda dSelCell
         cmp #64
         bcs goUnselect
         jsr drawCellIndex
goUnselect lda #$FFFF
         sta dSelCell
         jsr clearHint           ; green hint frames must not survive game over
         jsr dropBoard
         lda #$0000              ; black: uniform on every scanline band
         sta dFillWord
         lda #104
         sta dFillX
         lda #296
         sta dFillX1
         lda #57                 ; centre 90px panel on board y=14..190 (centre 102)
         sta dFillY0
         lda #147
         sta dFillY1
         jsr fillRect
         lda #2
         sta dTScale
         lda #65
         sta dTextY
         lda #147
         sta dTextX
         lda #1
         ldx #strOver
         jsr drawText
         lda #1
         sta dTScale
         lda #89
         sta dTextY
         lda #185
         sta dTextX
         lda #1
         ldx #strScore
         jsr drawText
         jsr gameOverScore
         lda #1
         sta dTScale              ; gameOverScore left the scale at 2
         lda #129
         sta dTextY
         lda #128
         sta dTextX
         lda #1
         ldx #strAgain
         jsr drawText
         lda #137
         sta dTextY
         lda #167
         sta dTextX
         lda #1
         ldx #strQuit
         jsr drawText
         jsr checkHiscore
         jsr drawBestLine
         rts

* Final score as a big centred number.
gameOverScore anop
         lda dScore
         sta dNumVal
         jsr mkNumStr
         lda #2
         sta dTScale
         lda #99
         sta dTextY
         lda dNumLen
         asl a
         sta dTmpW
         asl a
         clc
         adc dTmpW               ; len*6
         sec
         sbc #1                  ; (6*len-1)
         asl a                   ; scale 2
         sta dNumTmp
         lda #192
         sec
         sbc dNumTmp
         lsr a
         clc
         adc #104
         sta dTextX
         lda #1
         ldx #dNumBuf
         jsr drawText
         rts

*-----------------------------------------------------------------------------
* dNumVal -> 5 digits in dNumBuf ; leading zeros blanked, dNumLen = first index
* of a non-space digit .. 5.
*-----------------------------------------------------------------------------
mkNumStr anop
         lda dNumVal
         sta dVal
         lda #4
         sta dNumIdx
mnLp     jsr div10
         sta dNumTmp
         sep #$20
         longa off
         lda dNumTmp
         ora #$30
         ldx dNumIdx
         sta dNumBuf,x
         rep #$20
         longa on
         lda dQuot
         sta dVal
         dec dNumIdx
         lda dNumIdx
         bpl mnLp
         lda #0
         sta dNumIdx
mnTrim   lda dNumIdx
         tax
         sep #$20
         longa off
         lda dNumBuf,x
         sta dNumTmp
         rep #$20
         longa on
         lda dNumTmp
         and #$00FF
         cmp #'0'
         bne mnScan
         lda dNumIdx
         cmp #4
         bcs mnScan
         sep #$20
         longa off
         lda #$20
         sta dNumBuf,x
         rep #$20
         longa on
         inc dNumIdx
         lda dNumIdx
         cmp #4
         bcc mnTrim
mnScan   lda #0
         sta dNumIdx
mnScanLp
         lda dNumIdx
         tax
         sep #$20
         longa off
         lda dNumBuf,x
         sta dNumTmp
         rep #$20
         longa on
         lda dNumTmp
         and #$00FF
         cmp #$20
         bne mnFound
         inc dNumIdx
         lda dNumIdx
         cmp #5
         bcc mnScanLp
mnFound  lda #5
         sec
         sbc dNumIdx
         sta dNumLen
* Shift the digits down over the blanked leading zeros so the caller can
* centre the number from its real width.
         lda #0
         sta dNumTmp
mnShift  lda dNumTmp
         cmp dNumLen
         bcs mnShiftDone
         clc
         adc dNumIdx
         tax
         sep #$20
         longa off
         lda dNumBuf,x
         ldx dNumTmp
         sta dNumBuf,x
         rep #$20
         longa on
         inc dNumTmp
         bra mnShift
mnShiftDone
         lda #0
         sep #$20
         longa off
         ldx dNumLen
         sta dNumBuf,x           ; terminator right after the last digit
         rep #$20
         longa on
         rts

*-----------------------------------------------------------------------------
* 5x7 text: X = NUL-terminated string, A = colour nibble (SHR slot).
* dTextX/dTextY = pixel origin, dTScale = 1 or 2. Glyphs are 8 bytes in
* txtglyphs (ASCII 32..90), 6*scale pixels of advance per character.
*-----------------------------------------------------------------------------
drawText anop
         sta dTColorNib
         stx dTextBase
         lda #0
         sta dTIdx
         lda dTColorNib
         and #$000F
         sta dTColorLo
         lda dTColorNib
         asl a
         asl a
         asl a
         asl a
         sta dTColorHi
         lda dTextBase
         sta dtStrOp+1
dtChar   ldy dTIdx
         sep #$20
         longa off
dtStrOp  lda $0000,y
         sta dTChar
         rep #$20
         longa on
         lda dTChar
         and #$00FF
         bne dtHaveCh
         brl dtEnd
dtHaveCh inc dTIdx
         sec
                  sbc    #{32}
         bcc dtBlank
         cmp #91                 ; TEXT_LAST - TEXT_FIRST + 1 (32..122)
         bcc dtGlyph
         bra dtBlank
dtBlank  lda #0
dtGlyph  asl a
         asl a
         asl a
         sta dGlyphOfs
         lda #0
         sta dTRow
         lda dTextY
         sta dPlotY
dtRowLp  lda dGlyphOfs
         clc
         adc dTRow
         tax
         lda txtglyphs,x
         and #$001F
         sta dGlyphRow
         lda dTextX
         sta dPlotX
         lda #0
         sta dTCol
dtColLp  lda dGlyphRow
         and #$0010
         beq dtNoPix
         jsr plotBlock
dtNoPix  asl dGlyphRow
         lda dPlotX
         clc
         adc dTScale
         sta dPlotX
         inc dTCol
         lda dTCol
         cmp #5
         bcc dtColLp
         lda dPlotY
         clc
         adc dTScale
         sta dPlotY
         inc dTRow
         lda dTRow
         cmp #7
         bcc dtRowLp
         lda #6
         ldx dTScale
         cpx #1
         beq dtAdv1
         asl a
dtAdv1   clc
         adc dTextX
         sta dTextX
         jsr musYield            ; long help/menu text must not starve the DOC
         brl dtChar
dtEnd    rts

plotBlock anop
         lda dTScale
         cmp #1
         bne pbTwo
         lda dPlotX
         sta dPx
         lda dPlotY
         sta dPy
         jsr plotPixel
         rts
pbTwo    lda dPlotX
         sta dPx
         lda dPlotY
         sta dPy
         jsr plotPixel
         lda dPx
         inc a
         sta dPx
         jsr plotPixel
         lda dPlotY
         inc a
         sta dPy
         jsr plotPixel
         lda dPx
         dec a
         sta dPx
         jsr plotPixel
         rts

plotPixel anop
         lda dPy
         asl a
         asl a
         asl a
         asl a
         asl a
         sta dTmpW
         asl a
         asl a
         clc
         adc dTmpW               ; dPy*160
         sta dRowBase
         lda dPx
         lsr a
         clc
         adc dRowBase
         tax
         lda dPx
         and #$0001
         bne ppOdd
         sep #$20
         longa off
                  lda    >SCREEN,x
         and #$0F
         ora dTColorHi
                  sta    >SCREEN,x
         rep #$20
         longa on
         rts
ppOdd    sep #$20
         longa off
                  lda    >SCREEN,x
         and #$F0
         ora dTColorLo
                  sta    >SCREEN,x
         rep #$20
         longa on
         rts

*-----------------------------------------------------------------------------
* Filled rectangle: dFillWord, x from dFillX (even) to dFillX1, rows dFillY0
* (inclusive) to dFillY1 (exclusive).
*-----------------------------------------------------------------------------
fillRect anop
         lda dFillY0
         sta dFillY
flRow    lda dFillY
         asl a
         asl a
         asl a
         asl a
         asl a
         sta dTmpW
         asl a
         asl a
         clc
         adc dTmpW
         sta dRowBase
         lda dFillX
         lsr a
         clc
         adc dRowBase
         tax
         lda dFillX1
         sec
         sbc dFillX
         lsr a                   ; pixels -> bytes ...
         lsr a                   ; ... and bytes -> words (1 word = 4 px)
         sta dFillCnt
flWord   lda dFillWord
                  sta    >SCREEN,x
         inx
         inx
         dec dFillCnt
         bne flWord
         inc dFillY
         lda dFillY
         cmp dFillY1
         bcc flRow
         rts

*-----------------------------------------------------------------------------
* Title / how-to-play / mode selection (M3).
*
* All four full-screen pictures (TITLE.RAW, HOWTO.RAW, SCENE4.RAW, SCENE4E.RAW)
* are 32000-byte 4bpp images streamed into SCREEN through one shared GS/OS
* Open/Read/Close pblock trio: only the pblock's pathname pointer is patched,
* so loadScene can play any of them.
*
* The picture is read as 32 sequential 1000-byte slices with musPump calls
* between slices.  A single 32 KB Read blocks the main loop for ~23 frames
* (0.38 s on GSSquared) and the DOC music table is only 21.97 frames long, so
* every screen change used to run the music dry for up to 0.38 s.  Sequential
* reads advance the file mark just like the MUSIC.PCM streamer relies on, and
* the per-slice musStep keeps the standby buffer queued (see musStep/MUS_GUARD).
*-----------------------------------------------------------------------------
LOAD_SLICES equ 32
LOAD_CHUNK  equ 1000
* musStep moves MUS_CHUNK bytes per call; musPump tops up the standby table
* during a scene load so the DOC does not run dry. It copies up to 2048 B
* between reads, outpacing the shorter scene slice;
* extra calls are nearly free because musStep returns at once once the standby
* buffer is full (dMusTotal = MUS_LEN).
loadScene anop
         lda dPathPtr
         sta pbOpen+4           ; pblock pathname pointer (same bank as code)
         jsr musPump            ; top the standby buffer up before the Open blocks
         sep #$20
         longa off
         lda #1
         sta >$019CFE
         rep #$20
         longa on
         jsl $E100A8
         dw  $2010              ; Open
         adrl pbOpen
         bcc lsOpened
         sta >$019CFC
         jsr fallbackFill
         rts
lsOpened lda pbOpen+2          ; refNum
         sta pbRead+2
         sta pbClose+2
                  lda    #LOAD_CHUNK
         sta pbRead+8           ; length of one slice (long: high word stays 0)
         stz pbRead+10
         stz dLoadOfs
         stz dLoadErr
                  lda    #LOAD_SLICES
         sta dLoadCnt
lsChunk  lda dLoadOfs
         clc
         adc #$2000             ; low word of $012000 + slice offset (bank 1)
         sta pbRead+4
         sep #$20
         longa off
         lda #2
         sta >$019CFE
         rep #$20
         longa on
         jsl $E100A8
         dw  $2012              ; Read
         adrl pbRead
         bcs lsSliceBad
         lda dLoadOfs
         clc
                  adc    #LOAD_CHUNK
         sta dLoadOfs
         jsr musPump            ; the disk is busy: keep the DOC fed
         dec dLoadCnt
         bne lsChunk
         bra lsClose
lsSliceBad
         sta >$019CFC
         lda #1
         sta dLoadErr
lsClose  sep #$20
         longa off
         lda #3
         sta >$019CFE
         rep #$20
         longa on
         jsl $E100A8
         dw  $2014              ; Close
         adrl pbClose
         lda dLoadErr
         bne lsFill
         rts
lsFill   jsr fallbackFill
         rts

*-----------------------------------------------------------------------------
* DOC audio (M4).
*
* Five 8-bit unsigned PCM waves are uploaded to the Ensoniq 5503 wave RAM once
* at boot ; SCREEN ($012000) is the staging buffer, and the title scene load
* right after overwrites it, so nothing stays resident in main memory.
* playSound only reprograms oscillator registers, which costs a few hundred
* cycles and is safe to call from the game loop.
*
* DOC RAM map (the $C0+n wave-size register picks the table length):
*   $0000 SELECT 4K   $1000 FALL 4K    $2000 MATCH1 16K
*   $6000 MATCH2 16K  $A000 MATCH3 16K
*   $E000 MUSIC A 4K   $F000 MUSIC B 4K
* The two music buffers take the rest of the 64 KB ; SELECT/FALL only need 4K
* (their waves are 0.14 s and 0.18 s) and that is what paid for them.
*
* Playback rate with eight oscillators enabled (=$E1 0E) is
*   894886/(8+2) * freq / 2^(9+res-size)
* so 4K tables use size 4 / res 0 / freq 4, 8K tables size 5 / res 1 / freq 4
* and 16K tables size 6 / res 0 / freq 1 ; all land on 11186 Hz, the rate
* build_iigs_sounds.py resamples to.
*
* Oscillators 0/1 play SELECT, 2/3 FALL and 4/5 MATCHx, so a match can ring over
* a fall (and over the next select) instead of cutting it off ; the original
* never mixes, but a single pair would truncate every effect. Each pair carries
* both DOC channel bits (control $02 on the even oscillator, $12 on the odd one)
* so the effect is audible on both outputs.
*-----------------------------------------------------------------------------
* DOC output level.  The main volume nibble is not a taste knob: how loud a
* voice comes out depends on how each emulator weights the mix.
*
*   GSSquared 2026-10 (the build anomixer.github.io/gssquared serves) does
*       sample = sum(data*vol*mult) * 64 / (oscEnabled+2) * (256/atten[nibble])
*   -- k_doc_makeup 64, slots = oscEnabled+2, atten[15]=256 -- which is about
*   51x louder than the older "data*vol/8" build in C:\dev\emu\gssquared.
*   At vol $78/nibble 15 the music hit the int16 clamp on every beat, which is
*   exactly the "too loud, all distorted, bo~bo~" report from the web build.
*
* GSplus (and KEGS) mix as data*vol*(nibble/16) and the Sep-30 GSSquared
* desktop exe as ~data*vol/8, so the same nibble that tames the web build also
* keeps those two audible.  127*vol*6.4*0.126 (web) and 127*vol*6/16 (GSplus)
* both land under 0.3 FS at these values, and the older desktop exe stays at
* ~0.35 FS instead of clipping.
*
* DOC_VOL is the $C03C low nibble used for the whole game ; the mode bits above
* it are added per use ($6n wave+auto-inc, $4n wave, $0n register file).
DOC_VOL           equ    $06
DOC_FX_VOL        equ    $50                  ; per-oscillator volume for the five effects
*-----------------------------------------------------------------------------
audioInit anop
         sep #$20
         longa off
                  lda    #$00                 ; register mode, main volume 0 first
                  sta    >$01C03C
* The GS/OS startup chime may still be running in the DOC when a SetStart app
* takes over. Its oscillators keep pointing into wave RAM that loadSounds then
* overwrites, so they would replay our effect data at full volume. Halt every
* oscillator while the main volume is still 0, then set up the chip and restore
* the volume. (This does *not* explain the 40 ms startup burst logged in
* See iigs/AGENTS.md for the current audio validation status.)
                  ldx    #0
aiHalt            txa
                  ora    #$A0                 ; oscillator control register $A0+n
                  sta    >$01C03E
                  lda    #$01                 ; halt
                  sta    >$01C03D
                  inx
                  cpx    #8
                  bcc    aiHalt
                  lda    #DOC_VOL               ; register mode, main volume nibble 6
         sta >$01C03C
         lda #$E1
         sta >$01C03E
         lda #$0E                 ; 8 oscillators -> DOC sample clock 89488.6 Hz
         sta >$01C03D
         rep #$20
         longa on
         rts

* Halt the six effect oscillators (control bit 0 = 1). Oscillators 6/7 carry
* the streamed music and are only stopped by musStop, so muting effects from the
* Options screen never cuts the music.
audioStop anop
         sep #$20
         longa off
         ldx #0
asLoop   txa
         ora #$A0                 ; oscillator control register $A0+n
         sta >$01C03E
         lda #$01
         sta >$01C03D
         inx
         cpx #6
         bcc asLoop
         rep #$20
         longa on
         rts

* Upload dSndLen bytes of SCREEN into DOC RAM at dDocBase. $C03C bit6 selects
* wave RAM, bit5 auto-increments the address after every $C03D write ; the low
* nibble is the main volume, so it must stay non-zero.
docUpload anop
         sep #$20
         longa off
                  lda    #DOC_VOL+$60           ; wave RAM + auto-increment + main volume
         sta >$01C03C
         lda dDocBase
         sta >$01C03E
         lda dDocBase+1
         sta >$01C03F
         ldx #0
duLoop            lda    >SCREEN,x
         sta >$01C03D
         inx
         cpx dSndLen
         bcc duLoop
* Read three bytes of the wave RAM back through $C03D (the port is a one-access
* pipeline: the first read returns the previous latch, the second the byte at
* the current address) and compare them with the source in SCREEN. dSndOk /
* dSndBad are the socket harness proof that the upload really landed.
                  lda    #DOC_VOL+$40           ; wave RAM, no auto-increment + main volume
         sta >$01C03C
         ldx #0
         jsr dvCheck              ; first byte
         lda dSndLen
         lsr a
         tax
         jsr dvCheck              ; middle byte
         lda dSndLen
         dec a
         tax
         jsr dvCheck              ; last byte
* $C03C is an 8-bit soft switch and dvCheck left A 16-bit wide: a word store
* here also put $00 into $C03D (the DOC data port) and the chip stayed in
* wave-RAM mode, so every later oscillator register write went into wave RAM
* instead of the register file and no sound was ever heard.
         sep #$20
         longa off
                  lda    #DOC_VOL               ; back to register mode, keep main volume
         sta >$01C03C
         rep #$20
         longa on
         rts

* A = byte at DOC RAM dDocBase + X. X is preserved.
docSample anop
         rep #$20
         longa on
         txa
         clc
         adc dDocBase
         sta dSndY
         sep #$20
         longa off
         lda dSndY
         sta >$01C03E
         lda dSndY+1
         sta >$01C03F
         lda >$01C03D             ; priming read (pipeline)
         lda >$01C03D             ; the byte at the latched address
         rep #$20
         longa on
         rts

* Compare DOC RAM[X] with the staged source byte SCREEN[X] ; bump dSndOk/dSndBad.
dvCheck anop
         phx
         jsr docSample
         sep #$20                 ; docSample exits 16-bit; the compare is a byte
         longa off
         sta dSndByte
         plx
                  lda    >SCREEN,x
         cmp dSndByte
         bne dvBad
         inc dSndOk
         bra dvOut
dvBad    inc dSndBad
dvOut    rep #$20
         longa on
         rts

* Stream one wave file into SCREEN (dPathPtr = GS/OS name) and upload it.
sndLoadOne anop
         lda dPathPtr
         sta pbSndOpen+4
         jsl $E100A8
         dw  $2010                ; Open
         adrl pbSndOpen
         bcs sloOut
         lda pbSndOpen+2
         sta pbSndRead+2
         sta pbSndClose+2
         lda dSndLen
         sta pbSndRead+8          ; length is a long: low word, zero high word
         lda #0
         sta pbSndRead+10
         jsl $E100A8
         dw  $2012                ; Read
         adrl pbSndRead
         php
         jsl $E100A8
         dw  $2014                ; Close
         adrl pbSndClose
         plp
         bcs sloOut
         jsr docUpload
sloOut   rep #$20
         longa on
         rts

* Boot: program the chip, then walk audTab (name, DOC base, length, $C0 value,
* frequency). Run before the title scene load because SCREEN is the staging
* buffer ; dPathPtr must be re-set by the caller afterwards.
loadSounds anop
         jsr audioInit
         jsr audioStop
         stz dSndIdx
lsLoop   lda dSndIdx
         asl a
         asl a
         asl a
         asl a
         tax                       ; X = 16-byte audTab entry
         lda audTab,x             ; low word of the name pointer
         sta dPathPtr
         lda audTab+4,x
         sta dDocBase
         lda audTab+6,x
         sta dSndLen
         jsr sndLoadOne
         inc dSndIdx
         lda dSndIdx
                  cmp    #{5}
         bcc lsLoop
         rts

* A = sound id: 0 select, 1 fall, 2..4 match1..3.
playSound anop
         sta dSndIdx
         lda dSoundOn
         bne psPlay
         inc dSndTot             ; muted: still count the trigger for tests
         jsr audioStop
         rts
psPlay   lda dSndIdx
         asl a
         asl a
         asl a
         asl a
         tax                       ; X = wave table entry
         lda dSndIdx
         cmp #2
         bcs psMatch
         asl a                     ; select/fall: oscillator pair 0/1 or 2/3
         bra psBase
psMatch  lda dMatchVoice          ; alternate match voices so cascades can overlap
         eor #4                   ; match pairs 0/1 and 4/5; fall keeps pair 2/3
         sta dMatchVoice
psBase   sta dSndBase
         sta dSndY
         lda audTab+10,x
         sta dSndFreq
         lda audTab+8,x
         sta dSndC0
         lda audTab+4,x
         sta dDocBase
         jsr docRegs
         inc dSndTot
         rts

* Program both oscillators of the dSndBase pair from dSndFreq/dSndC0/dDocBase,
* then start them one-shot. Register order matters: frequency, volume, wave
* address and table size before the control write that enables the oscillator.
docRegs anop
* A pair can still be active when a cascade retriggers it. Halt both voices
* first so the following control writes have a real stopped->playing edge;
* otherwise GSplus/KEGS keep the old accumulator and the new effect starts at
* an arbitrary point in its wave table.
         sep #$20
         longa off
         lda dSndBase
         ora #$A0
         sta >$01C03E
         lda #$01
         sta >$01C03D
         lda dSndBase
         inc a
         ora #$A0
         sta >$01C03E
         lda #$01
         sta >$01C03D
         rep #$20
         longa on
         lda dSndBase
         sta dSndY
         sep #$20
         longa off
         ldx #0
drLoop   lda dSndY
         sta >$01C03E             ; +$00 frequency low
         lda dSndFreq
         sta >$01C03D
         lda dSndY
         ora #$20
         sta >$01C03E             ; +$20 frequency high
         lda dSndFreq+1
         sta >$01C03D
         lda dSndY
         ora #$40
         sta >$01C03E             ; +$40 volume
                  lda    #DOC_FX_VOL
         sta >$01C03D
         lda dSndY
         ora #$80
         sta >$01C03E             ; +$80 wave start address (addr >> 8)
         lda dDocBase+1
         sta >$01C03D
         lda dSndY
         ora #$C0
         sta >$01C03E             ; +$C0 table size / resolution
         lda dSndC0
         sta >$01C03D
         inc dSndY
         inx
         cpx #2
         bcc drLoop
         lda dSndY
         sec
         sbc #2
         sta dSndY                ; back to the even oscillator of the pair
         ora #$A0
         sta >$01C03E             ; control: one-shot, channel bit clear
         lda #$02
         sta >$01C03D
         lda dSndY
         ora #$A1
         sta >$01C03E             ; control: one-shot, channel bit set
         lda #$12
         sta >$01C03D
* Read four registers of the even oscillator back and compare them with what we
* meant to write: if the DOC took the frequency, volume, wave address and table
* size at all, these match. (The emulator cannot record its audio output, so
* this plus the wave-RAM readback is the strongest evidence available.)
         rep #$20
         longa on
         lda dSndBase
         sta dSndReg
         lda dSndFreq
         and #$00FF
         sta dSndExp
         lda dSndReg
         jsr chkReg               ; +$00 frequency low
         lda dSndBase
         clc
         adc #$40
         sta dSndReg
         lda #DOC_FX_VOL
         sta dSndExp
         lda dSndReg
         jsr chkReg               ; +$40 volume
         lda dSndBase
         clc
         adc #$80
         sta dSndReg
         lda dDocBase
         xba
         and #$00FF
         sta dSndExp
         lda dSndReg
         jsr chkReg               ; +$80 wave address (addr >> 8)
         lda dSndBase
         clc
         adc #$C0
         sta dSndReg
         lda dSndC0
         and #$00FF
         sta dSndExp
         lda dSndReg
         jsr chkReg               ; +$C0 table size / resolution
         rep #$20
         longa on
         rts

* A = DOC register number, dSndExp = expected byte. Bump dSndRegOk/dSndRegBad.
chkReg anop
         sep #$20
         longa off
         sta >$01C03E             ; register select (one byte: never touch $C03F)
         lda >$01C03D             ; priming read (pipeline)
         lda >$01C03D             ; the register value
         cmp dSndExp
         bne crBad
         inc dSndRegOk
         bra crOut
crBad    inc dSndRegBad
crOut    rep #$20
         longa on
         rts

* Choose the match sample by depth within this cascade: first clear MATCH1,
* first cascade MATCH2, and every later cascade MATCH3.
matchSound anop
         lda dCasc
         cmp #1
         beq msDepthOne
         cmp #2
         beq msDepthTwo
         lda #4
         bra msCascadePlay
msDepthOne lda #2
         bra msCascadePlay
msDepthTwo lda #3
msCascadePlay
         jsr playSound
         rts

fallSound anop
         lda #1
         jsr playSound
         rts

*-----------------------------------------------------------------------------
* DOC music streaming (M5).
*
* music.ogg is 126 s, far more than the 64 KB of wave RAM, so MUSIC.PCM is
* cached in main RAM: oscillators 6/7 play a 4K buffer (0.366 s at 11186 Hz)
* while the *other* 4K buffer ($E000 / $F000) is copied from the cache in 256-byte
* slices. Every
* buffer switch re-programs both oscillators, so the swap is an exact restart at
* the new base and the two buffers alternate for as long as the music plays.
*
* Timing is kept in 1/16 frame units of the VSYNC counter (dMusTick16).  The
* tick is only a stopwatch, never the switch itself: it exists to bound how long
* we wait for the DOC's end-of-table flag, and to hand out one MUS_FRAC per
* switch so the count stays in step with what the chip plays.
*
* Why the flag has to win (2026-10-24): the emulators disagree about the DOC
* sample rate.  GSplus plays a 4K table at ~10240 Hz (0.400 s) while the tick
* constant is calibrated for 11186 Hz (0.366 s), so a tick-driven switch fired
* ~30 ms early and cut the wave mid-slope -- an audible "bo~ bo~" every 0.4 s
* that the user heard on GSplus but not on GSSquared.  Waiting for the chip's
* own flag makes the switch exact at whatever rate the emulator runs ; the tick
* is only the escape hatch for an emulator that never sets the flag.  The
* counter wraps every 68 s, which is harmless: dMusStart is always re-based on
* the live count, and the difference never comes close to 32768.
*-----------------------------------------------------------------------------
MUS_LEN    equ 4096            ; one music buffer, 0.366 s at 11186 Hz
* The DOC data port is slow: every $C03D write costs ~90 cycles, so copying 512
* bytes in one call stalls the main loop for ~46 000 cycles (a whole frame).
* That burst ran the input poll at ~60 Hz and froze the pointer/menu for ~130 ms
* while a 4 KB buffer refilled.  128 bytes per call spreads the same bandwidth
* evenly over 32 calls (~0.18 s), keeps the loop at a few milliseconds and polls
* the ADB mouse every loop instead of once per frame.
MUS_CHUNK  equ 256             ; 60 VBL services/s refill >15 KB/s (>11.2 KB/s consumed)
MUS_FRAC   equ 352             ; 4096/11186*60*16 = 351.5 sixteenths of a frame
MUS_GUARD  equ 6               ; only trust the halt flag this many calls after a
*                              ; restart: the bit also reads set for a moment then
MUS_HARD          equ    448                  ; 28 frames: switch even if the chip never says so
MUS_OSC    equ 6               ; oscillators 6/7 carry the music on both channels
MUS_BUF_A  equ $E000
MUS_BUF_B  equ $F000
MUS_VOL           equ    $D0                  ; music is a background layer, not a foreground FX
                               ; (tuned for the 2026-10 GSSquared mix + DOC_VOL $06;
                               ; see the DOC output level note before audioInit)
* The ES5503 "volume glitch" triples the last *enabled* oscillator (here osc 7),
* and both music oscillators play the same mono buffer on separate channels --
* so the right channel came out 3x louder than the left.  Write last-osc
* volume = MUS_VOL/3 so both channels carry the same level.
MUS_VOL_LAST      equ    $45                  ; 207/3: cancels the 3x glitch on oscillator 7

* Restart the track from the top for a new round.  MUSIC.PCM is 126 s and one
* Time Trial round is 120 s, so a restart at game start means the whole round
* gets the track from its first bar instead of dropping in wherever the title
* screen happened to leave the stream. Queue it for the next DOC boundary so
* rewinding does not halt the music during a complete 4K upload.
musRestart        anop
                  lda    dMusOn
                  beq    mrOut
                  lda    dMusState
                  beq    mrStart
* Defer disk rewind until musSwitch has just started a full, queued table.
* Replacing a partly uploaded standby immediately could leave less than one
* chunk of playback time to upload all 4K again, producing a 0.2s gap.
                  lda    #1
                  sta    dMusRewind
                  inc    dMusRestart
                  rts
mrStart           jsr    musStart
                  inc    dMusRestart
mrOut             rts

* Start the music at the top of MUSIC.PCM if it is enabled and not already
* running.  Called once at boot and again when Options turns Music back on.
musStart anop
         lda dMusOn
         bne msOn
         rts
msOn     lda dMusState
         beq msBegin
         rts
msBegin  lda dMusCacheState
         cmp #1
         beq msCached
         cmp #2
         beq msStreamOpen
         jsr musCacheLoad
         bcc msCached
msStreamOpen
         jsr musOpen
         bcc msStreamReady
         brl msBad
msStreamReady
         stz dMusCacheState       ; a later start may retry the RAM cache
         bra msOpened
msCached
         stz dMusPos
         stz dMusPos+2
msOpened
         stz dMusRewind
         stz dMusBuf
         jsr musFillStage       ; first 4K of PCM into the staging buffer
         bcc msFirst
         brl msBadClose
msFirst
         lda #1                 ; "standby" is A for this one full copy
         sta dMusBuf
         jsr musCopyAll
         stz dMusBuf            ; A is the buffer that plays
         stz dMusTotal
         stz dMusReady
         stz dMusIrqPending
         stz dMusIrqSwitched
         jsr musIrqInstall      ; install our tiny DOC-end callback before osc 6 starts
         jsr musPlay
         lda dMusTick16
                  sta    dMusStart
         clc
                  adc    #{352}
         sta dMusEnd
         lda #1
         sta dMusState
         inc dMusOk
         jsr musFillStage       ; the next 4K is now waiting for buffer B
         bcc msOut
         brl msBadClose
msBadClose
         jsr musClose
msBad    inc dMusBad
msOut    rts

* Per-frame service: swap buffers when the playing one has run out, otherwise
* copy the next slice of the standby buffer.
*
* musStep moves MUS_CHUNK bytes per call ; while a GS/OS read blocks the main
* loop the buffer needs several calls just to stay level.
* musPump makes eight calls (2048 B) per slice, up to 64 KB over the slices of a
* scene load, and once dMusTotal = MUS_LEN every extra call returns at once, so
* pumping from loadScene costs nothing in steady state.
MUS_PUMP_N equ 8

musPump anop
         php
                  ldx    #{8}
mppLoop  phx
         jsr musStep
         plx
         dex
         bne mppLoop
         plp
         rts

* Rendering loops own their A/X/Y and flags. Yield only at complete row/cell/
* character boundaries; music I/O uses its own pblocks and scratch variables.
musYield anop
         php
         rep #$30
         pha
         phx
         phy
         jsr musStep
         ply
         plx
         pla
         plp
         rts

* Keep the music clock alive in loadScene/musPump and waitFrame as well as the
* main loop. The old clock only advanced in vsyncPoll, so a halted DOC table
* could never pass MUS_MINPLAY during a scene load or a long cascade.
* Use a separate edge latch: music service must not consume the game's VBL.
musClock anop
         jsr clockAdvance
         rts

musStep anop
         jsr musClock
         lda dMusState
         bne mstOn
         rts
mstOn    lda dMusIrqInstalled
         beq mstLegacy
* DOC callback starts a complete standby table at the oscillator boundary.
* Foreground only acknowledges the event and prepares the next table.
         lda dMusIrqPending
         beq mstIrqFill
         lda dMusIrqSwitched
         beq mstIrqWait
         stz dMusIrqPending
         stz dMusIrqSwitched
         inc dMusHalt
         jsr musPostSwitch
         bra mstIrqFill
mstIrqWait
         lda dMusReady
         beq mstIrqFill
         stz dMusIrqPending
         jsr musSwitch
         bra mstIrqFill
mstIrqFill
         lda dMusTotal
         cmp #MUS_LEN
         bcs mstOut
         jsr musChunk
* An IRQ can arrive during the final chunk. If it had to wait for that chunk,
* complete the switch now before returning to the long drawing routine.
         lda dMusIrqPending
         beq mstOut
         lda dMusIrqSwitched
         bne mstIrqAgain
         lda dMusReady
         beq mstOut
         stz dMusIrqPending
         jsr musSwitch
         bra mstIrqFill
mstIrqAgain
         stz dMusIrqPending
         stz dMusIrqSwitched
         inc dMusHalt
         jsr musPostSwitch
         bra mstIrqFill
mstLegacy
         inc dMusGuard
         jsr musHaltChk
         bcc mstLate
         inc dMusHalt
         lda dMusGuard
         cmp #6
         bcc mstLate
         bra mstSwap
mstLate  lda dMusTick16
         sec
         sbc dMusStart
         cmp #448
         bcs mstSwap
         bra mstFill
mstSwap  lda dMusTotal
         cmp #MUS_LEN
         bcs mstReady
         jsr musChunk
         rts
mstReady jsr musSwitch
         rts
mstFill  lda dMusTotal
         cmp #MUS_LEN
         bcs mstOut
         jsr musChunk
mstOut   rts

* Carry set = oscillator 6 has run off the end of its 4K table and halted.
* This is the *real* end of the buffer ; dMusTick16 only approximates it, and it
* runs slow whenever vsyncPoll misses a VBL edge (the game loop is occasionally
* longer than a frame), which used to leave a 30-45 ms hole at every switch:
* measured on GSSquared, the tick's switch period was 0.404 s against a 0.366 s
* table, i.e. exactly that much silence each time. Reading the DOC control
* register back (SOUNDCTL = register number, SOUNDDATA = value) is legal in
* register mode and GSSquared reports bit 0 = "halted", so the switch now fires
* on the chip's own end-of-table flag and the tick is only a fallback.
musHaltChk anop
         sep #$20
         longa off
                  lda    #DOC_VOL               ; register mode + main volume (idempotent)
         sta >$01C03C
         lda #$A6               ; control register of oscillator 6
         sta >$01C03E           ; register select lives in SOUNDADRL, not SOUNDCTL
         lda >$01C03D           ; priming read: the data port is one byte deep
         lda >$01C03D           ; this is the register value (see chkReg)
         and #$01
         rep #$20
         longa on
         bne mhcYes
         clc
         rts
mhcYes   sec
         rts

musSwitch anop
         lda dMusTotal
         cmp #MUS_LEN
         bcs mswGo
         jsr musStop
         jsr musStart
         rts
mswGo    lda dMusBuf
         eor #1
         sta dMusBuf
         jsr musBase
         jsr musPlay
musPostSwitch
         lda dMusTick16
         sta dMusStart
         clc
         adc #352
         sta dMusEnd
         inc dMusOk
         lda dMusRewind
         beq mswFill
         stz dMusRewind
         lda dMusCacheState
         cmp #1
         beq mswRewindMem
         jsr musReopen
         bcs mswBad
         bra mswFillStage
mswRewindMem
         stz dMusPos
         stz dMusPos+2
         bra mswFillStage
mswFillStage
mswFill  jsr musFillStage
         bcc mswOk
         brl mswBad
mswOk    stz dMusTotal
         stz dMusChunk
         rts
mswBad   inc dMusBad
         jsr musStop
         rts

* DOC callback setup follows Silky-GS's Sound Interrupt JML stub at $E1002C.
* It saves/restores the system's four-byte stub. The handler is deliberately
* tiny: it checks osc 6 and starts only a fully prepared alternate 4K table;
* PCM reads/copies and song bookkeeping remain in the foreground.
MUS_INT_VECTOR equ $E1002C
MUS_INT_SOURCE equ $E100CC
musIrqInstall anop
         lda dMusIrqInstalled
         bne miiOut
         php
         sei
         ldal MUS_INT_VECTOR
         sta dMusIrqOld
         ldal MUS_INT_VECTOR+2
         sta dMusIrqOld+2
         sep #$20
         longa off
         lda #$5C                 ; JML long target
         stal MUS_INT_VECTOR
         rep #$20
         longa on
         lda #musIrqHandler
         stal MUS_INT_VECTOR+1
         sep #$20
         longa off
         phk
         pla
         stal MUS_INT_VECTOR+3
         rep #$20
         longa on
         lda #1
         sta dMusIrqInstalled
         plp
miiOut   rts

musIrqRestore anop
         lda dMusIrqInstalled
         beq mirOut
         php
         sei
* Drain a latched DOC source after osc 6/7 have been halted and before the
* system callback is restored, so no late IRQ can enter code being unloaded.
         sep #$20
         longa off
         lda #DOC_VOL
         sta >$01C03C
         ldx #32
mirDrain lda #$E0
         sta >$01C03E
         lda >$01C03D
         lda >$01C03D
         bmi mirDrained
         dex
         bne mirDrain
mirDrained
         rep #$20
         longa on
         lda dMusIrqOld
         stal MUS_INT_VECTOR
         lda dMusIrqOld+2
         stal MUS_INT_VECTOR+2
         stz dMusIrqInstalled
         plp
mirOut   rts

musIrqHandler anop
         php
         sep #$30
         phb
         phd
         phk
         plb
         clc
         xce                    ; Silky-GS normalizes sound callback entry to native mode
         rep #$30
         pha
         phx
         phy
         sep #$20
         longa off
         ldal MUS_INT_SOURCE      ; pending oscillator ID (DOC reports index * 2)
         and #$3E
         cmp #$0C                 ; oscillator 6
         bne mihDone8
         rep #$20
         longa on
         lda dMusState
         beq mihDone16
         lda dMusReady
         beq mihPending
* Start the opposite, completely filled 4K table at this hardware boundary.
         lda dMusBuf
         eor #1
         sta dMusBuf
         jsr musBase
         jsr musPlay
         stz dMusTotal
         stz dMusReady
         lda dMusTick16
         sta dMusStart
         lda #1
         sta dMusIrqSwitched
mihPending
         lda #1
         sta dMusIrqPending
mihDone16
mihDone8 rep #$30
         longa on
         pld
         plb
         ply
         plx
         pla
         plp
         clc
         rtl

* dMusBase = DOC base of the playing buffer (dMusBuf), or of the standby when
* musStandby computed the inverted index.
musBase anop
         lda dMusBuf
         beq mbA
                  lda    #MUS_BUF_B
         bra mbSet
mbA               lda    #MUS_BUF_A
mbSet    sta dMusBase
         rts

musStandby anop
         lda dMusBuf
         eor #1
         beq msbA
                  lda    #MUS_BUF_B
         bra msbSet
msbA              lda    #MUS_BUF_A
msbSet   sta dMusBase
         rts

* Program oscillators 6/7 for dMusBase and start them: even oscillator on
* channel A ($02), odd on channel B ($12), 4K table ($20) at 11186 Hz (freq 4).
* The DOC register number is the oscillator index (X), not the wave RAM
* address ; only the $80 pointer byte comes from dMusBase+1.  Using the base
* address as the register number programmed oscillators 0/1 instead, which is
* exactly what the earlier silent run did.
musPlay anop
         stz dMusGuard
         sep #$20
         longa off
                  ldx    #{6}
mplLoop  txa
         sta >$01C03E           ; oscillator X: frequency low
         lda #4
         sta >$01C03D
         txa
         ora #$20
         sta >$01C03E           ; frequency high
         lda #0
         sta >$01C03D
         txa
         ora #$40
         sta >$01C03E           ; volume
                  lda    #MUS_VOL
                  cpx    #{6}+1               ; last enabled osc is tripled by the chip
                  bne    mplVol
                  lda    #MUS_VOL_LAST
mplVol            sta    >$01C03D
         txa
         ora #$80
         sta >$01C03E           ; wave RAM address >> 8
         lda dMusBase+1
         sta >$01C03D
         txa
         ora #$C0
         sta >$01C03E           ; table size 4 (4K) + resolution 0
         lda #$20
         sta >$01C03D
         inx
                  cpx    #{6}+2
         bcc mplLoop
         lda #$A6               ; control register of oscillator 6
         sta >$01C03E
         lda #$02               ; channel A
         ldx dMusIrqInstalled
         beq mplAStart
         lda #$0A               ; channel A with DOC table-end interrupt
mplAStart
         sta >$01C03D
         lda #$A7
         sta >$01C03E
         lda #$12               ; start, channel B
         sta >$01C03D
         rep #$20
         longa on
         rts

* Copy MUS_CHUNK bytes of the staging buffer into the standby buffer, starting
* at the byte offset already queued (dMusTotal).
musChunk anop
         jsr musStandby
         lda dMusBase
         clc
         adc dMusTotal
         sta dMusAddr
         lda dMusTotal
         clc
         adc #MUS_CHUNK
         sta dMusNew
         sep #$20
         longa off
                  lda    #DOC_VOL+$60           ; wave RAM + auto-increment + main volume
         sta >$01C03C
         lda dMusAddr
         sta >$01C03E
         lda dMusAddr+1
         sta >$01C03F
         ldx dMusTotal
mckLoop  lda dMusStage,x
         sta >$01C03D
         inx
         cpx dMusNew
         bcc mckLoop
                  lda    #DOC_VOL               ; back to the oscillator register file
         sta >$01C03C
         rep #$20
         longa on
         lda dMusNew
         sta dMusTotal
         cmp #MUS_LEN
         bne mckOut
         lda #1
         sta dMusReady
mckOut   rts

* Whole-buffer copy, used once at start ; musChunk advances dMusTotal itself.
* MUS_LEN/MUS_CHUNK = 16 slices of 256 bytes: the loop used to stop after 8
* (1024 B), so the first 4K table was only a quarter filled and the oscillator
* played uninitialised wave RAM for the rest of it -- audible as a full-scale
* 60 ms burst 0.16 s after the music started (fgcheck peak 32767, 974 samples
* over 32000). Merlin32 has no parentheses, so the count is a literal.
musCopyAll anop
                  ldy    #16
mcCopy   phy
         jsr musChunk
         ply
         dey
         bne mcCopy
         rts

* Fill the staging buffer with MUS_LEN bytes ; at end of file close and reopen
* so the track loops forever.  Carry set on failure.
musFillStage anop
         lda dMusCacheState
         cmp #1
         bne mfsDisk
         brl mfsMemory
mfsDisk  lda dMusRef
         beq mfsFail
         sta pbMusRead+2
                  lda    #{4096}
         sta pbMusRead+8
         lda #0
         sta pbMusRead+10
         jsl $E100A8
         dw  $2012
         adrl pbMusRead
         bcc mfsCount
         brl mfsRetry
mfsCount lda pbMusRead+12        ; bytes actually transferred
         sta dMusRead
                  cmp    #{4096}
         bcs mfsOk
mfsRetry jsr musReopen
         bcc mfsAgain
         brl mfsFail
mfsAgain jsl $E100A8
         dw  $2012
         adrl pbMusRead
         bcc mfsAgain2
         brl mfsFail
mfsAgain2
         lda pbMusRead+12
         sta dMusRead
                  cmp    #{4096}
         bcs mfsOk
         brl mfsFail
mfsOk    clc
         rts
mfsFail  sec
         rts

* Cache the complete MUSIC.PCM in a locked Memory Manager handle.  The read
* happens once when music is first enabled; the DOC still uses its two 4K wave
* tables, but refills no longer wait on GS/OS or the disk during play.  A failed
* allocation/read leaves the legacy disk streamer available as a fallback.
musCacheLoad anop
         lda #musNamePtr
         sta pbMusOpen+4
         jsl $E100A8
         dw $2010
         adrl pbMusOpen
         bcc mclOpened
         brl mclFail
mclOpened
         lda pbMusOpen+2
         sta dMusRef
         sta pbMusGetEOF+2
         sta pbMusWholeRead+2
         sta pbMusClose+2
         jsl $E100A8
         dw $2019
         adrl pbMusGetEOF
         bcc mclGotEOF
         brl mclCloseFail
mclGotEOF
         lda pbMusGetEOF+4
         sta dMusFileLen
         lda pbMusGetEOF+6
         sta dMusFileLen+2
         lda dMusFileLen
         ora dMusFileLen+2
         bne mclHaveLen
         brl mclCloseFail
mclHaveLen
* NewHandle(size, app user ID, locked + fixed; allow cross-bank for this large PCM).
         pea $0000
         pea $0000
         lda dMusFileLen+2
         pha
         lda dMusFileLen
         pha
         lda dGfxUserID
         pha
         pea $C000
         pea $0000
         pea $0000
         ldx #$0902
         jsl $E10000
         sta dGfxError
         pla
         sta dMusHandle
         pla
         sta dMusHandle+2
         bcc mclAllocated
         brl mclCloseFail
mclAllocated
         lda dMusHandle
         sta $E0
         lda dMusHandle+2
         sta $E2
         lda [$E0]
         sta pbMusWholeRead+4
         ldy #2
         lda [$E0],y
         sta pbMusWholeRead+6
         sta dMusMemPtr+2
         lda pbMusWholeRead+4
         sta dMusMemPtr
         lda dMusFileLen
         sta pbMusWholeRead+8
         lda dMusFileLen+2
         sta pbMusWholeRead+10
         stz pbMusWholeRead+12
         stz pbMusWholeRead+14
         jsl $E100A8
         dw $2012
         adrl pbMusWholeRead
         bcc mclReadOK
         brl mclDisposeFail
mclReadOK
         lda pbMusWholeRead+12
         cmp dMusFileLen
         beq mclCountLowOK
         brl mclDisposeFail
mclCountLowOK
         lda pbMusWholeRead+14
         cmp dMusFileLen+2
         beq mclCountOK
         brl mclDisposeFail
mclCountOK
         jsr musClose
         lda #1
         sta dMusCacheState
         stz dMusPos
         stz dMusPos+2
         clc
         rts
mclDisposeFail
         jsr musDisposeCache
mclCloseFail
         jsr musClose
mclFail  lda #2
         sta dMusCacheState
         sec
         rts

* Dispose a failed cache allocation so the disk-stream fallback has memory.
musDisposeCache anop
         lda dMusHandle
         ora dMusHandle+2
         beq mdcOut
         lda dMusHandle+2
         pha
         lda dMusHandle
         pha
         ldx #$1002
         jsl $E10000
         stz dMusHandle
         stz dMusHandle+2
mdcOut   rts

* Copy the next 4K table from cached PCM.  File position is a 32-bit offset;
* wrap to the start when fewer than 4K bytes remain, matching the old EOF loop.
mfsMemory
         rep #$20
         longa on
         lda dMusFileLen
         sec
         sbc dMusPos
         sta dMusAvail
         lda dMusFileLen+2
         sbc dMusPos+2
         sta dMusAvail+2
         lda dMusAvail+2
         bne mfmReady
         lda dMusAvail
         cmp #4096
         bcs mfmReady
         stz dMusPos
         stz dMusPos+2
mfmReady lda dMusMemPtr
         clc
         adc dMusPos
         sta $E0
         lda dMusMemPtr+2
         adc dMusPos+2
         sta $E2
         sep #$20
         longa off
         ldx #0
         ldy #0
mfmCopy  lda [$E0],y
         sta dMusStage,x
         inx
         iny
         cpx #4096
         bcc mfmCopy
         rep #$20
         longa on
         lda dMusPos
         clc
         adc #4096
         sta dMusPos
         bcc mfmNoCarry
         inc dMusPos+2
mfmNoCarry
         clc
         rts

musReopen anop
         jsr musClose
musOpen anop
         lda #musNamePtr
         sta pbMusOpen+4
         jsl $E100A8
         dw  $2010
         adrl pbMusOpen
         bcs moFail
         lda pbMusOpen+2
         sta dMusRef
         sta pbMusRead+2
         sta pbMusClose+2
         clc
         rts
moFail   sec
         rts

* Close MUSIC.PCM if it is open (refNum 0 is never a valid GS/OS refNum).
musClose anop
         lda dMusRef
         beq mclOut
         sta pbMusClose+2
         jsl $E100A8
         dw  $2014
         adrl pbMusClose
         stz dMusRef
mclOut   rts

* Halt the two music oscillators and release the file.
musStop anop
         stz dMusState
         stz dMusTotal
         stz dMusChunk
         sep #$20
         longa off
         lda #$A6
         sta >$01C03E
         lda #$01
         sta >$01C03D
         lda #$A7
         sta >$01C03E
         lda #$01
         sta >$01C03D
         rep #$20
         longa on
         jsr musIrqRestore
         jsr musClose
         rts

*-----------------------------------------------------------------------------
* High scores: HISCORE.DAT holds two 16-bit words, Time Trial then Endless.
* loadHiscore runs once at boot (before SHR is on) ; saveHiscore rewrites the
* file whenever a round beats the stored best. The file is shipped by
* `make disk`, so the normal path is Open-with-write ; Create is the fallback for
* an image built without it. Any failure is recorded at $019CF2 for the socket
* harness but never blocks play.
*-----------------------------------------------------------------------------
loadHiscore anop
         jsl $E100A8
         dw  $2010              ; Open (read only)
         adrl pbHiOpen
         bcs lhNone
         lda pbHiOpen+2
         sta pbHiRead+2
         sta pbHiClose+2
         jsl $E100A8
         dw  $2012              ; Read 4 bytes
         adrl pbHiRead
         php
         jsl $E100A8
         dw  $2014              ; Close
         adrl pbHiClose
         plp
         bcs lhNone
         lda dHiBuf
         sta dHiTrial
         lda dHiBuf+2
         sta dHiEndless
lhOut    rts
lhNone   lda #0
         sta dHiTrial
         sta dHiEndless
         bra lhOut

saveHiscore anop
         lda dHiTrial
         sta dHiBuf
         lda dHiEndless
         sta dHiBuf+2
         jsl $E100A8
         dw  $2010              ; Open (GS/OS opens it read/write, see TimePilot)
         adrl pbHiOpen
         bcs shFail
         lda pbHiOpen+2
         sta pbHiWrite+2
         sta pbHiClose+2
         jsl $E100A8
         dw  $2013              ; Write 4 bytes
         adrl pbHiWrite
         php
         jsl $E100A8
         dw  $2014              ; Close
         adrl pbHiClose
         plp
         bcs shFail
         jsr verifyHiscore
         rts
shFail   sta >$019CF2           ; last save error (socket harness reads this)
         rts

* Read the file back inside the same session and compare, so the test harness
* can tell a silent no-op Write from a real save ($019CF6: 1 ok, 2 mismatch,
* 3 Open/Read failed ; $019CF8 = value read back).
verifyHiscore anop
         jsl $E100A8
         dw  $2010
         adrl pbHiOpen
         bcs vhBad
         lda pbHiOpen+2
         sta pbHiRead+2
         sta pbHiClose+2
         jsl $E100A8
         dw  $2012
         adrl pbHiRead
         php
         jsl $E100A8
         dw  $2014
         adrl pbHiClose
         plp
         bcs vhBad
         lda dHiBuf
         sta >$019CF8
         cmp dHiTrial
         bne vhMis
         lda dHiBuf+2
         cmp dHiEndless
         bne vhMis
         lda #1
         sta >$019CF6
         rts
vhMis    lda #2
         sta >$019CF6
         rts
vhBad    lda #3
         sta >$019CF6
         rts

* A new best is announced on the Game Over panel ; equal scores do not count.
* dHiNew is cleared by resetGame so the title/panel never shows a stale record.
checkHiscore anop
         lda #0
         sta dHiNew
         lda dMode
         bne chEndless
         lda dScore
         cmp dHiTrial
         bcc chOut
         beq chOut
         sta dHiTrial
         bra chSave
chEndless lda dScore
         cmp dHiEndless
         bcc chOut
         beq chOut
         sta dHiEndless
chSave   lda #1
         sta dHiNew
         jsr saveHiscore
chOut    rts

* Title screen: "HI <n>" bottom left, outside the amber menu bar (x 60..264).
drawHiLine anop
         lda dHiTrial
         sta dNumVal
         jsr mkNumStr
         lda #1
         sta dTScale
         lda #190
         sta dTextY
         lda #8
         sta dTextX
         lda #1
         ldx #strHi
         jsr drawText
         ldx #dNumBuf            ; mkNumStr already shifted the digits down
         lda #26                ; "HI " = 3 chars at 6 px
         sta dTextX
         lda #190
         sta dTextY
         lda #$000F
         jsr drawText
         rts

* Game Over panel: "BEST n" or "NEW BEST n", centred at x=200, scale 1, y=117.
drawBestLine anop
         lda dMode
         bne dbEndless
         lda dHiTrial
         bra dbHave
dbEndless lda dHiEndless
dbHave   sta dNumVal
         jsr mkNumStr
         lda dHiNew
         beq dbPlain
         ldx #strNewBest
         bra dbStr
dbPlain  ldx #strBest
dbStr    stx dBestPtr
         ldx dBestPtr
         jsr strLen
         sta dBestLen
         lda dNumLen
         clc
         adc dBestLen
         asl a
         sta dTmpW
         asl a
         asl a
         sec
         sbc dTmpW              ; total characters * 6 = pixel width
         lsr a                  ; half width
         sta dTmpW
         lda #200
         sec
         sbc dTmpW
         sta dTextX
         lda #1
         sta dTScale
         lda #117
         sta dTextY
         lda #1
         ldx dBestPtr
         jsr drawText            ; leaves dTextX just past the prefix
         lda #117
         sta dTextY
         ldx #dNumBuf
         lda #1
         jsr drawText
         rts

* 384 bytes of RGB444 palette words, one copy loop per screen set. The source
* is addressed with long,X (`>`), so GS/OS relocates all three bytes and no
* data-bank-director or self-patching trick is involved.
installTitlePal anop
         ldx #0
itpLp    lda >titlepals,x
                  sta    >PALBASE,x
         inx
         inx
         cpx #384
         bne itpLp
         rts

installTitleScb anop
         sep #$20
         longa off
         ldx #0
itscLp   lda titleScb,x
         sta >SCB,x
         inx
         cpx #200
         bne itscLp
         rep #$20
         longa on
         rts

installHowtoScb anop
         sep #$20
         longa off
         ldx #0
ihscLp   lda howtoScb,x
         sta >SCB,x
         inx
         cpx #200
         bne ihscLp
         rep #$20
         longa on
         rts

installOptionsScb anop
         sep #$20
         longa off
         ldx #0
ioscLp   lda optionsScb,x
         sta >SCB,x
         inx
         cpx #200
         bne ioscLp
         rep #$20
         longa on
         rts

installHowtoPal anop
         ldx #0
ihpLp    lda >howtopals,x
                  sta    >PALBASE,x
         inx
         inx
         cpx #384
         bne ihpLp
         rts

installOptionsPal anop
         ldx #0
iopLp    lda >optionspals,x
         sta >PALBASE,x
         inx
         inx
         cpx #384
         bne iopLp
         rts

installGamePal anop
         ldx #0
igpLp    lda >gempals,x
                  sta    >PALBASE,x
         inx
         inx
         cpx #512
         bne igpLp
         rts

installScb anop
         sep #$20
         longa off
         ldx #0
iscLp    lda scbtab,x
                  sta    >SCB,x
         inx
         cpx #200
         bne iscLp
         rep #$20
         longa on
         rts

installGameScb anop
         sep #$20
         longa off
         ldx #0
igscLoop lda gameScb,x
         sta >SCB,x
         inx
         cpx #200
         bne igscLoop
         rep #$20
         longa on
         rts

saveGameBoard anop
         ldx #2288              ; 14*160 + 96/2
         ldy #0
         lda #176
         sta dSaveRows
sgbRow
         lda >SCREEN+0,x
         sta dTitleSave+0,y
         lda >SCREEN+2,x
         sta dTitleSave+2,y
         lda >SCREEN+4,x
         sta dTitleSave+4,y
         lda >SCREEN+6,x
         sta dTitleSave+6,y
         lda >SCREEN+8,x
         sta dTitleSave+8,y
         lda >SCREEN+10,x
         sta dTitleSave+10,y
         lda >SCREEN+12,x
         sta dTitleSave+12,y
         lda >SCREEN+14,x
         sta dTitleSave+14,y
         lda >SCREEN+16,x
         sta dTitleSave+16,y
         lda >SCREEN+18,x
         sta dTitleSave+18,y
         lda >SCREEN+20,x
         sta dTitleSave+20,y
         lda >SCREEN+22,x
         sta dTitleSave+22,y
         lda >SCREEN+24,x
         sta dTitleSave+24,y
         lda >SCREEN+26,x
         sta dTitleSave+26,y
         lda >SCREEN+28,x
         sta dTitleSave+28,y
         lda >SCREEN+30,x
         sta dTitleSave+30,y
         lda >SCREEN+32,x
         sta dTitleSave+32,y
         lda >SCREEN+34,x
         sta dTitleSave+34,y
         lda >SCREEN+36,x
         sta dTitleSave+36,y
         lda >SCREEN+38,x
         sta dTitleSave+38,y
         lda >SCREEN+40,x
         sta dTitleSave+40,y
         lda >SCREEN+42,x
         sta dTitleSave+42,y
         lda >SCREEN+44,x
         sta dTitleSave+44,y
         lda >SCREEN+46,x
         sta dTitleSave+46,y
         lda >SCREEN+48,x
         sta dTitleSave+48,y
         lda >SCREEN+50,x
         sta dTitleSave+50,y
         lda >SCREEN+52,x
         sta dTitleSave+52,y
         lda >SCREEN+54,x
         sta dTitleSave+54,y
         lda >SCREEN+56,x
         sta dTitleSave+56,y
         lda >SCREEN+58,x
         sta dTitleSave+58,y
         lda >SCREEN+60,x
         sta dTitleSave+60,y
         lda >SCREEN+62,x
         sta dTitleSave+62,y
         lda >SCREEN+64,x
         sta dTitleSave+64,y
         lda >SCREEN+66,x
         sta dTitleSave+66,y
         lda >SCREEN+68,x
         sta dTitleSave+68,y
         lda >SCREEN+70,x
         sta dTitleSave+70,y
         lda >SCREEN+72,x
         sta dTitleSave+72,y
         lda >SCREEN+74,x
         sta dTitleSave+74,y
         lda >SCREEN+76,x
         sta dTitleSave+76,y
         lda >SCREEN+78,x
         sta dTitleSave+78,y
         lda >SCREEN+80,x
         sta dTitleSave+80,y
         lda >SCREEN+82,x
         sta dTitleSave+82,y
         lda >SCREEN+84,x
         sta dTitleSave+84,y
         lda >SCREEN+86,x
         sta dTitleSave+86,y
         lda >SCREEN+88,x
         sta dTitleSave+88,y
         lda >SCREEN+90,x
         sta dTitleSave+90,y
         lda >SCREEN+92,x
         sta dTitleSave+92,y
         lda >SCREEN+94,x
         sta dTitleSave+94,y
         lda >SCREEN+96,x
         sta dTitleSave+96,y
         lda >SCREEN+98,x
         sta dTitleSave+98,y
         lda >SCREEN+100,x
         sta dTitleSave+100,y
         lda >SCREEN+102,x
         sta dTitleSave+102,y
         jsr cacheNextRow
         dec dSaveRows
         beq sgbDone
         brl sgbRow
sgbDone  lda dGfxBank
         beq sgbOut
         phb
         sep #$20
         longa off
         lda dGfxBank
         sta cacheMove+1
         phk
         pla
         sta cacheMove+2
         rep #$20
         longa on
         ldx #dTitleSave
         ldy #$B400
         lda #18303
cacheMove db $54,$00,$00          ; MVN destination bank, source bank
         plb
sgbOut   rts

restoreGameBoard anop
         ldx #2288
         ldy #0
         lda #176
         sta dSaveRows
rgbRow
         lda dTitleSave+0,y
         sta >SCREEN+0,x
         lda dTitleSave+2,y
         sta >SCREEN+2,x
         lda dTitleSave+4,y
         sta >SCREEN+4,x
         lda dTitleSave+6,y
         sta >SCREEN+6,x
         lda dTitleSave+8,y
         sta >SCREEN+8,x
         lda dTitleSave+10,y
         sta >SCREEN+10,x
         lda dTitleSave+12,y
         sta >SCREEN+12,x
         lda dTitleSave+14,y
         sta >SCREEN+14,x
         lda dTitleSave+16,y
         sta >SCREEN+16,x
         lda dTitleSave+18,y
         sta >SCREEN+18,x
         lda dTitleSave+20,y
         sta >SCREEN+20,x
         lda dTitleSave+22,y
         sta >SCREEN+22,x
         lda dTitleSave+24,y
         sta >SCREEN+24,x
         lda dTitleSave+26,y
         sta >SCREEN+26,x
         lda dTitleSave+28,y
         sta >SCREEN+28,x
         lda dTitleSave+30,y
         sta >SCREEN+30,x
         lda dTitleSave+32,y
         sta >SCREEN+32,x
         lda dTitleSave+34,y
         sta >SCREEN+34,x
         lda dTitleSave+36,y
         sta >SCREEN+36,x
         lda dTitleSave+38,y
         sta >SCREEN+38,x
         lda dTitleSave+40,y
         sta >SCREEN+40,x
         lda dTitleSave+42,y
         sta >SCREEN+42,x
         lda dTitleSave+44,y
         sta >SCREEN+44,x
         lda dTitleSave+46,y
         sta >SCREEN+46,x
         lda dTitleSave+48,y
         sta >SCREEN+48,x
         lda dTitleSave+50,y
         sta >SCREEN+50,x
         lda dTitleSave+52,y
         sta >SCREEN+52,x
         lda dTitleSave+54,y
         sta >SCREEN+54,x
         lda dTitleSave+56,y
         sta >SCREEN+56,x
         lda dTitleSave+58,y
         sta >SCREEN+58,x
         lda dTitleSave+60,y
         sta >SCREEN+60,x
         lda dTitleSave+62,y
         sta >SCREEN+62,x
         lda dTitleSave+64,y
         sta >SCREEN+64,x
         lda dTitleSave+66,y
         sta >SCREEN+66,x
         lda dTitleSave+68,y
         sta >SCREEN+68,x
         lda dTitleSave+70,y
         sta >SCREEN+70,x
         lda dTitleSave+72,y
         sta >SCREEN+72,x
         lda dTitleSave+74,y
         sta >SCREEN+74,x
         lda dTitleSave+76,y
         sta >SCREEN+76,x
         lda dTitleSave+78,y
         sta >SCREEN+78,x
         lda dTitleSave+80,y
         sta >SCREEN+80,x
         lda dTitleSave+82,y
         sta >SCREEN+82,x
         lda dTitleSave+84,y
         sta >SCREEN+84,x
         lda dTitleSave+86,y
         sta >SCREEN+86,x
         lda dTitleSave+88,y
         sta >SCREEN+88,x
         lda dTitleSave+90,y
         sta >SCREEN+90,x
         lda dTitleSave+92,y
         sta >SCREEN+92,x
         lda dTitleSave+94,y
         sta >SCREEN+94,x
         lda dTitleSave+96,y
         sta >SCREEN+96,x
         lda dTitleSave+98,y
         sta >SCREEN+98,x
         lda dTitleSave+100,y
         sta >SCREEN+100,x
         lda dTitleSave+102,y
         sta >SCREEN+102,x
         jsr cacheNextRow
         dec dSaveRows
         beq rgbDone
         brl rgbRow
rgbDone  rts

cacheNextRow anop
         txa
         clc
         adc #160
         tax
         tya
         clc
         adc #104
         tay
         jsr musYield
         rts

* GS/OS hands the desktop palette and scanline table back to the Finder by
* itself only if the application restores them ; without this the desktop is
* redrawn in the last game palette (seen as a black screen with a stray icon).
saveScreenSet anop
         ldx #0
sssPal            lda    >PALBASE,x
         sta >dSavePal,x
         inx
         inx
         cpx #512
         bne sssPal
         ldx #0
sssScb            lda    >SCB,x
         sta >dSaveScb,x
         inx
         inx
         cpx #200
         bne sssScb
         rts

restoreScreenSet anop
         ldx #0
rssPal   lda >dSavePal,x
                  sta    >PALBASE,x
         inx
         inx
         cpx #512
         bne rssPal
         ldx #0
rssScb   lda >dSaveScb,x
                  sta    >SCB,x
         inx
         inx
         cpx #200
         bne rssScb
         rts

shrOn anop
         sep #$20
         longa off
         lda #$E1
                  sta    >NEWVIDEO
         rep #$20
         longa on
         rts

* Menu art + menu. Re-streaming the art is how the previous highlight bar is
* erased (a GS/OS read of 32000 bytes takes a few frames).
* Title animation has its own composed background (menu included) in the
* unused tail of the last locked sprite-code bank. The pristine menu cache
* remains in dTitleSave for hover/Options band restoration.
saveTitleComposite anop
         lda dGfxFastBanks+4
         bne stcReady
         rts
stcReady sep #$20
         longa off
         sta titleCompositeMove+1
         rep #$20
         longa on
         ldx #22302             ; SCREEN low word $2000 + 14110
         ldy #$B400
         lda #112
         sta dTitleRows
stcRow   phb
         lda #101
titleCompositeMove db $54,$00,$01
         plb
         txa
         clc
         adc #58
         tax
         jsr musYield
         dec dTitleRows
         bne stcRow
         rts

titleEraseGem anop
         lda dTitleOldY
         cmp #88
         bcs tegTop
         rts
tegTop   cmp #200
         bcc tegVisible
         rts
tegVisible lda #200
         sec
         sbc dTitleOldY
         cmp #20
         bcc tegCount
         lda #20
tegCount sta dTitleRows
         lda dTitleOldY
         asl a
         tax
         lda titleCacheRows,x
         clc
         adc dGemX
         sec
         sbc #30
         tay
         lda screenRows,x
         clc
         adc dGemX
         tax
         lda dGfxFastBanks+4
         phb
         sep #$20
         longa off
         pha
         plb
         rep #$20
         longa on
tegRow   lda $B400,y
         sta >SCREEN,x
         lda $B402,y
         sta >SCREEN+2,x
         lda $B404,y
         sta >SCREEN+4,x
         lda $B406,y
         sta >SCREEN+6,x
         lda $B408,y
         sta >SCREEN+8,x
         lda $B40A,y
         sta >SCREEN+10,x
         txa
         clc
         adc #160
         tax
         tya
         clc
         adc #102
         tay
         lda >dTitleRows
         dec a
         sta >dTitleRows
         bne tegRow
         plb
         rts

drawTitleGem anop
         lda dGemY
         cmp #200
         bcc dtgVisible
         rts
dtgVisible lda dGem
         dec a
         asl a
         tax
         lda titleGemOff,x
         sta dTitleTileRow
         lda #20
         sta dTitleRows
         lda dGfxBank
         bne dtgBank
         rts
dtgBank  phb
         sep #$20
         longa off
         pha
         plb
         rep #$20
         longa on
dtgRow   lda >dGemY
         cmp #200
         bcs dtgDone
         asl a
         tax
         lda >screenRows,x
         clc
         adc >dGemX
         tax
         lda >dTitleTileRow
         tay
         lda gemtiles,y
         sta >titleGemCall+1
titleGemCall jsl $000000
         lda >dTitleTileRow
         clc
         adc #2
         sta >dTitleTileRow
         lda >dGemY
         inc a
         sta >dGemY
         lda >dTitleRows
         dec a
         sta >dTitleRows
         bne dtgRow
dtgDone  plb
         rts

titleGemsStill anop
         stz dTitleIndex
tgsGem   ldx dTitleIndex
         lda titleXTab,x
         sta dGemX
         txa
         lsr a
         inc a
         sta dGem
         lda #88
         sta dGemY
         jsr drawTitleGem
         jsr musYield
         inc dTitleIndex
         inc dTitleIndex
         lda dTitleIndex
         cmp #14
         bcc tgsGem
         rts

titleIntro anop
         jsr pointerHide
         jsr saveTitleComposite
         ldx #0
tiInit   lda #200
         sta dTitlePY,x
         stz dTitleDone,x
         inx
         inx
         cpx #14
         bcc tiInit
         jsr clockRead
         sta dMotionStartTick
         stz dMotionFrames
         lda #60
         sta dMotionDuration
tiFrame  jsr clockRead
         sta dTitleFrameTick
         sec
         sbc dMotionStartTick
         sta dTitleElapsed
         stz dTitleIndex
tiGem    ldx dTitleIndex
         lda dTitleDone,x
         bne tiNext
         txa
         lsr a
         sta dTitleDelay
         asl a
         asl a
         clc
         adc dTitleDelay
         sta dTitleDelay
         lda dTitleElapsed
         sec
         sbc dTitleDelay
         bcc tiNext
         cmp #30
         bcc tiMoving
         lda #1
         sta dTitleDone,x
         lda #30
tiMoving asl a
         tax
         lda titleRiseY,x
         sta dTitleNewY
         ldx dTitleIndex
         cmp dTitlePY,x
         beq tiNext
         lda dTitlePY,x
         sta dTitleOldY
         lda dTitleNewY
         sta dTitlePY,x
         lda titleXTab,x
         sta dGemX
         jsr titleEraseGem
         lda dTitleIndex
         lsr a
         inc a
         sta dGem
         lda dTitleNewY
         sta dGemY
         jsr drawTitleGem
         jsr musYield
tiNext   inc dTitleIndex
         inc dTitleIndex
         lda dTitleIndex
         cmp #14
         bcs tiFrameDone
         brl tiGem
tiFrameDone inc dMotionFrames
         lda dTitleElapsed
         cmp #98
         bcs tiDone
tiWait   jsr musStep
         jsr clockRead
         sec
         sbc dTitleFrameTick
         cmp #2
         bcc tiWait
         brl tiFrame
tiDone   jsr clockRead
         sta dMotionEndTick
         rts

showTitleScreen anop
         jsr pointerHide        ; restore the old scene's pixels before loading Title
         lda #nmTitle
         sta dPathPtr
         jsr loadScene
         jsr installTitlePal
         jsr installTitleScb
         jsr saveTitleMenu
         jsr titleDraw
         jsr shrOn
         jsr titleIntro
         rts
*-----------------------------------------------------------------------------
* The title menu is redrawn on every arrow/hover move.  Reading TITLE.RAW from
* disk each time made the cursor feel sluggish, so the 112x102-byte menu band is
* saved once and copied back to the screen before titleDraw repaints it.
*-----------------------------------------------------------------------------
TITLE_SAVE_OFF   equ 7390        ; y46 * 160 + byte x30
TITLE_SAVE_ROWS  equ 154
TITLE_SAVE_BYTES equ 102

saveTitleMenu anop
         rep #$20
         longa on
                  ldx    #{7390}
         ldy #0
                  lda    #{154}
         sta dReadRow
         longa on
svRow    lda #51
         sta dColCnt
svWord            lda    >SCREEN,x
         sta dTitleSave,y
         inx
         inx
         iny
         iny
         dec dColCnt
         bne svWord
         txa
         clc
         adc #58
         tax
         jsr musYield            ; 11 KB background copy spans several DOC slices
         dec dReadRow
         bne svRow
         rts

titleRedrawMenu anop
         rep #$20
         longa on
         lda dMenuPrev
         cmp dMenuSel
         bne trmGo
         rts                    ; nothing moved: leave the screen alone
trmGo    inc dTrN
         jsr pointerHide        ; the cached menu band may overlap the software cursor
         lda #1
         sta dTScale
         lda dMenuPrev
         jsr titleRestoreBand   ; pristine art back over the old bar+label
         lda dMenuPrev
         sta dMenuIdx
         jsr titleLabel         ; old label, now white on the art
         jsr titleBar           ; amber bar under the new selection
         lda dMenuSel
         sta dMenuIdx
         jsr titleLabel
         lda dMenuSel
         sta dMenuPrev
         rts

* Title rows restore 11 scanlines; Options restores 22 through dBandRows.
* The pristine cache starts at y46, x60 and stores 102 bytes per scanline.
TITLE_BAND_ROWS equ 11

* A = menu index. Resolve the first scanline, then restore its cached band.
titleRestoreBand anop
          pha
          lda #11
          sta dBandRows
          pla
          rep #$20
          longa on
          asl a
          tax
          lda menuYTab,x
          sec
          sbc #2
          sta dRowY
bandRestoreY anop
          inc dTrB
          lda dRowY
          sec
          sbc #46
          sta dTmpA              ; (y - 46)
          asl a
          asl a                  ; 4x
          sta dTmpW
          lda dTmpA
          asl a
          asl a
          asl a
          asl a
          asl a                  ; 32x
          clc
          adc dTmpW              ; 36x
          sta dTmpW
          lda dTmpA
          asl a
          asl a
          asl a
          asl a
          asl a
          asl a                  ; 64x
          clc
          adc dTmpW              ; 100x
          clc
          adc dTmpA
          adc dTmpA              ; 102x
          sta dSaveOff
          sta dTmpW              ; keep the save offset for Y
          lda dRowY
          sta dTmpA
          asl a
          asl a
          asl a
          asl a
          asl a                  ; 32y
          sta dRowY
          lda dTmpA
          asl a
          asl a
          asl a
          asl a
          asl a
          asl a
          asl a                  ; 128y
          clc
          adc dRowY              ; 160y
          clc
          adc #30                ; x = 60 px -> byte 30, the same window dTitleSave holds
          tax                    ; SCREEN byte offset
          ldy dTmpW              ; dTitleSave offset
          lda dBandRows
          sta dRowCnt
trBandRow lda #51
          sta dColCnt
trBandW  lda dTitleSave,y
          sta >SCREEN,x
          inx
          inx
          iny
          iny
          dec dColCnt
          bne trBandW
          txa
          clc
          adc #58                ; next scanline, same x window
          tax
          dec dRowCnt
          bne trBandRow
          rts

showHowto anop
         jsr pointerHide        ; never carry cursor-underlay bytes across a scene load
         lda #nmHowto
         sta dPathPtr
         jsr loadScene
         jsr installHowtoPal
         jsr installHowtoScb
         jsr howtoDraw
         jsr shrOn
         rts

* Time Trial streams SCENE4.RAW ; Endless streams SCENE4E.RAW, whose art has no
* "Time left" header or panel.
startGame anop
         jsr pointerHide        ; restore menu pixels before replacing the full screen
         lda dMode
         beq sgTimeTrial
         lda #nmSceneE
         bra sgLoad
sgTimeTrial
                  lda    #{scenePath}
sgLoad   sta dPathPtr
         jsr loadScene
         jsr saveGameBoard
         jsr installGamePal
         jsr installGameScb
         jsr shrOn
         jsr resetGame
         lda #1
         sta dState
         rts

* A = length of the NUL-terminated string at X (bounded by the NUL only).
strLen anop
         stx dTextBase
         lda dTextBase
         sta slOp+1
         lda #0
         sta dLen
slLp     ldy dLen
         sep #$20
         longa off
slOp     lda $0000,y           ; patched string base
         rep #$20
         longa on
         and #$00FF
         beq slDone
         inc dLen
         bra slLp
slDone   lda dLen
         rts

* Menu: amber bar behind the selected item, white labels centred at scale 1
* (width 6*len-1, so x = 161-3*len). fillRect needs an even x0 and a width
* divisible by 4: 98..222 is 31 words.
titleDraw anop
         lda #1
         sta dTScale
         jsr titleBar
         lda #0
         sta dMenuIdx
tdLoop   jsr titleLabel
         inc dMenuIdx
         lda dMenuIdx
                  cmp    #{5}
         bne tdLoop
         lda dMenuSel
         sta dMenuPrev
         rts

* Amber bar behind the selected item: rows menuYTab-2 .. menuYTab+9, x=98..222.
titleBar anop
         lda dMenuSel
         asl a
         tax
         lda menuYTab,x
         sec
         sbc #2
         sta dFillY0
         lda dMenuSel
         asl a
         tax
         lda menuYTab,x
         clc
         adc #9
         sta dFillY1
         lda #98
         sta dFillX
         lda #222
         sta dFillX1
         lda #$2222             ; amber in every title palette (slot 2)
         sta dFillWord
         lda dFillY0
         sta dTrY0
         lda dFillY1
         sta dTrY1
         lda dMusTick16
         sta dTrTick
         jsr fillRect
         rts

* Centred white label for the item in dMenuIdx, scale from dTScale (1).
titleLabel anop
         lda dMenuIdx
         asl a
         tax
         lda menuStrTab,x
         tax
         jsr strLen
         sta dNumTmp
         sta dTmpW
         asl a
         clc
         adc dTmpW              ; 3*len at scale 1
         sta dMenuX
         lda #161
         sec
         sbc dMenuX
         sta dTextX
         lda dMenuIdx
         asl a
         tax
         lda menuYTab,x
         sta dTextY
         lda dMenuIdx
         asl a
         tax
         lda menuStrTab,x
         tax
         lda #1
         jsr drawText
         rts

* How to play: title at the top right, wrapped body copy at x=124, and the
* original "Press any button to go back" hint at the bottom left.
howtoDraw anop
         lda #2
         sta dTScale
         lda #156
         sta dTextX
         lda #17
         sta dTextY
         lda #1
         ldx #strHtTitle
         jsr drawText
         lda #1
         sta dTScale
         lda #0
         sta dLineIdx
hdLoop   lda dLineIdx
         asl a
         tax
         lda htYTab,x
         sta dTextY
         lda #124
         sta dTextX
         lda dLineIdx
         asl a
         tax
         lda htStrTab,x
         tax
         lda #1
         jsr drawText
         inc dLineIdx
         lda dLineIdx
                  cmp    #{14}
         bne hdLoop
         lda #1
         sta dTScale
         lda #12
         sta dTextX
         lda #185
         sta dTextY
         lda #1
         ldx #strHtBack
         jsr drawText
         rts

*-----------------------------------------------------------------------------
* State handlers. The title accepts W/S (wrap), Space/Return and ESC ; the
* how-to-play screen returns to the menu on any key.
*-----------------------------------------------------------------------------
toTitle
         rep #$20
         longa on
         stz dClockActive
         stz dTimedOut
         stz dTimeDirty
         lda #$FFFF
         sta dDragCell
         lda #0
         sta dState
         sta dMenuSel
         jsr showTitleScreen
         brl gameExit

stateTitle
         sep #$20
         longa off
                  lda    >KBD
         bmi titleKeyDown
         rep #$20
         longa on
         lda dMouseClick
         bne stmHit
         lda dMouseMoved
         bne stmHit
         brl gameExit
stmHit   brl titleMouse
titleKeyDown
         sep #$20
         longa off
                  sta    >KBDSTRB
         and #$7F
         cmp #$1B                ; ESC quits the program from the menu
         bne tkNotEsc
         brl quitGame
tkNotEsc cmp #$20
         beq tkChoose
         cmp #$0D                ; Return
         beq tkChoose
         cmp #$0B                ; Apple IIgs cursor up
         beq tkUp
         cmp #$0A                ; Apple IIgs cursor down
         beq tkDown
         and #$DF
         cmp #'W'
         beq tkUp
         cmp #'S'
         beq tkDown
         rep #$20
         longa on
         brl gameExit
tkUp     rep #$20
         longa on
         lda dMenuSel
         bne tkUpDec
                  lda    #{5}
         dec a
         sta dMenuSel
         bra tkRedraw
tkUpDec  dec dMenuSel
         bra tkRedraw
tkDown   rep #$20
         longa on
         lda dMenuSel
         inc a
                  cmp    #{5}
         bcc tkDnOk
         lda #0
         sta dMenuSel
         bra tkRedraw
tkDnOk   sta dMenuSel
tkRedraw jsr titleRedrawMenu
         brl gameExit
tkChoose rep #$20
         longa on
         lda dMenuSel
         cmp #2
         beq tkHowto
         cmp #3
         beq tkOptions
         cmp #4
         beq tkQuit
         sta dMode              ; 0 = Time Trial, 1 = Endless
         jsr startGame
         brl gameExit
tkHowto  rep #$20
         longa on
         lda #2
         sta dState
         jsr showHowto
         brl gameExit
tkQuit   brl quitGame
tkOptions rep #$20
         longa on
         lda #3
         sta dState
         jsr showOptions
         brl gameExit

stateHowto
         sep #$20
         longa off
                  lda    >KBD
         bmi htKeyDown
         rep #$20
         longa on
         lda dMouseClick        ; a click behaves like "any key"
         bne htClick
         brl gameExit
htClick  stz dMouseClick
         lda #0
         sta dState
         jsr showTitleScreen
         brl gameExit
htKeyDown
         sep #$20
         longa off
                  sta    >KBDSTRB
         and #$7F
         cmp #$1B
         bne htBack
         brl quitGame
htBack   rep #$20
         longa on
         lda #0
         sta dState
         jsr showTitleScreen
         brl gameExit

*-----------------------------------------------------------------------------
* Options follows VERA: Music/Sound values, fixed Fullscreen: On, Back,
* then the two per-mode high-score rows.
showOptions anop
         jsr pointerHide        ; restore the old scene before loading Options
         lda #nmOptions
         sta dPathPtr
         jsr loadScene
         jsr installOptionsPal
         jsr installOptionsScb
         jsr saveTitleMenu
         jsr optionsDrawAll
         jsr shrOn
         rts

* Restore just the previous compact selection band, then draw the new row.
optionsDraw anop
         jsr pointerHide        ; restore any pointer under the row being redrawn
         rep #$20
         longa on
         lda #1
         sta dTScale
         lda dOptPrev
         cmp #$FFFF
         beq odNoPrev
         jsr optBandA
         lda dOptPrev
         jsr optLabelA
odNoPrev lda dOptSel
         jsr optBarA
         lda dOptSel
         jsr optLabelA
         lda dOptSel
         sta dOptPrev
         rts

drawOptionsScores anop
         lda dHiTrial
         sta dNumVal
         jsr mkNumStr
         lda dNumLen
         sta dHiWidth
         lda dHiEndless
         sta dNumVal
         jsr mkNumStr
         lda dNumLen
         cmp dHiWidth
         bcc dosWidthReady
         sta dHiWidth
dosWidthReady
         lda #1
         sta dTScale
         lda #130
         sta dTextX
         lda #126
         sta dTextY
         ldx #strHighScore
         lda #1
         jsr drawText
         stz dHiRow
dosRow   lda dHiRow
         beq dosTrial
         lda dHiEndless
         bra dosHave
dosTrial lda dHiTrial
dosHave  sta dNumVal
         jsr mkNumStr
         lda dNumLen
         sta dHiCount
         lda dHiWidth
         clc
         adc #11
         asl a
         sta dHiTmp
         asl a
         clc
         adc dHiTmp
         sec
         sbc #1
         sta dHiTmp
         lda #320
         sec
         sbc dHiTmp
         lsr a
         sta dHiX
         lda dHiRow
         beq dosLabelTrial
         ldx #strEndlessScore
         bra dosLabel
dosLabelTrial ldx #strTimeTrialScore
dosLabel stx dTextBase
         lda dHiX
         sta dTextX
         lda dHiRow
         asl a
         clc
         adc dHiRow
         asl a
         asl a
         clc
         adc #143
         sta dTextY
         ldx dTextBase
         lda #1
         jsr drawText
         lda dHiWidth
         sec
         sbc dHiCount
         sta dHiTmp2
         asl a
         sta dHiTmp
         asl a
         clc
         adc dHiTmp
         clc
         adc #66
         clc
         adc dHiX
         sta dTextX
         lda dHiRow
         asl a
         clc
         adc dHiRow
         asl a
         asl a
         clc
         adc #143
         sta dTextY
         ldx #dNumBuf
         lda #1
         jsr drawText
         inc dHiRow
         lda dHiRow
         cmp #2
         bcs dosDone
         brl dosRow
dosDone  rts

optionsDrawAll anop
         rep #$20
         longa on
         lda #1
         sta dTScale
         lda dOptSel
         jsr optBarA
         lda #0
         jsr optLabelA
         lda #1
         jsr optLabelA
         lda #2
         jsr optLabelA
         lda #3
         jsr optLabelA
         jsr drawOptionsScores
         lda #34
         sta dTextX
         lda #190
         sta dTextY
         ldx #strPortCredit
         lda #1
         jsr drawText
         lda dOptSel
         sta dOptPrev
         rts

optBandA anop
         pha
         lda #16
         sta dBandRows
         pla
         asl a
         tax
         lda optYTab,x
         dec a
         sta dRowY
         jsr bandRestoreY
         rts

optBarA anop
         asl a
         tax
         lda optYTab,x
         dec a
         sta dFillY0
         lda optYTab,x
         clc
         adc #15
         sta dFillY1
         lda #70
         sta dFillX
         lda #250
         sta dFillX1
         lda #$2222
         sta dFillWord
         jsr fillRect
         rts

optLabelA anop
         sta dTmpA
         sta dOptIdx
         lda #2
         sta dTScale
         lda dTmpA
         asl a
         tax
         lda optYTab,x
         sta dTextY
         lda dTmpA
         beq olMusic
         cmp #1
         beq olSound
         cmp #2
         beq olFullscreen
         ldx #strBack
         bra olDraw
olMusic  ldx #strMusicLabel
         jsr drawOptionLabel
         lda dMusOn
         beq olMusicOff
         ldx #strOn
         bra olValue
olMusicOff ldx #strOff
         bra olValue
olSound  ldx #strSoundLabel
         jsr drawOptionLabel
         lda dSoundOn
         beq olSoundOff
         ldx #strOn
         bra olValue
olSoundOff ldx #strOff
         bra olValue
olFullscreen ldx #strFullscreen
         bra olDraw
olValue  stx dTmpW
         lda #188
         sta dTextX
         lda dOptIdx
         asl a
         tax
         lda optYTab,x
         sta dTextY
         ldx dTmpW
         lda #1
         jsr drawText
         rts
olDraw   jsr centerLabel
         rts

drawOptionLabel anop
         stx dTmpW
         lda dOptIdx
         asl a
         tax
         lda optYTab,x
         sta dTextY
         lda #106
         sta dTextX
         ldx dTmpW
         lda #1
         jsr drawText
         lda dOptIdx
         asl a
         tax
         lda optYTab,x
         sta dTextY
         rts

centerLabel anop
         stx dTmpW
         jsr strLen
         sta dNumTmp
         asl a
         clc
         adc dNumTmp
         asl a
         sta dOptX
         lda #160
         sec
         sbc dOptX
         sta dTextX
         ldx dTmpW
         lda #1
         jsr drawText
         rts

stateOptions
         sep #$20
         longa off
                  lda    >KBD
         bmi soKeyDown
         rep #$20
         longa on
         lda dMouseClick
         ora dMouseMoved
         beq soOut
* Hover and click share the same visible 16-row hitboxes. Ignore the gaps and
* the background, and do not override keyboard selection while the mouse rests.
         lda dMouseX
         cmp #70
         bcc soOut
         cmp #250
         bcs soOut
         ldx #0
soHitRow lda dMouseY
         sec
         sbc optYTab,x
         clc
         adc #1
         cmp #16
         bcc soMouseHit
         inx
         inx
         cpx #8
         bcc soHitRow
         bra soOut
soMouseHit
         txa
         lsr a
         cmp dOptSel
         beq soMouseChoose
         sta dOptSel
         jsr optionsDraw
soMouseChoose
         lda dMouseClick
         beq soOut
         stz dMouseClick
         lda dOptSel
         cmp #3
         bcc soMouseToggle
         brl soBack
soMouseToggle
         jsr optToggle
         brl gameExit
soOut    brl gameExit
soKeyDown
         sep #$20
         longa off
                  sta    >KBDSTRB
         and #$7F
         cmp #$1B                ; ESC leaves Options back to the title
         beq soBack
         cmp #$20
         beq soChoose
         cmp #$0D
         beq soChoose
         cmp #$0B
         beq soUp
         cmp #$0A
         beq soDown
         and #$DF
         cmp #'W'
         beq soUp
         cmp #'S'
         beq soDown
         rep #$20
         longa on
         brl gameExit
soUp     rep #$20
         longa on
         lda dOptSel
         bne soUpDec
                  lda    #{4}
         dec a
         sta dOptSel
         bra soRedraw
soUpDec  dec dOptSel
         bra soRedraw
soDown   rep #$20
         longa on
         lda dOptSel
         inc a
                  cmp    #{4}
         bcc soDnOk
         lda #0
         sta dOptSel
         bra soRedraw
soDnOk   sta dOptSel
soRedraw jsr optionsDraw
         brl gameExit
soChoose rep #$20
         longa on
         lda dOptSel
         cmp #3
         bcs soBack
         jsr optToggle
         brl gameExit
soBack   rep #$20
         longa on
         lda #0
         sta dState
         sta dOptSel
         lda #$FFFF
         sta dOptPrev
         jsr showTitleScreen
         brl gameExit
* dOptSel decides which row is toggled: 0 = Music, 1 = Sound, 2 = Back (the
* caller handles Back itself).
optToggle anop
         lda dOptSel
         cmp #1
         bcs otSoundOrBack
         lda dMusOn
         eor #1
         sta dMusOn
         beq otMusOff
         jsr musStart           ; resuming restarts the track from the top
         bra otDone
otMusOff jsr musStop
         bra otDone
otSoundOrBack
         cmp #2
         bcs otDone             ; Fullscreen is fixed ON
         lda dSoundOn
         eor #1
         sta dSoundOn
         bne otDone
         jsr audioStop          ; muting must silence what is playing now
otDone   jsr optionsDraw
         rts


*-----------------------------------------------------------------------------
* Menu labels and the how-to-play copy (NUL-terminated, 5x7 font cells).
*-----------------------------------------------------------------------------
strMTrial
         db $54,$69,$6D,$65,$74,$72,$69,$61
         db $6C,$20,$6D,$6F,$64,$65
         db $00
strMEndless
         db $45,$6E,$64,$6C,$65,$73,$73,$20
         db $6D,$6F,$64,$65
         db $00
strMHowto
         db $48,$6F,$77,$20,$74,$6F,$20,$70
         db $6C,$61,$79,$3F
         db $00
strMExit
         db $45,$78,$69,$74
         db $00
strMOptions
         db $4F,$70,$74,$69,$6F,$6E,$73
         db $00
strMusOn
         db $4D,$75,$73,$69,$63,$3A,$20
         db $4F,$6E
         db $00
strMusOff
         db $4D,$75,$73,$69,$63,$3A,$20
         db $4F,$66,$66
         db $00
strSndOn
         db $53,$6F,$75,$6E,$64,$3A,$20
         db $4F,$6E
         db $00
strSndOff
         db $53,$6F,$75,$6E,$64,$3A,$20
         db $4F,$66,$66
         db $00
strBack
         db $42,$61,$63,$6B
         db $00
strFullscreen
         db $46,$75,$6C,$6C,$73,$63,$72,$65
         db $65,$6E,$3A,$20,$4F,$6E,$00
strMusicLabel
         db $4D,$75,$73,$69,$63,$3A,$00
strSoundLabel
         db $53,$6F,$75,$6E,$64,$3A,$00
strOn    db $4F,$6E,$00
strOff   db $4F,$66,$66,$00
strHighScore
         db $48,$69,$67,$68,$20,$73,$63,$6F
         db $72,$65,$00
strTimeTrialScore
         db $54,$69,$6D,$65,$74,$72,$69,$61
         db $6C,$3A,$00
strEndlessScore
         db $45,$6E,$64,$6C,$65,$73,$73,$20
         db $20,$3A,$00
strPortCredit
         db $46,$72,$65,$65,$67,$65,$6D,$61
         db $73,$20,$41,$70,$70,$6C,$65,$20
         db $49,$49,$67,$73,$20,$70,$6F,$72
         db $74,$20,$62,$79,$20,$61,$6E,$6F
         db $6D,$69,$78,$65,$72,$20,$32,$30
         db $32,$36,$00
strHtTitle
         db $48,$6F,$77,$20,$74,$6F,$20,$70
         db $6C,$61,$79
         db $00
strHtBack
         db $50,$72,$65,$73,$73,$20,$61,$6E
         db $79,$20,$62,$75,$74,$74,$6F,$6E
         db $20,$74,$6F,$20,$67,$6F,$20,$62
         db $61,$63,$6B
         db $00
hs01
         db $54,$68,$65,$20,$6F,$62,$6A,$65
         db $63,$74,$69,$76,$65,$20,$69,$73
         db $20,$74,$6F,$20,$73,$77,$61,$70
         db $20,$6F,$6E,$65
         db $00
hs02
         db $67,$65,$6D,$20,$77,$69,$74,$68
         db $20,$61,$6E,$20,$61,$64,$6A,$61
         db $63,$65,$6E,$74,$20,$67,$65,$6D
         db $20,$74,$6F
         db $00
hs03
         db $66,$6F,$72,$6D,$20,$61,$20,$68
         db $6F,$72,$69,$7A,$6F,$6E,$74,$61
         db $6C,$20,$6F,$72,$20,$76,$65,$72
         db $74,$69,$63,$61,$6C
         db $00
hs04
         db $63,$68,$61,$69,$6E,$20,$6F,$66
         db $20,$74,$68,$72,$65,$65,$20,$6F
         db $72,$20,$6D,$6F,$72,$65,$20,$67
         db $65,$6D,$73,$2E
         db $00
hs05
         db $00
hs06
         db $53,$65,$6C,$65,$63,$74,$20,$74
         db $68,$65,$20,$66,$69,$72,$73,$74
         db $20,$67,$65,$6D,$20,$61,$6E,$64
         db $20,$74,$68,$65,$6E
         db $00
hs07
         db $73,$65,$6C,$65,$63,$74,$20,$61
         db $6E,$20,$61,$64,$6A,$61,$63,$65
         db $6E,$74,$20,$67,$65,$6D,$2E,$20
         db $41
         db $00
hs08
         db $63,$6F,$72,$72,$65,$63,$74,$20
         db $6D,$6F,$76,$65,$20,$73,$77,$61
         db $70,$73,$20,$74,$68,$65,$6D,$20
         db $61,$6E,$64
         db $00
hs09
         db $72,$65,$6D,$6F,$76,$65,$73,$20
         db $74,$68,$65,$20,$6D,$61,$74,$63
         db $68,$69,$6E,$67,$20,$63,$68,$61
         db $69,$6E,$2E
         db $00
hs10
         db $00
hs11
         db $4C,$6F,$6E,$67,$65,$72,$20,$63
         db $68,$61,$69,$6E,$73,$20,$67,$69
         db $76,$65,$20,$62,$6F,$6E,$75,$73
         db $00
hs12
         db $70,$6F,$69,$6E,$74,$73,$2E,$20
         db $46,$61,$6C,$6C,$69,$6E,$67,$20
         db $67,$65,$6D,$73,$20,$63,$61,$6E
         db $20,$66,$6F,$72,$6D
         db $00
hs13
         db $63,$61,$73,$63,$61,$64,$65,$73
         db $2C,$20,$77,$68,$69,$63,$68,$20
         db $61,$6C,$73,$6F,$20,$67,$69,$76
         db $65
         db $00
hs14
         db $62,$6F,$6E,$75,$73,$20,$70,$6F
         db $69,$6E,$74,$73,$2E
         db $00
htStrTab
         dw hs01,hs02,hs03,hs04,hs05,hs06,hs07,hs08,hs09,hs10,hs11,hs12,hs13,hs14
htYTab
         dw 46,54,63,71,79,87,96,104,113,121,129,138,146,154
strOver  db $47,$41,$4D,$45,$20,$4F,$56,$45,$52,$00
strScore db $53,$43,$4F,$52,$45,$00
strAgain db $53,$50,$41,$43,$45,$20,$4F,$52,$20,$43,$4C,$49,$43,$4B,$20,$54
         db $4F,$20,$52,$45,$50,$4C,$41,$59,$00
strQuit  db $45,$53,$43,$20,$54,$4F,$20,$51,$55,$49,$54,$00
strHi    db $48,$49,$00                       ; "HI"
strBest  db $42,$45,$53,$54,$20,$00           ; "BEST "
strNewBest db $4E,$45,$57,$20,$42,$45,$53,$54,$20,$00  ; "NEW BEST "

*-----------------------------------------------------------------------------
* Match engine core. scanBoard marks every cell in a run of 3+ (horizontal
* then vertical), removeMarked clears the marked gems, collapseBoard drops the
* surviving gems down each column and refills the empty top cells, and
* resolveBoard repeats that until the cascade settles (capped at 8 rounds).
*-----------------------------------------------------------------------------
scanBoard anop
         stz dMatchUnits
         stz dGroupCount
         sep #$20
         longa off
         ldx #0
         lda #0
markClear
         sta dMark,x
         inx
         cpx #128
         bne markClear
         rep #$20
         longa on

         lda #1                   ; horizontal: stride 1, bases 0,8,...56
         sta dStride
         lda #8
         sta dBaseInc
         lda #0
         sta dLineBase
         lda #8
         sta dLineCnt
hLine
         jsr scanLine
         lda dLineBase
         clc
         adc dBaseInc
         sta dLineBase
         dec dLineCnt
         bne hLine

         lda #8                   ; vertical: stride 8, bases 0..7
         sta dStride
         lda #1
         sta dBaseInc
         lda #0
         sta dLineBase
         lda #8
         sta dLineCnt
vLine
         jsr scanLine
         lda dLineBase
         clc
         adc dBaseInc
         sta dLineBase
         dec dLineCnt
         bne vLine

         lda #0
         sta dMatchCnt
         ldx #0
cMarks
         lda dMark,x
         beq cNext
         inc dMatchCnt
cNext
         inx
         inx
         cpx #128
         bne cMarks
         rts

*-----------------------------------------------------------------------------
* A = one line of 8 cells: dLineBase + dStride * 0..7.
*-----------------------------------------------------------------------------
scanLine anop
         lda dStride
         asl a
         sta dWordStride
         lda dLineBase
         asl a
         sta dIdx
         sta dRunStart
         ldx dIdx
         lda cellgem,x
         sta dRunGem
         lda #1
         sta dRunLen
         lda dIdx
         clc
         adc dWordStride
         sta dIdx
         lda #1
         sta dStep
sStep
         ldx dIdx
         lda cellgem,x
         sta dGemNow
         cmp dRunGem
         bne sBreak
         cmp #0
         beq sBreak
         inc dRunLen
sNext
         lda dIdx
         clc
         adc dWordStride
         sta dIdx
         inc dStep
         lda dStep
         cmp #8
         bcc sStep
         jsr markRun
         rts
sBreak
         jsr markRun
         lda dGemNow
         sta dRunGem
         lda #1
         sta dRunLen
         lda dIdx
         sta dRunStart
         brl sNext

*-----------------------------------------------------------------------------
* Mark dRunStart..dRunStart+dRunLen-1 when the run is at least 3 long.
*-----------------------------------------------------------------------------
markRun anop
         lda dRunLen
         cmp #3
         bcc mRunDone
         clc
         adc dMatchUnits
         sta dMatchUnits
         lda dGroupCount
         cmp #32
         bcs mgRecorded
         lda dRunStart
         lsr a
         sta dGroupCenter
         lda dRunLen
         lsr a
         tay
mgCenter lda dGroupCenter
         clc
         adc dStride
         sta dGroupCenter
         dey
         bne mgCenter
         lda dGroupCount
         asl a
         tax
         lda dGroupCenter
         sta dGroupCell,x
         lda dRunLen
         sta dGroupSize,x
         inc dGroupCount
mgRecorded
         ldx dRunStart            ; already a word offset into cellgem/dMark
         ldy dRunLen
mRunLoop
         lda #1
         sta dMark,x
         txa                      ; step along the run: 2 bytes horizontally,
         clc                      ; 16 bytes vertically (dWordStride)
         adc dWordStride
         tax
         dey
         bne mRunLoop
mRunDone
         rts

*-----------------------------------------------------------------------------
* Clear every marked gem and repaint its cell with the board background.
*-----------------------------------------------------------------------------
removeMarked anop
         lda #0
         sta dRemIdx
remLoop
         lda dRemIdx
         asl a
         tax
         lda dMark,x
         beq remNext
         lda #0
         sta cellgem,x
         lda dRemIdx
         jsr drawCellIndex
remNext
         inc dRemIdx
         lda dRemIdx
         cmp #64
         bcc remLoop
         rts

*-----------------------------------------------------------------------------
* Gravity plus refill: compact each column downwards, then fill the emptied
* top cells with fresh random gems.
*-----------------------------------------------------------------------------
collapseBoard anop
         lda #0
         sta dColBase
colLoop
         lda #0
         sta dEmpty
         lda #7
         sta dReadRow
         lda #56
         clc
         adc dColBase
         asl a
         sta dWriteIdx
         lda #8
         sta dColCnt
readLoop
         lda dReadRow
         asl a
         asl a
         asl a
         clc
         adc dColBase
         asl a
         sta dIdx
         ldx dIdx
         lda cellgem,x
         beq readNext
         ldy dWriteIdx
         sta cellgem,y
         cpx dWriteIdx
         beq noClear
         lda #0
         sta cellgem,x
noClear
         lda dWriteIdx
         sec
         sbc #16
         sta dWriteIdx
         brl readNext2
readNext
         inc dEmpty
readNext2
         dec dReadRow
         dec dColCnt
         bne readLoop

         lda dEmpty
         beq fillDone
         lda #0
         sta dFillRow
fillLoop
         lda dFillRow
         asl a
         asl a
         asl a
         clc
         adc dColBase
         asl a
         tax
         jsr nextRandom
         sta cellgem,x
         inc dFillRow
         lda dFillRow
         cmp dEmpty
         bcc fillLoop
fillDone
         inc dColBase
         lda dColBase
         cmp #8
         bcs collapseDone
         brl colLoop
collapseDone
         rts

*-----------------------------------------------------------------------------
* Cascade animation (M2 visual parity).  The original pops the matched gems and
* then drops the survivors ; this does the same in three pieces:
*   flashMarked  - source particles and per-group floating points
*   animCollapse - compress/refill, then interpolate moving gems
*   animAppear / dropBoard - elapsed-time whole-board movement
* Only the cells that change are repainted, so the animation stays cheap.
*-----------------------------------------------------------------------------
FLASH_FRAMES equ 6
ANIM_MAX     equ 24

* Block until the next vertical blank starts (one 60 Hz frame).
waitFrame anop
         sep #$20
         longa off
wfLow             lda    >VERTFLAG
         bmi wfLow               ; wait out the blank that is in progress
wfHigh            lda    >VERTFLAG
         bpl wfHigh              ; ...then wait for the next one
         rep #$20
         longa on
         jsr musStep             ; animations (flash/collapse, ~24 frames) own
                                 ; the main loop here; without this the music
                                 ; buffer ran dry and the DOC went silent right
                                 ; when a match sound played (M3 蝥?16)
         rts

* Matched gems disappear into the original particle artwork. Floating
* group points rise inside their cleared cell; there is no white rectangle.
flashMarked anop
         jsr pointerHide
         jsr clockRead
         sta dFxStartTick
         stz dFxPhase
fxFrame  jsr fxDrawMarked
         jsr fxDrawScores
fxWait   jsr musStep
         jsr clockRead
         sec
         sbc dFxStartTick
         cmp #20
         bcs fxDone
         ldx #0
fxDivide cmp #5
         bcc fxPhaseReady
         sec
         sbc #5
         inx
         bra fxDivide
fxPhaseReady cpx dFxPhase
         beq fxWait
         stx dFxPhase
         brl fxFrame
fxDone   jsr fxEraseMarked
         rts

fxEraseMarked anop
         stz dFxCell
fxEraseCell lda dFxCell
         asl a
         tax
         lda dMark,x
         beq fxEraseNext
         lda dFxCell
         jsr blankCell
         jsr musYield
fxEraseNext inc dFxCell
         lda dFxCell
         cmp #64
         bcc fxEraseCell
         rts

fxDrawMarked anop
         stz dFxCell
fxCell   lda dFxCell
         asl a
         tax
         lda dMark,x
         beq fxNextCell
         lda dFxCell
         jsr blankCell
         lda dFxCell
         asl a
         tax
         lda cellGemX,x
         clc
         adc #1
         sta dFxX
         lda cellGemY,x
         clc
         adc #3
         sec
         sbc dFxPhase
         sta dFxY
         jsr drawSpark
         lda dFxCell
         asl a
         tax
         lda cellGemX,x
         clc
         adc #6
         sta dFxX
         lda cellGemY,x
         clc
         adc #10
         adc dFxPhase
         sta dFxY
         jsr drawSpark
         jsr musYield
fxNextCell inc dFxCell
         lda dFxCell
         cmp #64
         bcc fxCell
         rts

fxDrawScores anop
         stz dFxGroup
fxScoreGroup lda dFxGroup
         cmp dGroupCount
         bcs fxScoresDone
         asl a
         tax
         lda dGroupSize,x
         sta dFxValue
         asl a
         asl a
         clc
         adc dFxValue
         sta dFxBaseValue
         stz dNumVal
         ldy dCasc
fxMultiply lda dNumVal
         clc
         adc dFxBaseValue
         sta dNumVal
         dey
         bne fxMultiply
         lda dHintUsed
         beq fxHaveValue
         lda dCasc
         cmp #1
         bne fxHaveValue
         stz dNumVal
fxHaveValue jsr mkNumStr
         lda dFxGroup
         asl a
         tax
         lda dGroupCell,x
         asl a
         tax
         lda cellGemX,x
         asl a
         clc
         adc #2
         sta dTextX
         lda dFxPhase
         asl a
         sta dFxRise
         lda cellGemY,x
         clc
         adc #8
         sec
         sbc dFxRise
         sta dTextY
         lda #1
         sta dTScale
         ldx #dNumBuf
         jsr drawText
         inc dFxGroup
         brl fxScoreGroup
fxScoresDone rts

drawSpark anop
         lda dFxPhase
         asl a
         asl a
         asl a
         asl a
         asl a
         asl a
         sta dFxSource
         lda #8
         sta dFxRows
fxSparkRow lda dFxY
         cmp #14
         bcc fxSparkNext
         cmp #190
         bcs fxSparkNext
         asl a
         tax
         lda screenRows,x
         clc
         adc dFxX
         tax
         ldy dFxSource
         lda fxStar,y
         and >SCREEN,x
         ora fxStar+2,y
         sta >SCREEN,x
         lda fxStar+4,y
         and >SCREEN+2,x
         ora fxStar+6,y
         sta >SCREEN+2,x
fxSparkNext inc dFxY
         lda dFxSource
         clc
         adc #8
         sta dFxSource
         dec dFxRows
         bne fxSparkRow
         rts

* A = number of 60 Hz frames to wait (dAnimSpeed / harness slow-motion hook).
waitFramesN anop
         sta dWaitCnt
         beq wfnOut
wfnLoop  jsr waitFrame
         dec dWaitCnt
         bne wfnLoop
wfnOut   rts

* Pixel motion shared by swaps, gravity, board appearance and board exit.
* Logical board data and visual positions are independent during a transition.
motionClear anop
         stz dMotionType
         stz dMotionSwap
         ldx #0
         lda #0
mvClear  sta dMotionGem,x
         inx
         inx
         cpx #128
         bcc mvClear
         rts

* Initialise a destination slot X from dMvGem/dMvStartY/dMvEndY. Column X
* positions are identical here; swap setup overrides the two endpoints.
motionSlot anop
         lda dMvGem
         sta dMotionGem,x
         lda dMvStartY
         sta dMotionSY,x
         sta dMotionPY,x
         lda dMvEndY
         sta dMotionEY,x
         lda cellGemX,x
         sta dMotionSX,x
         sta dMotionEX,x
         sta dMotionPX,x
         rts

animCollapse anop
         jsr motionClear
         ldx #0
mvSnapshot lda cellgem,x
         sta dBoardShadow,x
         lda #0
         sta cellgem,x
         inx
         inx
         cpx #128
         bcc mvSnapshot
         stz dMvCol
mvColumn lda #7
         sta dMvWrite
         sta dMvRead
mvRead   lda dMvRead
         asl a
         asl a
         asl a
         clc
         adc dMvCol
         asl a
         tax
         lda dBoardShadow,x
         beq mvReadNext
         sta dMvGem
         lda cellGemY,x
         sta dMvStartY
         lda dMvWrite
         asl a
         asl a
         asl a
         clc
         adc dMvCol
         asl a
         tax
         lda dMvGem
         sta cellgem,x
         lda cellGemY,x
         sta dMvEndY
         cmp dMvStartY
         beq mvStationary
         jsr motionSlot
mvStationary dec dMvWrite
mvReadNext dec dMvRead
         bpl mvRead
         lda dMvWrite
         inc a
         sta dMvMissing
         stz dMvRead
mvNew    lda dMvRead
         cmp dMvMissing
         bcs mvColumnDone
         asl a
         asl a
         asl a
         clc
         adc dMvCol
         asl a
         tax
         jsr nextRandom
         sta cellgem,x
         sta dMvGem
         lda cellGemY,x
         sta dMvEndY
         lda dMvMissing
         asl a
         sta dMvTmp
         asl a
         clc
         adc dMvTmp
         sta dMvTmp
         lda dMvMissing
         asl a
         asl a
         asl a
         asl a
         clc
         adc dMvTmp              ; missing * 22
         sta dMvTmp
         lda dMvEndY
         sec
         sbc dMvTmp
         sta dMvStartY
         jsr motionSlot
         inc dMvRead
         bra mvNew
mvColumnDone inc dMvCol
         lda dMvCol
         cmp #8
         bcs mvFallReady
         brl mvColumn
mvFallReady lda #24               ; 0.4s, not four VBLs for each whole row
         sta dMotionDuration
         lda #2                  ; original easeOutQuad
         sta dMotionEase
         jsr animateMotion
         rts

animAppear anop
         jsr restoreGameBoard
         jsr motionClear
         lda #1
         sta dMotionType
         ldx #0
mvAppear lda cellgem,x
         sta dMvGem
         lda cellGemY,x
         sta dMvEndY
         sec
         sbc #176
         sta dMvStartY
         jsr motionSlot
         inx
         inx
         cpx #128
         bcc mvAppear
         lda #47                  ; 12-tick columns, staggered by 5 ticks
         sta dMotionDuration
         lda #2
         sta dMotionEase
         jsr animateMotion
         rts

dropBoard anop
         jsr clearHint
         lda dCursor
         jsr drawCellIndex        ; only the cursor and selected cell need cleanup
         lda dSelCell
         cmp #64
         bcs dbUnframed
         jsr drawCellIndex
dbUnframed
         jsr motionClear
         lda #2
         sta dMotionType
         ldx #0
mvDrop   lda cellgem,x
         sta dMvGem
         lda cellGemY,x
         sta dMvStartY
         txa
         and #14
         asl a
         clc
         adc #210
         clc
         adc dMvStartY
         sta dMvEndY
         jsr motionSlot
         inx
         inx
         cpx #128
         bcc mvDrop
         lda #47                  ; same staggered duration as appearance
         sta dMotionDuration
         lda #1
         sta dMotionEase
         jsr animateMotion
         rts

animSwap anop
         jsr motionClear
         lda #1
         sta dMotionSwap
         lda dSwapA
         jsr drawCellIndex
         lda dSwapB
         jsr drawCellIndex
         lda dSwapA
         asl a
         sta dMvSlotA
         tax
         lda cellgem,x
         sta dMvGem
         lda cellGemY,x
         sta dMvStartY
         lda dSwapB
         asl a
         tay
         lda cellGemY,y
         sta dMvEndY
         jsr motionSlot
         lda cellGemX,y
         sta dMotionEX,x
         lda dSwapB
         asl a
         tax
         lda cellgem,x
         sta dMvGem
         lda cellGemY,x
         sta dMvStartY
         ldy dMvSlotA
         lda cellGemY,y
         sta dMvEndY
         jsr motionSlot
         lda cellGemX,y
         sta dMotionEX,x
         lda #10
         sta dMotionDuration
         lda #2
         sta dMotionEase
         jsr animateMotion
         rts

* Restore only a previously occupied 24x20 rectangle, clipped to the board.
eraseMotionRect anop
         lda #20
         sta dEraseRows
eraseMotionRows lda dEraseRows
         beq emNoRows
         lda dEraseY
         bmi emAbove
         cmp #14
         bcs emTopReady
emAbove  lda dEraseY
         clc
         adc dEraseRows          ; exclusive bottom, even for negative starts
         bmi emNoRows
         cmp #15
         bcc emNoRows
         sec
         sbc #14
         sta dEraseRows
         lda #14
         sta dEraseY
emTopReady lda dEraseY
         cmp #190
         bcs emNoRows
         clc
         adc dEraseRows
         cmp #191
         bcc emAddress
         lda #190
         sec
         sbc dEraseY
         sta dEraseRows
         bra emAddress
emNoRows rts
emAddress lda dEraseY
         sec
         sbc #14
         asl a
         tax
         lda boardRows,x
         clc
         adc dEraseX
         sec
         sbc #48
         tay
         lda dEraseY
         asl a
         tax
         lda screenRows,x
         clc
         adc dEraseX
         tax
emRow    lda dTitleSave+0,y
         sta >SCREEN+0,x
         lda dTitleSave+2,y
         sta >SCREEN+2,x
         lda dTitleSave+4,y
         sta >SCREEN+4,x
         lda dTitleSave+6,y
         sta >SCREEN+6,x
         lda dTitleSave+8,y
         sta >SCREEN+8,x
         lda dTitleSave+10,y
         sta >SCREEN+10,x
         txa
         clc
         adc #160
         tax
         tya
         clc
         adc #104
         tay
         dec dEraseRows
         bne emRow
emDone   rts

* Unsigned 16-bit multiply. Inputs here are at most 255, product <=65025.
motionMul anop
         stz dMulResult
mmLoop   lda dMulB
         beq mmDone
         lsr dMulB
         bcc mmShift
         lda dMulResult
         clc
         adc dMulA
         sta dMulResult
mmShift  asl dMulA
         bra mmLoop
mmDone   rts

motionInterpolate anop
         lda dIntEnd
         cmp dIntStart
         bne miMoving
         rts
miMoving lda dMotionProgress
         cmp #256
         bcc miPartial
         lda dIntEnd
         rts
miPartial stz dIntSign
         lda dIntEnd
         sec
         sbc dIntStart
         bpl miPositive
         eor #$FFFF
         inc a
         sta dIntValue
         lda #1
         sta dIntSign
         lda dIntValue
miPositive lsr a
         sta dMulA
         lda dMotionProgress
         sta dMulB
         jsr motionMul
         lda dMulResult
         lsr a
         lsr a
         lsr a
         lsr a
         lsr a
         lsr a
         lsr a
         sta dIntValue
         lda dIntSign
         beq miAdd
         lda dIntValue
         eor #$FFFF
         inc a
         sta dIntValue
miAdd    lda dIntValue
         clc
         adc dIntStart
         rts

motionProgress anop
         lda dMotionElapsed
         cmp dMotionDuration
         bcc mpPartial
         lda #256
         sta dMotionProgress
         rts
mpPartial xba
         and #$FF00
         stz dMotionProgress
mpDivide cmp dMotionDuration
         bcc mpEase
         sec
         sbc dMotionDuration
         inc dMotionProgress
         bra mpDivide
mpEase   lda dMotionEase
         beq mpLinear
         cmp #1
         beq mpEaseIn
         lda dMotionProgress
         beq mpLinear
         lda #256
         sec
         sbc dMotionProgress
         bra mpSquare
mpEaseIn lda dMotionProgress
mpSquare sta dMulA
         sta dMulB
         jsr motionMul
         lda dMulResult
         xba
         and #$00FF
         sta dMotionProgress
         lda dMotionEase
         cmp #1
         beq mpLinear
         lda #256
         sec
         sbc dMotionProgress
         sta dMotionProgress
mpLinear rts

animateMotion anop
         jsr pointerHide
         jsr clockRead
         sta dMotionStartTick
         stz dMotionElapsed
         stz dMotionFrames
         stz dPerfErase
         stz dPerfDraw
         stz dPerfMusic
         ldx #14
mvColumnInit stz dMotionColDone,x
         dex
         dex
         bpl mvColumnInit
mvFrame  jsr clockRead
         sta dMotionFrameTick
         jsr motionProgress
         lda dMotionType
         bne mvHasColumns
         brl mvNoColumns
mvHasColumns anop
         lda dMotionProgress
         sta dMotionGlobalProgress
         lda dMotionElapsed
         sta dMotionGlobalElapsed
         lda dMotionDuration
         sta dMotionGlobalDuration
         lda #12
         sta dMotionDuration
         stz dMotionIndex
mvColumnDelta ldx dMotionIndex
         lda dMotionColDone,x
         beq mvColumnPending
         lda #3                  ; settled columns do no further drawing
         sta dMotionColState,x
         bra mvColumnNext
mvColumnPending txa
         lsr a
         sta dIntValue
         asl a
         asl a
         clc
         adc dIntValue           ; column * 5 ticks
         sta dIntValue
         lda dMotionGlobalElapsed
         sec
         sbc dIntValue
         bcs mvColumnStarted
         stz dMotionColState,x   ; not started: preserve the existing screen
         bra mvColumnNext
mvColumnStarted cmp #12
         bcc mvColumnActive
         lda #1
         sta dMotionColDone,x
         lda #2                  ; draw the final position once
         sta dMotionColState,x
         lda #12
         bra mvColumnTime
mvColumnActive pha
         lda #1
         sta dMotionColState,x
         pla
mvColumnTime sta dMotionElapsed
         jsr motionProgress
         ldx dMotionIndex
         lda dMotionType
         cmp #1
         beq mvAppearDelta
         txa
         asl a
         clc
         adc #210
         bra mvDeltaReady
mvAppearDelta lda #176
mvDeltaReady sta dIntEnd
         stz dIntStart
         jsr motionInterpolate
         ldx dMotionIndex
         sta dMotionColDelta,x
mvColumnNext inc dMotionIndex
         inc dMotionIndex
         lda dMotionIndex
         cmp #16
         bcs mvColumnsDone
         brl mvColumnDelta
mvColumnsDone lda dMotionGlobalProgress
         sta dMotionProgress
         lda dMotionGlobalElapsed
         sta dMotionElapsed
         lda dMotionGlobalDuration
         sta dMotionDuration
mvNoColumns lda dMotionSwap
         bne mvTwoPass
         lda #126
         sta dMotionIndex
         bra mvPaint
mvTwoPass stz dMotionIndex
mvErase  ldx dMotionIndex
         lda dMotionGem,x
         beq mvEraseNext
         lda dMotionPY,x
         sta dEraseY
         lda dMotionPX,x
         sta dEraseX
         jsr eraseMotionRect
         jsr musYield
mvEraseNext inc dMotionIndex
         inc dMotionIndex
         lda dMotionIndex
         cmp #128
         bcc mvErase
         stz dMotionIndex
mvPaint  jsr clockRead
         sta dPerfClock
         ldx dMotionIndex
         lda dMotionGem,x
         bne mvPaintActive
         brl mvPaintNext
mvPaintActive lda dMotionType
         beq mvIndividualY
         txa
         and #14
         tay
         lda dMotionColState,y
         beq mvColumnSkip
         cmp #3
         bne mvColumnPaint
mvColumnSkip brl mvPaintNext
mvColumnPaint lda dMotionColDelta,y
         clc
         adc dMotionSY,x
         bra mvNextYReady
mvIndividualY lda dMotionSY,x
         sta dIntStart
         lda dMotionEY,x
         sta dIntEnd
         jsr motionInterpolate
mvNextYReady sta dMotionNextY
         ldx dMotionIndex
         lda dMotionSwap
         bne mvPosition
         lda dMotionPY,x
         sta dEraseY
         lda dMotionPX,x
         sta dEraseX
         lda #20
         sta dEraseRows
         lda dMotionNextY
         cmp #14
         bcc mvFullErase
         cmp #171
         bcs mvFullErase
         sec
         sbc dEraseY
         cmp #20
         bcs mvFullErase
         sta dEraseRows
mvFullErase jsr eraseMotionRows
         ldx dMotionIndex
mvPosition jsr clockRead
         pha
         sec
         sbc dPerfClock
         clc
         adc dPerfErase
         sta dPerfErase
         pla
         sta dPerfClock
         ldx dMotionIndex
         lda dMotionNextY
         sta dGemY
         sta dMotionPY,x
         lda dMotionSX,x
         sta dIntStart
         lda dMotionEX,x
         sta dIntEnd
         jsr motionInterpolate
         ldx dMotionIndex
         sta dGemX
         sta dMotionPX,x
         lda dMotionGem,x
         sta dGem
         jsr drawGem
         jsr clockRead
         pha
         sec
         sbc dPerfClock
         clc
         adc dPerfDraw
         sta dPerfDraw
         pla
         sta dPerfClock
         jsr musYield
         jsr clockRead
         sec
         sbc dPerfClock
         clc
         adc dPerfMusic
         sta dPerfMusic
mvPaintNext lda dMotionSwap
         bne mvSwapNext
         dec dMotionIndex
         dec dMotionIndex
         bmi mvPaintDone
         brl mvPaint
mvSwapNext inc dMotionIndex
         inc dMotionIndex
         lda dMotionIndex
         cmp #128
         bcs mvPaintDone
         brl mvPaint
mvPaintDone inc dMotionFrames
         inc dAnimSteps
         lda dMotionElapsed
         cmp dMotionDuration
         bcs mvFinished
mvWait   jsr musStep
         jsr clockRead
         sec
         sbc dMotionFrameTick
         cmp #2
         bcc mvWait
         jsr clockRead
         sec
         sbc dMotionStartTick
         sta dMotionElapsed
         brl mvFrame
mvFinished jsr clockRead
         sta dMotionEndTick
         rts

* Hide the software pointer without capturing/repainting it during motion.
pointerHide anop
         lda dPtrOn
         beq pHideDone
         lda dPtrOff
         sta dDst
         ldy #0
pHideRow ldx dDst
         lda #8
         sta dPrtCnt
pHideByte jsr ptrRestoreByte
         inx
         iny
         dec dPrtCnt
         bne pHideByte
         lda dDst
         clc
         adc #160
         sta dDst
         cpy #PTR_BYTES
         bcc pHideRow
         stz dPtrOn
pHideDone rts

*-----------------------------------------------------------------------------
* Mix the continuously advancing system tick, current mouse coordinates and
* prior generator state so each fresh board differs across boots and resets.
* Xorshift's zero state is absorbing, so substitute a nonzero fallback.
seedRandom anop
         jsr clockRead
         eor dMouseX
         xba
         eor dMouseY
         eor dRandSeed
         bne srStore
         lda #$ACE1
srStore  sta dRandSeed
         rts

* 16-bit xorshift random gem: returns A = 1..7.
*-----------------------------------------------------------------------------
nextRandom anop
         lda dRandSeed
         sta dRandTmp
         asl dRandTmp
         asl dRandTmp
         asl dRandTmp
         lda dRandTmp
         eor dRandSeed
         sta dRandSeed
         lda dRandSeed
         sta dRandTmp
         lsr dRandTmp
         lsr dRandTmp
         lsr dRandTmp
         lsr dRandTmp
         lsr dRandTmp
         lda dRandTmp
         eor dRandSeed
         sta dRandSeed
         lda dRandSeed
         sta dRandTmp
         asl dRandTmp
         asl dRandTmp
         lda dRandTmp
         eor dRandSeed
         sta dRandSeed
         lda dRandSeed
         and #$0700
         xba
         and #$0007
         cmp #0
         bne randDone
         lda #7
randDone
         rts

*-----------------------------------------------------------------------------
* Score: matched gems x 5 x cascade multiplier (original Freegemas rule).
*-----------------------------------------------------------------------------
addScore anop
         lda dHintUsed           ; a hinted move scores nothing (original rule)
         bne asNoPoints
         lda dMatchUnits
         sta dTmpA
         asl a
         asl a
         clc
         adc dTmpA
         sta dPerGroup
         lda #0
         sta dAddScore
         ldy dCasc
mulLoop
         lda dAddScore
         clc
         adc dPerGroup
         sta dAddScore
         dey
         bne mulLoop
         lda dScore
         clc
         adc dAddScore
         sta dScore
         rts
asNoPoints
         lda #0
         sta dAddScore
         rts

*-----------------------------------------------------------------------------
* Clear/score/drop/refill until a rescan finds nothing; retain painted endpoints.
*-----------------------------------------------------------------------------
resolveBoard anop
         lda #1
         sta dCasc
resLoop
         jsr matchSound           ; match1..3, rotating like the original
         jsr addScore
         jsr removeMarked
         jsr flashMarked          ; source particles and per-group floating points
         jsr drawScore
         jsr fallSound            ; fall.wav while the survivors drop
         jsr animCollapse         ; final positions are already painted; keep them
         jsr scanBoard
         lda dMatchCnt
         beq resDone
         inc dCasc
         lda dCasc
         cmp #9
         bcc resLoop
resDone
         lda #0
         sta dHintUsed           ; hint penalty lasts for this move only
         lda dTimedOut
         bne resDoneRts
         jsr findHint
         lda dHintA
         cmp #$FFFF
         beq resNoMoves
* This search only checks whether play can continue. Do not leave its candidate
* in the visible hint slots; ptrStep paints any live dHintA/dHintB as green.
         lda #$FFFF
         sta dHintA
         sta dHintB
         bra resDoneRts
resNoMoves
         lda dMode
         bne resEndless
         jsr dropBoard
         jsr genBoard            ; no legal swap left: fresh board (original rule)
         jsr animAppear
         bra resDoneRts
resEndless
         jsr gameOver            ; Endless: no legal swap left ends the game
resDoneRts
         rts

*-----------------------------------------------------------------------------
* Draw every gem (the scene already provides wood, grid and panels).
*-----------------------------------------------------------------------------
drawBoard anop
          jsr restoreGameBoard
          lda #0
          sta dCellIdx
boardLoop
          lda dCellIdx
          jsr drawCellGem         ; the pristine board was restored above: gems have
                                  ; transparent pixels, so old pixels would
                                  ; otherwise show through (reset / cascade)
          jsr musYield
          inc dCellIdx
          lda dCellIdx
          cmp #64
          bne boardLoop
          rts

*-----------------------------------------------------------------------------
* A = cell index (0..63): redraw the wood square (blankCell) plus that cell's
* gem. The cell is 26x22 = 13 bytes per row, one flat wood tone: slot 9 when
* (row+col) is even, slot 10 otherwise -- exactly what the streamed scene holds.
*-----------------------------------------------------------------------------
drawCellIndex anop
         sta dIdxTemp
         jsr blankCell
         lda dIdxTemp
drawCellGem anop
         asl a
         tax
         lda cellgem,x
         sta dGem
         lda cellGemY,x
         sta dGemY
         lda cellGemX,x
         sta dGemX
         jsr drawGem
         rts

* Restore exact sampled wood/grid, never a flat checker fill.
blankCell anop
         asl a
         tax
         lda cellBgOff,x
         tay
         lda celloff,x
         tax
         lda #22
         sta dRestoreRows
bcRow
         lda dTitleSave+0,y
         sta >SCREEN+0,x
         lda dTitleSave+2,y
         sta >SCREEN+2,x
         lda dTitleSave+4,y
         sta >SCREEN+4,x
         lda dTitleSave+6,y
         sta >SCREEN+6,x
         lda dTitleSave+8,y
         sta >SCREEN+8,x
         lda dTitleSave+10,y
         sta >SCREEN+10,x
         sep #$20
         longa off
         lda dTitleSave+12,y
         sta >SCREEN+12,x
         rep #$20
         longa on
         txa
         clc
         adc #160
         tax
         tya
         clc
         adc #104
         tay
         dec dRestoreRows
         bne bcRow
         rts

*-----------------------------------------------------------------------------
* A = cell index (0..63): set dScr for the selector frame (cell origin).
*-----------------------------------------------------------------------------
setFrameCell anop
         asl a
         tax
         lda celloff,x
         sta dScr
         rts

*-----------------------------------------------------------------------------
* Draw dGem at dGemX (byte column), dGemY (pixel row), clipped to the board.
* Full visible sprites use compiled blitters; clipped edges use compiled rows.
*-----------------------------------------------------------------------------
* 24x20 masked rasters, six unrolled mask/colour word pairs per line.
* Every destination scanline chooses its matching compiled SCB palette raster.
drawGem anop
         lda >dGem
         bne dgDraw
         rts
dgDraw   lda dGemY
         bpl dgCheckBottom
         cmp #$FFFB             ; -5 is the first partly visible 20px gem
         bcs dgCheckMotion
         rts
dgCheckBottom cmp #190
         bcc dgCheckMotion
         rts
dgCheckMotion lda dMotionSwap
         bne dgSlow
         lda dGemY
         cmp #14
         bcc dgSlow
         cmp #171
         bcs dgSlow
         asl a
         tax
         lda gemFastAlign,x
         clc
         adc dGem
         adc dGem
         dec a
         dec a
         tax
         lda gemFastOffset,x
         sta dgFastCall+1
         lda gemFastBank,x
         tax
         lda dGfxFastBanks,x
         beq dgSlow
         sep #$20
         longa off
         sta dgFastCall+3
         rep #$20
         longa on
         lda dGemY
         asl a
         tax
         lda screenRows,x
         clc
         adc dGemX
         tax
         lda dGemY
         sec
         sbc #14
         asl a
         tay
         lda boardRows,y
         clc
         adc dGemX
         sec
         sbc #48
         tay
         phb
         lda dGfxBank
         sep #$20
         longa off
         pha
         plb
         rep #$20
         longa on
dgFastCall jsl $000000
         plb
         rts
dgSlow   lda dGem
         dec a
         asl a
         tax
         lda >gemoff,x
         sta >dTileRow
         lda >dGfxBank
         bne dgBankReady
         rts
dgBankReady phb
         sep #$20
         longa off
         pha
         plb                    ; rasters are in a locked, bank-aligned allocation
         rep #$20
         longa on
         lda #20
         sta >dGemRowCnt
dgRow    lda >dGemY
         cmp #14
         bcs dgTopOk
         brl dgSkip
dgTopOk  cmp #190
         bcc dgVisible
         brl dgSkip
dgVisible
         asl a
         tax
         lda >screenRows,x
         clc
         adc >dGemX
         sta >dDst
         lda >gamePalOfs,x
         clc
         adc >dTileRow
         tay
         lda >dDst
         tax
         lda gemtiles,y          ; compiled row offset within the locked bank
         sta >dgCall+1
dgCall   jsl $000000             ; bank patched once by gfxInit, RTL row body
dgSkip   lda >dGemY
         inc a
         sta >dGemY
         lda >dTileRow
         clc
         adc #2
         sta >dTileRow
         lda >dGemRowCnt
         dec a
         sta >dGemRowCnt
         beq dgDone
         brl dgRow
dgDone   plb
dgReturn rts

*-----------------------------------------------------------------------------
* One-pixel frame around the 26x22 cell at dScr: 13-byte top and bottom rows
* (+3360 = 21 rows down), 20 side rows touching the left byte's high nibble
* and the right byte's low nibble.
*-----------------------------------------------------------------------------
drawFrame anop
         sep #$20
         longa off
         ldx dScr
         ldy #13
frameTop lda dFrameByte
                  sta    >SCREEN,x
         inx
         dey
         bne frameTop
         rep #$20
         longa on
         lda dScr
         clc
         adc #3360
         sta dFrameScr
         sep #$20
         longa off
         ldx dFrameScr
         ldy #13
frameBottom
         lda dFrameByte
                  sta    >SCREEN,x
         inx
         dey
         bne frameBottom
         rep #$20
         longa on
         lda dScr
         clc
         adc #160
         sta dFrameScr
         lda #20
         sta dCnt
frameSide sep #$20
         longa off
         ldx dFrameScr
                  lda    >SCREEN,x
         and #$0F                ; clear the left pixel, keep its right neighbour
         ora dFrameHi
                  sta    >SCREEN,x
                  lda    >SCREEN+12,x
         and #$F0
         ora dFrameLo
                  sta    >SCREEN+12,x
         rep #$20
         longa on
         lda dFrameScr
         clc
         adc #160
         sta dFrameScr
         dec dCnt
         bne frameSide
         rts

*-----------------------------------------------------------------------------
* HUD digits: crisp 7-segment masks. Score 7x9 at y44, time 11x14 at y82.
* Horizontal placement centres actual first/last glyph ink around x45, not
* the nominal character cells. Erase the panel interior so changing widths
* cannot leave fragments from the previous value. Digit ink is palette 14.
*-----------------------------------------------------------------------------
* Centre the actual ink bounds, including narrow leading digit 1. Score and
* time keep their fixed cell pitch, but have equal visible margins in the panel.
centerScore lda dScore
         sta dVal
         lda #1
         sta dHudCount
         jsr div10
         sta dHudLast
         sta dHudFirst
csCount  lda dQuot
         beq csBounds
         sta dVal
         inc dHudCount
         jsr div10
         sta dHudFirst
         bra csCount
csBounds lda dHudFirst
         asl a
         tax
         lda dgtSleft,x
         sta dHudLeading
         lda dHudLast
         asl a
         tax
         lda dgtSright,x
         sta dHudTrailing
         lda dHudCount
         dec a
         asl a
         asl a
         asl a
         sta dHudSpan
         bra centerHud
centerTime lda dMin
         asl a
         tax
         lda dgtTleft,x
         sta dHudLeading
         lda dHudLast
         asl a
         tax
         lda dgtTright,x
         sta dHudTrailing
         lda #36
         sta dHudSpan
centerHud lda dHudSpan
         clc
         adc dHudTrailing
         sec
         sbc dHudLeading
         inc a
         lsr a
         sta dHudHalf
         lda #45
         sec
         sbc dHudHalf
         sec
         sbc dHudLeading
         clc
         adc dHudSpan
         sta dCharX
         rts

eraseScore anop
                  lda    #8
         lsr a
         sta dEByte              ; first byte of the erase rectangle
                  ldx    #42
         stx dERow
                  lda    #13
         sta dRows
esRow    lda dERow
         asl a
         asl a
         asl a
         asl a
         asl a                   ; *32
         sta dTmpW
         asl a
         asl a                   ; *128
         clc
         adc dTmpW               ; *160
         clc
         adc dEByte
         tax
         sep #$20
         longa off
                  ldy    #37
esFill   lda #$FF
                  sta    >SCREEN,x
         inx
         dey
         bne esFill
         rep #$20
         longa on
         inc dERow
         dec dRows
         bne esRow
         rts

drawScore anop
         jsr eraseScore
         jsr centerScore
         lda dScore
         sta dVal
         lda #dgtSdata           ; base for the score mask table
         sta dMBase
         lda #dgtSptr
         sta dMTableAbs
         sep #$20
         longa off
         lda dgtSh
         rep #$20
         longa on
         and #$00FF
         sta dMH
         sep #$20
         longa off
         lda dgtSpitch
         rep #$20
         longa on
         and #$00FF
         dec a
         sta dMW
                  lda    #44
         sta dMY
dsLoop   jsr div10               ; dQuot = dVal/10, A = remainder
         jsr blitDigit
         lda dCharX
         sec
                  sbc    #8
         sta dCharX
         lda dQuot
         beq dsDone
         sta dVal
         bra dsLoop
dsDone   rts

eraseTime anop
                  lda    #8
         lsr a
         sta dEByte
                  ldx    #{78}
         stx dERow
                  lda    #22
         sta dRows
etRow    lda dERow
         asl a
         asl a
         asl a
         asl a
         asl a
         sta dTmpW
         asl a
         asl a
         clc
         adc dTmpW
         clc
         adc dEByte
         tax
         sep #$20
         longa off
                  ldy    #37
etFill   lda #$FF
                  sta    >SCREEN,x
         inx
         dey
         bne etFill
         rep #$20
         longa on
         inc dERow
         dec dRows
         bne etRow
         rts

drawTime anop
         jsr eraseTime
         lda #dgtTdata
         sta dMBase
         lda #dgtTptr
         sta dMTableAbs
         sep #$20
         longa off
         lda dgtTh
         rep #$20
         longa on
         and #$00FF
         sta dMH
         sep #$20
         longa off
         lda dgtTpitch
         rep #$20
         longa on
         and #$00FF
         dec a
         sta dMW
                  lda    #82
         sta dMY
* Split seconds / minutes: dVal = dTimeLeft % 60, dQuot = dTimeLeft / 60.
         lda dTimeLeft
         sta dVal
         lda #0
         sta dQuot
tmDiv    lda dVal
         cmp #60
         bcc tmSplit
         sbc #60
         sta dVal
         inc dQuot
         bra tmDiv
tmSplit  lda dQuot
         sta dMin                ; minutes, before div10 clobbers dQuot
         jsr div10
         sta dHudLast
         pha
         jsr centerTime
         pla
         jsr blitDigit           ; sec ones
         jsr decCharX
         lda dQuot
         sta dVal
         jsr div10
         jsr blitDigit           ; sec tens
         jsr decCharX
         lda #10
         jsr blitDigit           ; ':'
         jsr decCharX
         lda dMin
         sta dVal
         jsr div10
         jsr blitDigit           ; min ones (unpadded, as the original)
         lda dQuot
         beq tmDone              ; minutes 0..9: no tens digit
         sta dVal
         jsr div10
         jsr blitDigit           ; min tens
tmDone   rts

*-----------------------------------------------------------------------------
* A = character 0..9 or ':' (10): point dMPtr at that mask and blit it.
* Callers advance dCharX themselves (drawScore inline, drawTime decCharX).
*-----------------------------------------------------------------------------
blitDigit anop
         asl a
         tay
* The pointer tables live in the segment's data bank, not the direct page, so
* (dp),y would read GS/OS workspace. Patch the absolute operand instead: the
* mask table entry is a 16-bit offset that is added to dMBase.
         lda dMTableAbs
         sta bdTabOp+1           ; patch low/high operand of bdTabOp as a word
bdTabOp  lda $0000,y
         clc
         adc dMBase
         sta dMPtrAbs
         lda dMPtrAbs
         sta dmMskOp+1
         lda dCharX
         sta dMX
         jsr drawMask
         rts

decCharX anop
         lda dCharX
         sec
                  sbc    #{12}
         sta dCharX
         rts

*-----------------------------------------------------------------------------
* dVal in: dQuot = dVal/10, dVal = remainder, A = remainder.
*-----------------------------------------------------------------------------
div10    anop
         lda #0
         sta dQuot
dvLoop   lda dVal
         cmp #10
         bcc dvDone
         sbc #10
         sta dVal
         inc dQuot
         bra dvLoop
dvDone   lda dVal
         rts

*-----------------------------------------------------------------------------
* Blit the 1bpp mask at dMPtr to (dMX,dMY), dMH rows x dMW pixels, colour
* nibble $E (slot 14, digit cyan). Mask rows are MSB-first, zero-padded to
* whole bytes. Pixels are replaced with AND+ORA: the erase fill leaves $FF
* background, so a plain ORA would be invisible.
*-----------------------------------------------------------------------------
drawMask anop
         lda dMW
         clc
         adc #7
         lsr a
         lsr a
         lsr a
         sta dMWB                ; mask bytes per row
         lda dMX
         lsr a
         sta dMXHalf             ; first screen byte column
         lda dMX
         and #$0001
         sta dMPar0              ; parity of the first pixel in every row
         lda dMY
         asl a
         asl a
         asl a
         asl a
         asl a
         sta dTmpW
         asl a
         asl a
         clc
         adc dTmpW               ; dMY * 160
         sta dMRowBase
         lda #0
         sta dMRrow
         ldy #0                  ; mask byte cursor
dmRow    lda dMRowBase
         clc
         adc dMXHalf
         tax                     ; X = screen byte at this row's start
         lda dMPar0
         sta dMPar
         lda dMWB
         sta dMBcnt
dmByte   sep #$20
         longa off
dmMskOp  lda $0000,y
         iny
         sta dMsk
         lda #8
         sta dMBits
dmBit    lda dMsk
         asl a
         sta dMsk
         bcs dmSet
         lda dMPar
         bne dmOddSkip
         bra dmAdv
dmOddSkip
         inx
         bra dmAdv
dmSet    lda dMPar
         bne dmOdd
                  lda    >SCREEN,x
         and #$0F
         ora #$E0
                  sta    >SCREEN,x
         bra dmAdv
dmOdd             lda    >SCREEN,x
         and #$F0
         ora #$0E
                  sta    >SCREEN,x
         inx
dmAdv    lda dMPar
         eor #$01
         sta dMPar
         dec dMBits
         bne dmBit
         rep #$20
         longa on
         dec dMBcnt
         bne dmByte
         lda dMRowBase
         clc
         adc #160
         sta dMRowBase
         inc dMRrow
         lda dMRrow
         cmp dMH
         bcc dmNext
         rts
dmNext   brl dmRow

*-----------------------------------------------------------------------------
* Data and constants.
*-----------------------------------------------------------------------------
SCREEN   equ $012000     ; bank 01 SHR linear alias selected by NEWVIDEO $E1
SCB      equ $019D00
PALBASE  equ $019E00
NEWVIDEO equ $01C029
SHADOWR  equ $01C035
KBD      equ $01C000
KBDSTRB  equ $01C010
VERTFLAG equ $01C019
MILESTONE equ $019CFF      ; last screen byte: boot progress marker
ADBSTAT  equ $01C027      ; ADB status: bit7 data full, bit6 int enable,
                          ; bit1 next byte's axis (0 = X, 1 = Y)
MOUSEDAT equ $01C024      ; ADB mouse data byte (button/sign/magnitude)
* Board geometry (tools/build_iigs_assets.py): 8 cells of 26x22 at (96,14).
B_X0     equ 96
B_Y0     equ 14
B_CW     equ 26
B_CH     equ 22
B_W      equ 208
B_H      equ 176

* Digit mask pointers are kept in the segment (absolute) and read back through
* patched absolute operands ; $F0/$F2 direct-page slots are GS/OS scratch.

SCENE_LEN equ 32000
GEMROWS   equ 20
FONT_FIRST equ 32          ; txtglyphs covers ASCII 32..90
SCORE_RIGHT equ 79
SCORE_SLOTS equ 6
SCORE_PITCH equ 7
SCORE_Y    equ 42
SCORE_H    equ 8
TIME_RIGHT equ 76
TIME_SLOTS equ 5
TIME_PITCH equ 12
TIME_Y     equ 78
TIME_H     equ 15
* Merlin32 has NO operator precedence: it evaluates strictly left to right,
* so `79 + 1 - 6 * 7` yields 518, not 38.  Split the products into their own
* equates (see the $FF-bar/erase bug in AGENTS.md).
SCORE_TEXT_W      equ 39   ; maximum five-digit ink span; placement is dynamic
SCORE_LEFT        equ 26
TIME_TEXT_W       equ 47   ; m:ss with full-width end digits
TIME_LEFT        equ 22

dGfxUserID dw 0
dGfxHandle ds 4
dGfxFastBanks dw 0,0,0
dGfxFastLoaded dw 0
pbGfxFastOpen dw 2,0
           adrl 0
pbGfxFastRead dw 4,0
           adrl 0
           adrl 65536
           adrl 0
nmGfxFast0 dw 14
           asc 'DATA:GEMS0.RAW'
nmGfxFast1 dw 14
           asc 'DATA:GEMS1.RAW'
nmGfxFast2 dw 14
           asc 'DATA:GEMS2.RAW'
dGfxBank   dw 0
dGfxError  dw 0
pbGfxOpen  dw 2,0
           adrl nmGfx
pbGfxRead  dw 4,0
           adrl 0
           adrl gfxBytes
           adrl 0
pbGfxClose dw 1,0
nmGfx      dw 13
           asc 'DATA:GEMS.RAW'

pbOpen      dw 2
            dw 0
            adrl scenePath
pbRead      dw 4
            dw 0
            adrl $012000
                  dw     {32000},0
                  dw     0,0
pbClose     dw 1
            dw 0
scenePath   dw 15
            asc 'DATA:SCENE4.RAW'
nmScene     equ scenePath
nmSceneE    dw 16
            asc 'DATA:SCENE4E.RAW'
nmTitle     dw 14
            asc 'DATA:TITLE.RAW'
nmHowto     dw 14
            asc 'DATA:HOWTO.RAW'
nmOptions   dw 16
            asc 'DATA:OPTIONS.RAW'
* High score file and its pblocks. Same shape as pbOpen/pbRead above: pCount,
* refNum (filled in from the successful Open/Create), then the parameters.
hiPath      dw 16
            asc 'DATA:HISCORE.DAT'  ; relative to the app's volume prefix
pbHiOpen    dw 2
            dw 0
            adrl hiPath
pbHiRead    dw 4
            dw 0
            adrl dHiBuf
                  dw     4,0
                  dw     0,0
pbHiWrite   dw 4
            dw 0
            adrl dHiBuf
                  dw     4,0
                  dw     0,0
pbHiClose   dw 1
            dw 0
* DOC wave files (M4). GS/OS name strings plus a shared Open/Read/Close pblock
* trio ; only the pathname pointer is patched per file, exactly like loadScene.
AUD_ITEMS equ 5
sndSelName  dw 15
            asc 'DATA:SELECT.PCM'
sndFallName dw 13
            asc 'DATA:FALL.PCM'
sndM1Name   dw 15
            asc 'DATA:MATCH1.PCM'
sndM2Name   dw 15
            asc 'DATA:MATCH2.PCM'
sndM3Name   dw 15
            asc 'DATA:MATCH3.PCM'
pbSndOpen   dw 2
            dw 0
            adrl sndSelName
pbSndRead   dw 4
            dw 0
            adrl $012000
                  dw     8192,0
                  dw     0,0
pbSndClose  dw 1
            dw 0
* MUSIC.PCM is streamed (M5): 126 s of 8-bit PCM does not fit in wave RAM, so
* the music section above reads it in 4K slices through pbMusRead while the
* oscillators loop the two 4K wave buffers.
musNamePtr  dw 14
            asc 'DATA:MUSIC.PCM'
pbMusOpen   dw 2
            dw 0
            adrl musNamePtr
pbMusGetEOF dw 2
            dw 0
            ds 4
pbMusWholeRead dw 4
            dw 0
            ds 4                  ; 24-bit buffer pointer
            ds 4                  ; requested byte count
            ds 4                  ; actual transfer count
pbMusRead   dw 4
            dw 0
            adrl dMusStage
                  dw     4096,0
                  dw     0,0
pbMusClose  dw 1
            dw 0
* 16-byte wave entries: name (adrl), DOC base, upload length, $C0 value and
* frequency. $20 = table size 4 (4K) + resolution 0 ; $29 = size 5 (8K) + res 1;
* $30 = size 6 (16K) + res 0. See the DOC RAM map above for the bases.
audTab      adrl sndSelName
                  dw     $0000,4096
                  dw     $20,4
                  dw     0,0
            adrl sndFallName
                  dw     $1000,4096
                  dw     $20,4
                  dw     0,0
            adrl sndM1Name
                  dw     $2000,16384
                  dw     $30,1
                  dw     0,0
            adrl sndM2Name
                  dw     $6000,16384
                  dw     $30,1
                  dw     0,0
            adrl sndM3Name
                  dw     $A000,16384
                  dw     $30,1
                  dw     0,0
* GS/OS strings take a 2-byte length word (GS/OS Reference ch.3) ; Merlin's
* `str` emits a Pascal 1-byte length, which Open reads as a bogus 21315-char
* path and fails.

* Exit hands the machine to the Finder instead of a blank GS/OS text page.
* Quit's pblock is a 16-bit result word followed by a long pointer to the
* *next* application's GS/OS pathname ; a NULL pointer is exactly the case
* Start.GS/OS reports as ".CONSOLE#Can't run next application" (it has already
* finished by then, so nothing repaints and the screen stays empty).  Point it
* at the Finder and GS/OS itself starts the desktop after we quit.
quitFinder  dw 24
            db $3A,$46,$52,$45,$45,$47,$45,$4D,$41,$53     ; ":FREEGEMAS"
            db $3A,$53,$59,$53,$54,$45,$4D                 ; ":SYSTEM"
            db $3A,$46,$49,$4E,$44,$45,$52                 ; ":FINDER"
quitpb      dw 0
            adrl quitFinder
dCursor     dw 27
dNewCursor  dw 0
dOldCursor  dw 0
dCellIdx    dw 0
dCount      dw 0
dGem        dw 0
dScr        dw 0
dDst        dw 0
dRows       dw 0
dCnt        dw 0
dFrameScr   dw 0
dSelCell    dw $FFFF     ; $FFFF = no gem marked for a swap
dDiff       dw 0
dSwapA      dw 0
dSwapB      dw 0
dTempGem    dw 0
dFrameByte  dw $0011     ; selector frame byte; slot 1 (white) by default
dFrameHi    dw $00F0
dFrameLo    dw $000F
dStride     dw 0
dWordStride dw 0
dBaseInc    dw 0
dLineBase   dw 0
dLineCnt    dw 0
dRunGem     dw 0
dRunLen     dw 0
dRunStart   dw 0
dIdx        dw 0
dIdxTemp    dw 0
dStep       dw 0
dGemNow     dw 0
dMatchCnt   dw 0
dRemIdx     dw 0
dEmpty      dw 0
dFillRow    dw 0
dReadRow    dw 0
dWriteIdx   dw 0
dColBase    dw 0
dColCnt     dw 0
dCasc       dw 1
* Text renderer / hint / game-over state (kept before dScore so the
* documented dScore = gempals-192 anchor stays valid).
dTColorNib  dw 0
dTColorHi   dw 0
dTColorLo   dw 0
dTScale     dw 1
dTextX      dw 0
dTextY      dw 0
dTextBase   dw 0
dTIdx       dw 0
dTChar      dw 0
dTRow       dw 0
dTCol       dw 0
dGlyphOfs   dw 0
dGlyphRow   dw 0
dPlotX      dw 0
dPlotY      dw 0
dPx         dw 0
dPy         dw 0
dRowBase    dw 0
dFillWord   dw 0
dFillX      dw 0
dFillX1     dw 0
dFillY0     dw 0
dFillY1     dw 0
dFillY      dw 0
dFillCnt    dw 0
dHCell      dw 0
dHa         dw 0
dHb         dw 0
dHintA      dw $FFFF
dHintB      dw $FFFF
dHintUsed   dw 0
dOver       dw 0
dGenFix     dw 0
dGenTries   dw 0
dNumVal     dw 0
dNumTmp     dw 0
dNumIdx     dw 0
dNumLen     dw 0
dNumBuf     ds 8
dScore      dw 0
dPerGroup   dw 0
dAddScore   dw 0
dTmpA       dw 0
dTmpW       dw 0
dRandSeed   dw $1234       ; mixed with tick/mouse entropy before each fresh board
dRandTmp    dw 0
dMark       ds 128      ; 64 word flags, one per cell
dBoardShadow ds 128     ; pre-pass copy: cascade animation moves one row/frame


dMatchUnits dw 0
dGroupCount dw 0
dGroupCenter dw 0
dGroupCell ds 64
dGroupSize ds 64
dFxStartTick dw 0
dFxPhase dw 0
dFxCell dw 0
dFxGroup dw 0
dFxValue dw 0
dFxBaseValue dw 0
dFxRise dw 0
dFxX dw 0
dFxY dw 0
dFxRows dw 0
dFxSource dw 0

dMotionGem ds 128
dMotionSY ds 128
dMotionEY ds 128
dMotionPY ds 128
dMotionSX ds 128
dMotionEX ds 128
dMotionPX ds 128
dMvGem dw 0
dMvStartY dw 0
dMvEndY dw 0
dMvCol dw 0
dMvRead dw 0
dMvWrite dw 0
dMvMissing dw 0
dMvTmp dw 0
dMvSlotA dw 0
dPerfClock dw 0
dPerfErase dw 0
dPerfDraw dw 0
dPerfMusic dw 0
dTitleIndex dw 0
dTitleElapsed dw 0
dTitleFrameTick dw 0
dTitleDelay dw 0
dTitleNewY dw 0
dTitleOldY dw 0
dTitleTileRow dw 0
dTitleRows dw 0
dTitlePY ds 14
dTitleDone ds 14
titleXTab dw 35,48,61,74,87,100,113
dMotionType dw 0
dMotionNextY dw 0
dMotionColDelta ds 16
dMotionColState ds 16
dMotionColDone ds 16
dMotionGlobalProgress dw 0
dMotionGlobalElapsed dw 0
dMotionGlobalDuration dw 0
dMotionSwap dw 0
dMotionDuration dw 0
dMotionEase dw 0
dMotionStartTick dw 0
dMotionEndTick dw 0
dMotionFrameTick dw 0
dMotionElapsed dw 0
dMotionProgress dw 0
dMotionFrames dw 0
dMotionIndex dw 0
dEraseX dw 0
dEraseY dw 0
dEraseRows dw 0
dIntStart dw 0
dIntEnd dw 0
dIntSign dw 0
dIntValue dw 0
dMulA dw 0
dMulB dw 0
dMulResult dw 0

dTitleSave  ds 18304        ; shared: Title menu, or pristine 104x176-byte game board
dGemY       dw 0
dGemX       dw 0
dTileRow    dw 0
dGemRowCnt  dw 0
dSaveRows   dw 0
dRestoreRows dw 0
dMoved      dw 0            ; animStep: cells that changed this frame
dAnimFrames dw 0            ; frames left in the current animation
dAnimSteps  dw 0            ; cascade animation frames since boot (evidence)
dFlashFrames dw 6           ; matched-gem pop length in frames
dAnimSpeed  dw 4            ; frames per gravity row (4 = 15 rows/s, like the original)
dWaitCnt    dw 0
dTimeLeft   dw 120      ; Time Trial: 2 minutes
dTick60     dw 0
dClockPtr   ds 4
dClockNow   dw 0
dClockDelta dw 0
dGameTickBase dw 0
dClockActive dw 0
dTimedOut   dw 0
dTimeDirty  dw 0
* --- ADB mouse state (M3) ---------------------------------------------------
dMouseX     dw 160          ; absolute pointer position on the 320x200 screen
dMouseY     dw 100
dMouseBtn   dw 0            ; 1 while the left button is held
dMousePrev  dw 0
dDragCell   dw $FFFF         ; left-press origin; $FFFF = released/consumed
dMouseClick dw 0            ; one-frame flag: button pressed this poll
dMouseMoved dw 0            ; one-frame flag: the pair carried a delta
dMouseStat  dw $00FF        ; $C027 as GS/OS left it (restored on quit)
dMByteX     dw 0
dMByteY     dw 0
dMBtn1      dw 0            ; button 1 (right) state from the X byte, 1 = down
dMBtn0      dw 0            ; button 0 (left) state from the Y byte, 1 = down
dMNewX      dw 0            ; 1 = an X byte arrived during this poll
dMNewY      dw 0            ; 1 = a Y byte arrived during this poll
dMDx        dw 0
dMDy        dw 0
dMTmp       dw 0
dMCol       dw 0
dMRow       dw 0
dMCell      dw $FFFF
* DEBUG (M3 蝥?16): ring of what mousePoll actually saw at $C027/$C024 while
* the host pointer moved.  dMLogS = status at poll entry, dMLogB = first byte
* read, dMLogC = second byte read ; index wraps at 32 polls (~0.5 s at 60 Hz).
dMLogIdx    dw 0
dMLogS      ds 32
dMLogB      ds 32
dMLogC      ds 32
* --- visible pointer overlay (M3) -------------------------------------------
dPtrX       dw 160
dPtrY       dw 100
dPtrOff     dw 0            ; SHR byte offset of the glove
dPrtNewX    dw 0
dPrtNewY    dw 0
dPrtT       dw 0
dPrtCnt     dw 0
dPrtCur     dw 0
dPrtNib     dw 0
dPtrOn      dw 0            ; 0 = nothing on screen to restore yet
dPtrSave    ds PTR_BYTES    ; bytes under the glove
dPtrPaint   ds PTR_BYTES    ; composed glove/frame bytes (restore guard)
dSavePal    ds 512          ; GS/OS desktop palette, given back on Quit
dSaveScb    ds 200          ; GS/OS scanline table, likewise
* --- title / menu / mode state (M3) -----------------------------------------
MENU_ITEMS  equ 5
OPT_ITEMS   equ 4
HOWTO_LINES equ 14
menuStrTab  dw strMTrial,strMEndless,strMHowto,strMOptions,strMExit
menuYTab    dw 117,131,145,159,173
optYTab     dw 48,65,82,99
gameBtnY    dw 136,151,179       ; build_iigs_assets.py BUTTONS, each 78x14 at x=7
dState      dw 0            ; 0 = title menu, 1 = playing, 2 = how to play
dMode       dw 0            ; 0 = Time Trial, 1 = Endless
dMenuSel    dw 0
dMenuPrev   dw 0            ; item whose bar+label the screen currently shows
dTrN        dw 0            ; debug: titleRedrawMenu calls
dTrB        dw 0            ; debug: titleRestoreBand calls
dTrY0       dw 0            ; debug: last bar rows
dTrY1       dw 0
dTrTick     dw 0            ; debug: dMusTick16 at the last bar
dRowY       dw 0            ; titleRestoreBand: scanline / running offsets
dRowCnt     dw 0
dBandRows   dw 11
dSaveOff    dw 0
dOptSel     dw 0            ; Options selection: Music, Sound, Fullscreen, Back
dOptPrev    dw $FFFF        ; Options row that currently owns the amber bar (FFFF = none)
dOptIdx     dw 0
dOptX       dw 0
dSoundOn    dw 1            ; Options: "Sound: On/Off", honoured by playSound
dMenuIdx    dw 0
dMenuX      dw 0
dPathPtr    dw 0
dLoadOfs    dw 0            ; byte offset of the next LOAD_CHUNK-byte scene slice
dLoadCnt    dw 0            ; slices still to read
dLoadErr    dw 0            ; non-zero once a slice read failed
dLineIdx    dw 0
dLen        dw 0
dVstate     db 0
dHdr        db 0
dPad        db 0
dSpan       db 0
dWood       db 0
dEByte      dw 0
dERow       dw 0
dVal        dw 0
dQuot       dw 0
dHudCount dw 0
dHudFirst dw 0
dHudLast dw 0
dHudLeading dw 0
dHudTrailing dw 0
dHudSpan dw 0
dHudHalf dw 0
dCharX      dw 0
dMH         dw 0
dMW         dw 0
dMBase      dw 0
dMTableAbs  dw 0             ; absolute address of the digit mask offset table
dMPtrAbs    dw 0             ; absolute address of the current digit mask
dMin        dw 0
dMX         dw 0
dMY         dw 0
dMRowBase   dw 0
dMXHalf     dw 0
dMWB        dw 0
dMPar       dw 0
dMPar0      dw 0
dMBcnt      dw 0
dMBits      dw 0
dMRrow      dw 0
dMsk        db 0
* --- high scores ------------------------------------------------------------
dHiTrial    dw 0            ; best Time Trial score (HISCORE.DAT word 0)
dHiEndless  dw 0            ; best Endless score (word 1)
dHiNew      dw 0            ; 1 = this round set a new best
dHiWidth    dw 0
dHiCount    dw 0
dHiRow      dw 0
dHiVal      dw 0
dHiX        dw 0
dHiTmp      dw 0
dHiTmp2     dw 0
dHiBuf      ds 4            ; file image while reading/writing
dBestPtr    dw 0
dBestLen    dw 0
dBestW      dw 0
* --- DOC audio (M4) ---------------------------------------------------------
dSndIdx     dw 0             ; wave being loaded / id of the last trigger
dSndTot     dw 0             ; total triggers (socket harness evidence)
dMatchVoice dw 4            ; match voice selector; toggles between pairs 4/5 and 0/1
dSndTmp     dw 0
dSndBase    dw 0
dSndY       dw 0
dSndFreq    dw 0
dSndC0      dw 0
dDocBase    dw 0
dSndLen     dw 0
dSndOk      dw 0             ; wave bytes that read back equal to the file
dSndBad     dw 0             ; ...and those that do not (must stay 0)
dSndReg     dw 0             ; DOC register number being checked
dSndExp     dw 0             ; expected byte for that register
dSndRegOk   dw 0             ; oscillator registers that read back as written
dSndRegBad  dw 0             ; ...and those that do not (must stay 0)
dSndByte    db 0
            ds 1
* --- DOC music streamer (M5) ------------------------------------------------
dMusOn      dw 1             ; Options: "Music: On/Off"
dMusState   dw 0             ; 1 while the stream is running
dMusBuf     dw 0             ; buffer index that is playing (0 = A, 1 = B)
dMusBase    dw 0             ; DOC base address being programmed
dMusAddr    dw 0
dMusNew     dw 0
dMusStart         dw     0                    ; dMusTick16 when the playing table started
dMusEnd     dw 0             ; dMusTick16 value at which the playing buffer ends
dMusTick16  dw 0             ; VSYNC counter in 1/16 frame units (wraps at 68 s)
dMusVstate dw 0             ; music VBL edge latch, also serviced during loads
dMusTotal   dw 0             ; bytes of the standby buffer already queued
dMusChunk   dw 0
dMusRead    dw 0             ; bytes transferred by the last GS/OS Read
dMusRef     dw 0             ; MUSIC.PCM refNum + 1 (0 = not open)
dMusOk      dw 0             ; music buffers started (harness evidence)
dMusBad     dw 0             ; starvations / read failures (must stay 0)
dMusGuard   dw 0             ; legacy poll trace slot
dMusReady   dw 0             ; standby DOC table is complete and safe to start
dMusIrqPending dw 0          ; osc 6 end event awaiting foreground refill
dMusIrqSwitched dw 0         ; handler already started the next table
dMusIrqInstalled dw 0        ; our DOC sound callback is installed
dMusIrqOld  ds 4              ; saved four-byte sound JML stub
dMusPump    dw 0             ; harness: musStep calls made from a scene load
dMusHalt    dw 0             ; harness: calls that saw the end-of-table flag
dMusRestart       dw     0                    ; full restarts from the top of MUSIC.PCM (game start)
dMusRewind        dw     0                    ; queue a rewind after starting a fresh DOC table
dMusCacheState dw 0             ; 0 unknown, 1 whole song cached, 2 cache unavailable
dMusHandle  ds 4                ; locked Memory Manager handle for the full song
dMusMemPtr  ds 4                ; 24-bit address of the cached PCM
dMusFileLen ds 4                ; MUSIC.PCM length returned by GS/OS GetEOF
dMusPos     ds 4                ; current byte offset in cached MUSIC.PCM
dMusAvail   ds 4                ; bytes remaining before the current 4K table
dEmOn             dw     0                    ; 1 = fake Tool Locator installed
dEmBank           dw     0                    ; program bank of the fake block
dEmTlSave         ds     4                    ; $E1/03C8-03CA before the fake
dEmPosSave        ds     4                    ; $E1/0190-0193 before the fake
dEmTools          ds     32                   ; scratch the Tool Locator points at
dMusStage   ds 4096          ; one buffer of PCM read ahead from disk

         put ../generated/gem_data.s

*-----------------------------------------------------------------------------
* Debug anchor table for the GSSquared socket harness. It lives after the
* generated assets and starts with a magic word so the harness can find it:
* dbgTab+4 is a list of 24-bit addresses (adrl) of the variables the test
* scripts read. Keep the order in sync with C:\tmp\p_verify2.ps1.
*-----------------------------------------------------------------------------
dbgPerf  asc 'FGP2'
         adrl dClockPtr
         adrl dGfxBank
         adrl dGfxError
         adrl dMotionDuration
         adrl dMotionFrames
         adrl dMotionStartTick
         adrl dMotionEndTick
         adrl dFxPhase
         adrl dTimedOut
         adrl dClockActive
         adrl dGameTickBase
         adrl dPerfErase
         adrl dPerfDraw
         adrl dPerfMusic
         adrl dTimeDirty

dbgTab   db $DE,$AD,$BE,$EF
         adrl dScore
         adrl dTimeLeft
         adrl dOver
         adrl dHintA
         adrl dHintB
         adrl dHintUsed
         adrl dSelCell
         adrl dCursor
         adrl dState
         adrl dMode
         adrl dMenuSel
         adrl dMouseX
         adrl dMouseY
         adrl dMouseClick
         adrl dMCell
         adrl cellgem
         adrl dHiTrial
         adrl dHiEndless
         adrl dHiNew
         adrl dSndTot
         adrl dSndOk
         adrl dSndBad
         adrl dSndRegOk
         adrl dSndRegBad
         adrl dAnimSteps
         adrl dFlashFrames
         adrl dAnimSpeed
         adrl dSoundOn
         adrl dOptSel
         adrl dPtrX
         adrl dPtrY
         adrl dPtrOff
         adrl dPtrOn
         adrl dMusOn
         adrl dMusState
         adrl dMusOk
         adrl dMusBad
         adrl dMusBuf
         adrl dMusTotal
         adrl dMusTick16
         adrl dMusRead
         adrl dMusGuard
         adrl dMLogIdx
         adrl dMLogS
         adrl dTrN
         adrl dTrB
         adrl dTrY0
         adrl dTrY1
         adrl dTrTick
                  adrl   dMusRestart
                   adrl   dEmOn
                   adrl   dEmBank
         END
