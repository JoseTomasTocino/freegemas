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
         dsk ../build/FREEGEM_MTEST.S16
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

* Keep the loader-set D and S untouched. With no direct-page/stack load
* segment in the OMF, GS/OS allocates a 4KB block: D = first byte, S = last
* byte (GS/OS Reference ch.2). The DP page (D..D+$FF) hosts the digit
* blitter's slots $F0-$F3; the stack grows down from the top of the same
* block, thousands of bytes away. The old prologue moved S below the block,
* sending the stack through unallocated bank-00 memory in violation of the
* documented contract.

* Display stays in the GS/OS text mode (NEWVIDEO $41) while the scene streams,
* so the old palette never shows new pixels. SHADOWR matches TimePilot-IIgs.
         sep #$20
         longa off
         lda #$00
         sta >SHADOWR               ; shadowing ON, as TimePilot-IIgs
         lda #$41
         sta >NEWVIDEO              ; SHR display off, bank 01 still writable
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
         jsr loadSounds           ; DOC waves ride through SCREEN before the title
         lda #nmTitle
         sta dPathPtr
         jsr loadScene
         jsr loadHiscore
         jsr installTitlePal
         jsr installScb
         jsr saveTitleMenu
         sep #$20
         longa off
         lda #1
         sta >MILESTONE
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
         sep #$20
         longa off
         lda #7
         sta >MILESTONE
         rep #$20
         longa on
         brl gameExit

* Main loop: VSYNC edge drives the 1-second timer; mouse polling runs first so
* every state handler sees this frame's pointer/button; WASD moves the
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
         lda dOver
         bne overKeys
         sep #$20
         longa off
         lda #8
         sta >MILESTONE
         lda >KBD
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
* accepted; the click restarts like Space does.
overKeys sep #$20
         longa off
         lda #8
         sta >MILESTONE
         lda >KBD
         bmi overKeyDown
         rep #$20
         longa on
         lda dMouseClick
         bne ovClick
         brl gameExit
ovClick  stz dMouseClick
         jsr resetGame
         brl gameExit
overKeyDown
         sep #$20               ; assembler must know A is 8-bit here too,
         longa off              ; otherwise cmp #$20 becomes a 3-byte BRK
         sta >KBDSTRB
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
         sta >KBDSTRB
         and #$7F
         cmp #$1B                ; ESC returns to the title menu
         bne notEsc
         brl toTitle
notEsc   cmp #$20                ; Space selects a gem / swaps an adjacent pair
         beq isSpace
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
         sep #$20
         longa off
         lda #$41                ; display off / linear map, as GS/OS expects
         sta >NEWVIDEO
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
ffLoop   sta >SCREEN,x
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
vsyncPoll anop
         sep #$20
         longa off
         lda >VERTFLAG
         bmi vsHigh
         stz dVstate
         bra vsOut
vsHigh   lda dVstate
         beq vsFirst
         bra vsOut
vsFirst  lda #1
         sta dVstate
         rep #$20
         longa on
         lda dMusTick16         ; free-running music clock in 1/16 frames
         clc
         adc #16
         sta dMusTick16
         lda dState             ; only a running game counts the clock down
         cmp #1
         bne vsPollDone
         inc dTick60
         lda dTick60
         cmp #60
         bcc vsPollDone
         lda #0
         sta dTick60
         lda dMode              ; Endless has no timer: never counts down
         bne vsPollDone
         lda dTimeLeft
         beq vsPollDone
         dec dTimeLeft
         jsr drawTime
         lda dTimeLeft
         bne vsPollDone
         jsr gameOver           ; 0:00 -> overlay, input becomes Space/ESC only
vsPollDone
         rts
* Every exit leaves the accumulator in 16-bit mode: callers assume it, and
* `longa on` here keeps the assembler's immediate-size tracking in step.
vsOut    rep #$20
         longa on
         rts

*-----------------------------------------------------------------------------
* Space: first press marks a gem, second press on an adjacent gem swaps them.
* The mark frame uses the blue panel slot; the white frame follows the cursor.
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
         jsr swapCells            ; tentative swap
         jsr scanBoard
         lda dMatchCnt
         bne swapResolve
* No match anywhere: undo, as the original rejects a non-winning swap.
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
         lda dCursor              ; the frame follows the cursor again
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
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
* White follows the cursor; blue marks the gem selected for a swap.
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
* ADB mouse (M3).  $C024 returns one movement byte per read; $C027 bit 1 says
* whether the next read is X (1) or Y (0) and bit 7 says the register holds a
* fresh pair.  Byte layout (Cortland ADB ERS, see a2gsemu-ia Docs/ADB.md):
*   bit 7    button, 1 = up / 0 = pressed (X byte carries button 1, the Y byte
*            carries button 0 = left, which is the only button on an Apple
*            Desktop Mouse)
*   bit 6    delta sign, 1 = negative
*   bits 5-0 magnitude, 0-63
* GS/OS enables the mouse interrupt and its own handler eats the pair, so the
* game clears bit 6 of $C027 while it owns the pointer and restores the saved
* status before quitting.  Polling (not the interrupt) drives the whole game.
*-----------------------------------------------------------------------------
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
         rts

mouseRestore anop
         rep #$20
         longa on
         lda dMouseStat
         and #$00FF
         sep #$20
         longa off
         sta >ADBSTAT            ; hand the mouse interrupt back to the Finder
         rep #$20
         longa on
         rts

* Take at most two bytes per poll and fold each one into the pointer.
* $C027 bit 7 says a byte is waiting; bit 1 says which axis it belongs to.
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
         lda dMLogIdx            ; DEBUG: advance the status ring
         inc a
         and #$001F
         sta dMLogIdx
         lda dMEvReady
         beq mpNoEv
         stz dMEvReady
         lda dMEvX
         sta dMByteX
         lda #1
         sta dMNewX
         lda dMEvY
         sta dMByteY
         lda #1
         sta dMNewY
         bra mpHave
mpNoEv   rep #$20
         longa on
         rts

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
         and #$003F
         eor #$FFFF
         inc a
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
         and #$003F
         eor #$FFFF
         inc a
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
mpNoBtnY lda dMDx
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
mpOut    rep #$20
         longa on
         rts

* Map dMouseX/dMouseY to a board cell.  Carry set = on the board, dMCell holds
* row*8+col.  The board is 8 cells of 26x22 at (96,14).
mouseHit anop
         lda dMouseX
         sec
         sbc #B_X0
         bcc mhMiss
         cmp #B_W
         bcs mhMiss
         sta dMTmp
         stz dMCol
mhColLp  lda dMTmp
         cmp #B_CW
         bcc mhColOk
         sec
         sbc #B_CW
         sta dMTmp
         inc dMCol
         bra mhColLp
mhColOk  lda dMouseY
         sec
         sbc #B_Y0
         bcc mhMiss
         cmp #B_H
         bcs mhMiss
         sta dMTmp
         stz dMRow
mhRowLp  lda dMTmp
         cmp #B_CH
         bcc mhRowOk
         sec
         sbc #B_CH
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
         jsr mouseHit
         bcc mcOut
         lda dMCell
         cmp dCursor
         beq mcAct
         sta dNewCursor
         jsr cursorMove
mcAct    brl spaceKey
mcOut    brl gameExit

*-----------------------------------------------------------------------------
* Visible mouse pointer: a 7x8 masked sprite painted straight into SHR.
*
* No hardware sprite exists, so ptrStep keeps three 28-byte row blocks per
* frame:  dPtrSave  = the bytes that were under the arrow
*         dPtrPaint = the bytes the arrow wrote
*         dPtrKeep/dPtrVal = the 4bpp mask (0 = keep that pixel, 1 = paint it)
*
* The restore is compare-guarded: a byte is only written back when it still
* holds the exact value the arrow painted. Anything the game repainted on top
* of the arrow (cell redraw, HUD, full-screen scene) is therefore left alone.
*-----------------------------------------------------------------------------
PTR_BYTES equ 28
PTR_ROWS  equ 7

ptrStep anop
         lda dPtrOn
         beq psSnap
         lda dPtrOff
         sta dDst
         ldy #0
psEraseR ldx dDst
         lda #4
         sta dPrtCnt
psEraseB sep #$20
         longa off
         lda >SCREEN,x
         cmp dPtrPaint,y
         bne psNoPut
         lda dPtrSave,y
         sta >SCREEN,x
psNoPut  rep #$20
         longa on
         inx
         iny
         dec dPrtCnt
         bne psEraseB
         lda dDst
         clc
         adc #160
         sta dDst
         cpy #PTR_BYTES
         bne psEraseR

* Clamp to the screen and align the box on an even pixel (the arrow tip then
* sits at x or x-1, which the eye cannot tell apart).
psSnap   lda dMouseX
         cmp #314
         bcc psXOk
         lda #313
psXOk    and #$FFFE
         sta dPtrX
         lda dMouseY
         cmp #194
         bcc psYOk
         lda #193
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
         lda #4
         sta dPrtCnt
psPaintB sep #$20
         longa off
         lda >SCREEN,x
         sta dPtrSave,y
         and dPtrKeep,y
         ora dPtrVal,y
         sta >SCREEN,x
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
         cpy #PTR_BYTES
         bne psPaintR
         lda #1
         sta dPtrOn
         rts

* 8x7 arrow, black outline + white body. Each row is four bytes (eight
* pixels); a keep nibble of $F means "leave the screen pixel alone".
dPtrKeep db $0F,$FF,$FF,$FF, $00,$FF,$FF,$FF, $00,$0F,$FF,$FF
         db $00,$00,$FF,$FF, $00,$00,$0F,$FF, $00,$00,$FF,$FF
         db $00,$FF,$FF,$FF
dPtrVal  db $00,$00,$00,$00, $10,$00,$00,$00, $11,$00,$00,$00
         db $11,$10,$00,$00, $11,$11,$00,$00, $11,$10,$00,$00
         db $11,$00,$00,$00

* Title menu: the pointer selects the item under it and a click chooses it.
titleMouse anop
         lda dMouseX
         cmp #60
         bcc tmOut
         cmp #264
         bcs tmOut
         lda dMouseY
         cmp #92
         bcc tmOut             ; above the first bar
         cmp #200
         bcs tmOut
         stz dMTmp             ; menu index under the pointer
         lda #1
         sta dMenuIdx          ; menuYTab is a word table: scan the rest
tmLp     lda dMenuIdx
         cmp #MENU_ITEMS
         beq tmHit
         asl a
         tax
         lda menuYTab,x
         sec
         sbc #4
         cmp dMouseY
         bcs tmNext
         lda dMenuIdx
         sta dMTmp
tmNext   inc dMenuIdx
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
fhCell   lda dHCell
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
gbSettle jsr scanBoard
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
         jsr clearHint
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
         jsr drawBoard            ; also repaints over the game-over panel
         lda dCursor
         jsr setFrameCell
         jsr frameWhite
         jsr drawFrame
         rts

*-----------------------------------------------------------------------------
* Game over: dark panel inside the board rectangle (so a plain drawBoard can
* restore it) with heading, final score and the restart/quit keys.
*-----------------------------------------------------------------------------
gameOver anop
         lda #1
         sta dOver
         lda #$FFFF
         sta dSelCell
         jsr clearHint           ; green hint frames must not survive game over
         lda #$0000              ; black: uniform on every scanline band
         sta dFillWord
         lda #104
         sta dFillX
         lda #296
         sta dFillX1
         lda #72
         sta dFillY0
         lda #162
         sta dFillY1
         jsr fillRect
         lda #2
         sta dTScale
         lda #80
         sta dTextY
         lda #147
         sta dTextX
         lda #1
         ldx #strOver
         jsr drawText
         lda #1
         sta dTScale
         lda #104
         sta dTextY
         lda #185
         sta dTextX
         lda #1
         ldx #strScore
         jsr drawText
         jsr gameOverScore
         lda #1
         sta dTScale              ; gameOverScore left the scale at 2
         lda #144
         sta dTextY
         lda #128
         sta dTextX
         lda #1
         ldx #strAgain
         jsr drawText
         lda #152
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
         lda #114
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
* dNumVal -> 5 digits in dNumBuf; leading zeros blanked, dNumLen = first index
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
         sbc #FONT_FIRST
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
         lda >SCREEN,x
         and #$0F
         ora dTColorHi
         sta >SCREEN,x
         rep #$20
         longa on
         rts
ppOdd    sep #$20
         longa off
         lda >SCREEN,x
         and #$F0
         ora dTColorLo
         sta >SCREEN,x
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
         sta >SCREEN,x
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
* The picture is read as eight 4000-byte sequential slices with one musStep call
* between slices.  A single 32 KB Read blocks the main loop for ~23 frames
* (0.38 s on GSSquared) and the DOC music table is only 21.97 frames long, so
* every screen change used to run the music dry for up to 0.38 s.  Sequential
* reads advance the file mark just like the MUSIC.PCM streamer relies on, and
* the per-slice musStep keeps the standby buffer queued (see musStep/MUS_GUARD).
*-----------------------------------------------------------------------------
LOAD_SLICES equ 8
LOAD_CHUNK  equ 4000
* musStep moves only MUS_CHUNK (128 B = 1/96 s of audio) per call, which is
* barely break-even against one GS/OS read, so a scene load still ran the
* 4096-byte music table dry and left a ~0.16 s hole at every screen change.
* musPump calls it enough times to cover a whole 4K table between disk reads;
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
         lda #LOAD_CHUNK
         sta pbRead+8           ; length of one slice (long: high word stays 0)
         stz pbRead+10
         stz dLoadOfs
         stz dLoadErr
         lda #LOAD_SLICES
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
         adc #LOAD_CHUNK
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
* at boot; SCREEN ($012000) is the staging buffer, and the title scene load
* right after overwrites it, so nothing stays resident in main memory.
* playSound only reprograms oscillator registers, which costs a few hundred
* cycles and is safe to call from the game loop.
*
* DOC RAM map (the $C0+n wave-size register picks the table length):
*   $0000 SELECT 4K   $1000 FALL 4K    $2000 MATCH1 16K
*   $6000 MATCH2 16K  $A000 MATCH3 16K
*   $E000 MUSIC A 4K   $F000 MUSIC B 4K
* The two music buffers take the rest of the 64 KB; SELECT/FALL only need 4K
* (their waves are 0.14 s and 0.18 s) and that is what paid for them.
*
* Playback rate with eight oscillators enabled (=$E1 0E) is
*   894886/(8+2) * freq / 2^(9+res-size)
* so 4K tables use size 4 / res 0 / freq 4, 8K tables size 5 / res 1 / freq 4
* and 16K tables size 6 / res 0 / freq 1; all land on 11186 Hz, the rate
* build_iigs_sounds.py resamples to.
*
* Oscillators 0/1 play SELECT, 2/3 FALL and 4/5 MATCHx, so a match can ring over
* a fall (and over the next select) instead of cutting it off; the original
* never mixes, but a single pair would truncate every effect. Each pair carries
* both DOC channel bits (control $02 on the even oscillator, $12 on the odd one)
* so the effect is audible on both outputs.
*-----------------------------------------------------------------------------
audioInit anop
         sep #$20
         longa off
         lda #$0F                 ; register mode, main volume nibble 15
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
* wave RAM, bit5 auto-increments the address after every $C03D write; the low
* nibble is the main volume, so it must stay non-zero.
docUpload anop
         sep #$20
         longa off
         lda #$6F                 ; wave RAM + auto-increment + volume 15
         sta >$01C03C
         lda dDocBase
         sta >$01C03E
         lda dDocBase+1
         sta >$01C03F
         ldx #0
duLoop   lda >SCREEN,x
         sta >$01C03D
         inx
         cpx dSndLen
         bcc duLoop
* Read three bytes of the wave RAM back through $C03D (the port is a one-access
* pipeline: the first read returns the previous latch, the second the byte at
* the current address) and compare them with the source in SCREEN. dSndOk /
* dSndBad are the socket harness proof that the upload really landed.
         lda #$4F                 ; wave RAM, no auto-increment, volume 15
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
         lda #$0F                 ; back to register mode, keep volume 15
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

* Compare DOC RAM[X] with the staged source byte SCREEN[X]; bump dSndOk/dSndBad.
dvCheck anop
         phx
         jsr docSample
         sep #$20                 ; docSample exits 16-bit; the compare is a byte
         longa off
         sta dSndByte
         plx
         lda >SCREEN,x
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
* buffer; dPathPtr must be re-set by the caller afterwards.
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
         cmp #AUD_ITEMS
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
psMatch  lda #4                   ; matchx: pair 4/5
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
         lda #$FF
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
         lda #$00FF
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

* Match effects rotate through MATCH1-3 like the original.
matchSound anop
         lda dSndRot
         sta dSndTmp
         inc dSndRot
         lda dSndRot
         cmp #3
         bcc msPlay
         stz dSndRot
msPlay   lda dSndTmp
         clc
         adc #2
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
* streamed from disk: oscillators 6/7 play a 4K buffer (0.366 s at 11186 Hz)
* while the *other* 4K buffer ($E000 / $F000) is refilled from disk in 128-byte
* slices, one slice per pass of the loop, so a refill never stalls the game loop.  Every
* buffer switch re-programs both oscillators, so the swap is an exact restart at
* the new base and the two buffers alternate for as long as the music plays.
*
* Timing is kept in 1/16 frame units of the VSYNC counter (dMusTick16) because a
* buffer is 21.97 frames at 60 Hz: adding MUS_FRAC per switch keeps every switch
* within a few samples of the end of the playing buffer.  The counter wraps
* every 68 s, which is harmless: dMusEnd is always re-based on the live count,
* and the signed difference never comes close to 32768.
*-----------------------------------------------------------------------------
MUS_LEN    equ 4096            ; one music buffer, 0.366 s at 11186 Hz
* The DOC data port is slow: every $C03D write costs ~90 cycles, so copying 512
* bytes in one call stalls the main loop for ~46 000 cycles (a whole frame).
* That burst ran the input poll at ~60 Hz and froze the pointer/menu for ~130 ms
* while a 4 KB buffer refilled.  128 bytes per call spreads the same bandwidth
* evenly over 32 calls (~0.18 s), keeps the loop at a few milliseconds and polls
* the ADB mouse every loop instead of once per frame.
MUS_CHUNK  equ 128             ; bytes copied into the standby buffer per call
MUS_FRAC   equ 352             ; 4096/11186*60*16 = 351.5 sixteenths of a frame
MUS_GUARD  equ 6               ; only trust the halt flag this many calls after a
*                              ; restart: the bit also reads set for a moment then
MUS_EARLY  equ 65440           ; 65536-96: the halt flag is honoured within 6 frames
*                              ; of the expected end (the tick runs a little slow,
*                              ; so the flag usually shows up 1-3 frames "early")
MUS_OSC    equ 6               ; oscillators 6/7 carry the music on both channels
MUS_BUF_A  equ $E000
MUS_BUF_B  equ $F000
MUS_VOL    equ $60             ; music is a background layer, not a foreground FX
                               ; ($60 not $80: with 8x asset gain the old level
                               ; clipped the DOC mix and buried the sound effects)

* Start the music at the top of MUSIC.PCM if it is enabled and not already
* running.  Called once at boot and again when Options turns Music back on.
musStart anop
         lda dMusOn
         bne msOn
         rts
msOn     lda dMusState
         beq msBegin
         rts
msBegin  jsr musOpen
         bcc msOpened
         brl msBad
msOpened
         stz dMusBuf
         jsr musFillStage       ; first 4K of PCM into the staging buffer
         bcc msFirst
         brl msBadClose
msFirst
         lda #1                 ; "standby" is A for this one full copy
         sta dMusBuf
         jsr musCopyAll
         stz dMusBuf            ; A is the buffer that plays
         jsr musPlay
         lda dMusTick16
         clc
         adc #MUS_FRAC
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
* musStep moves MUS_CHUNK (128 B = 1/96 s of audio) per call; while a GS/OS read
* blocks the main loop the buffer needs several calls just to stay level.
* musPump makes eight calls (1024 B) per slice, 8 KB over the eight slices of a
* scene load, and once dMusTotal = MUS_LEN every extra call returns at once, so
* pumping from loadScene costs nothing in steady state.
MUS_PUMP_N equ 8

musPump anop
         php
         ldx #MUS_PUMP_N
mppLoop  phx
         jsr musStep
         plx
         dex
         bne mppLoop
         plp
         rts

musStep anop
         lda dMusState
         bne mstOn
         rts
mstOn    inc dMusGuard         ; calls serviced since the current table started
         jsr musHaltChk        ; the oscillator itself says the table is done
         bcc mstTick
         inc dMusHalt           ; harness: how often the end-of-table flag was seen
         lda dMusGuard
         cmp #MUS_GUARD         ; ignore the short "halted" blip right after start
         bcs mstSwap
         lda dMusTick16
         sec
         sbc dMusEnd
         cmp #MUS_EARLY         ; only trust it inside the last few frames ...
         bcs mstSwap
* ... because the flag also reads set for a moment right after a restart.
mstTick  lda dMusTick16
         sec
         sbc dMusEnd
         bmi mstFill            ; signed difference: still inside the buffer
         cmp #16                ; one frame of slack for the halt flag to appear
         bcc mstFill
mstSwap  jsr musSwitch
         rts
mstFill  lda dMusTotal
         cmp #MUS_LEN
         bcs mstOut
         jsr musChunk
mstOut   rts

* Carry set = oscillator 6 has run off the end of its 4K table and halted.
* This is the *real* end of the buffer; dMusTick16 only approximates it, and it
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
         lda #$0F               ; register mode, volume 15 (idempotent)
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
* Starved (a disk read failed): fall back to a clean restart from the top.
         jsr musStop
         jsr musStart
         rts
mswGo    lda dMusBuf
         eor #1
         sta dMusBuf            ; the standby becomes the playing buffer
         jsr musBase
         jsr musPlay
         lda dMusTick16
         clc
         adc #MUS_FRAC
         sta dMusEnd
         inc dMusOk
         jsr musFillStage       ; next 4K for the buffer that just stopped
         bcc mswOk
         brl mswBad
mswOk    stz dMusTotal
         stz dMusChunk
         rts
mswBad   inc dMusBad
         jsr musStop
         rts

* dMusBase = DOC base of the playing buffer (dMusBuf), or of the standby when
* musStandby computed the inverted index.
musBase anop
         lda dMusBuf
         beq mbA
         lda #MUS_BUF_B
         bra mbSet
mbA      lda #MUS_BUF_A
mbSet    sta dMusBase
         rts

musStandby anop
         lda dMusBuf
         eor #1
         beq msbA
         lda #MUS_BUF_B
         bra msbSet
msbA     lda #MUS_BUF_A
msbSet   sta dMusBase
         rts

* Program oscillators 6/7 for dMusBase and start them: even oscillator on
* channel A ($02), odd on channel B ($12), 4K table ($20) at 11186 Hz (freq 4).
* The DOC register number is the oscillator index (X), not the wave RAM
* address; only the $80 pointer byte comes from dMusBase+1.  Using the base
* address as the register number programmed oscillators 0/1 instead, which is
* exactly what the earlier silent run did.
musPlay anop
         stz dMusGuard
         sep #$20
         longa off
         ldx #MUS_OSC
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
         lda #MUS_VOL
         sta >$01C03D
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
         cpx #MUS_OSC+2
         bcc mplLoop
         lda #$A6               ; control register of oscillator 6
         sta >$01C03E
         lda #$02               ; start, channel A
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
         lda #$6F               ; wave RAM + auto-increment + volume 15
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
         lda #$0F               ; back to the oscillator register file
         sta >$01C03C
         rep #$20
         longa on
         lda dMusNew
         sta dMusTotal
         rts

* Whole-buffer copy, used once at start; musChunk advances dMusTotal itself.
* 32 slices of 128 bytes make up MUS_LEN (Merlin32 has no parentheses).
musCopyAll anop
         ldy #8
mcCopy   phy
         jsr musChunk
         ply
         dey
         bne mcCopy
         rts

* Fill the staging buffer with MUS_LEN bytes; at end of file close and reopen
* so the track loops forever.  Carry set on failure.
musFillStage anop
         lda dMusRef
         beq mfsFail
         sta pbMusRead+2
         lda #MUS_LEN
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
         cmp #MUS_LEN
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
         cmp #MUS_LEN
         bcs mfsOk
         brl mfsFail
mfsOk    clc
         rts
mfsFail  sec
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
         jsr musClose
         rts

*-----------------------------------------------------------------------------
* High scores: HISCORE.DAT holds two 16-bit words, Time Trial then Endless.
* loadHiscore runs once at boot (before SHR is on); saveHiscore rewrites the
* file whenever a round beats the stored best. The file is shipped by
* `make disk`, so the normal path is Open-with-write; Create is the fallback for
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
* 3 Open/Read failed; $019CF8 = value read back).
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

* A new best is announced on the Game Over panel; equal scores do not count.
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

* Game Over panel: "BEST n" or "NEW BEST n", centred at x=160, scale 1, y=132.
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
         lda #160
         sec
         sbc dTmpW
         sta dTextX
         lda #1
         sta dTScale
         lda #132
         sta dTextY
         lda #1
         ldx dBestPtr
         jsr drawText            ; leaves dTextX just past the prefix
         lda #132
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
         sta >PALBASE,x
         inx
         inx
         cpx #384
         bne itpLp
         rts

installHowtoPal anop
         ldx #0
ihpLp    lda >howtopals,x
         sta >PALBASE,x
         inx
         inx
         cpx #384
         bne ihpLp
         rts

installGamePal anop
         ldx #0
igpLp    lda >gempals,x
         sta >PALBASE,x
         inx
         inx
         cpx #384
         bne igpLp
         rts

installScb anop
         sep #$20
         longa off
         ldx #0
iscLp    lda scbtab,x
         sta >SCB,x
         inx
         cpx #200
         bne iscLp
         rep #$20
         longa on
         rts

* GS/OS hands the desktop palette and scanline table back to the Finder by
* itself only if the application restores them; without this the desktop is
* redrawn in the last game palette (seen as a black screen with a stray icon).
saveScreenSet anop
         ldx #0
sssPal   lda >PALBASE,x
         sta >dSavePal,x
         inx
         inx
         cpx #384
         bne sssPal
         ldx #0
sssScb   lda >SCB,x
         sta >dSaveScb,x
         inx
         inx
         cpx #200
         bne sssScb
         rts

restoreScreenSet anop
         ldx #0
rssPal   lda >dSavePal,x
         sta >PALBASE,x
         inx
         inx
         cpx #384
         bne rssPal
         ldx #0
rssScb   lda >dSaveScb,x
         sta >SCB,x
         inx
         inx
         cpx #200
         bne rssScb
         rts

shrOn anop
         sep #$20
         longa off
         lda #$E1
         sta >NEWVIDEO
         rep #$20
         longa on
         rts

* Menu art + menu. Re-streaming the art is how the previous highlight bar is
* erased (a GS/OS read of 32000 bytes takes a few frames).
showTitleScreen anop
         lda #nmTitle
         sta dPathPtr
         jsr loadScene
         jsr installTitlePal
         jsr installScb
         jsr saveTitleMenu
         jsr titleDraw
         jsr shrOn
         rts
*-----------------------------------------------------------------------------
* The title menu is redrawn on every arrow/hover move.  Reading TITLE.RAW from
* disk each time made the cursor feel sluggish, so the 110x102-byte menu band is
* saved once and copied back to the screen before titleDraw repaints it.
*-----------------------------------------------------------------------------
TITLE_SAVE_OFF   equ 14110       ; 88 rows * 160 + 30 (x = 60 px)
TITLE_SAVE_ROWS  equ 110
TITLE_SAVE_BYTES equ 102

saveTitleMenu anop
         rep #$20
         longa on
         ldx #TITLE_SAVE_OFF
         ldy #0
         lda #TITLE_SAVE_ROWS
         sta dReadRow
         longa on
svRow    lda #51
         sta dColCnt
svWord   lda >SCREEN,x
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
         dec dReadRow
         bne svRow
         rts

restoreTitleMenu anop
         rep #$20
         longa on
         ldx #TITLE_SAVE_OFF
         ldy #0
         lda #TITLE_SAVE_ROWS
         sta dReadRow
restRow  lda #51
         sta dColCnt
restWord lda dTitleSave,y
         sta >SCREEN,x
         inx
         inx
         iny
         iny
         dec dColCnt
         bne restWord
         txa
         clc
         adc #58
         tax
         dec dReadRow
         bne restRow
         rts

titleRedrawMenu anop
         rep #$20
         longa on
         lda dMenuPrev
         cmp dMenuSel
         bne trmGo
         rts                    ; nothing moved: leave the screen alone
trmGo    inc dTrN
         lda #2
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

* Full repaint: only needed when something else (the Options screen) painted
* over the menu band.  Restores the whole cached band, then draws bar+labels.
titleFullRedraw anop
         jsr restoreTitleMenu
         jsr titleDraw
         rts

* One menu row covers 22 scanlines (y = menuYTab-4 .. +18) at x = 60..264, i.e.
* 51 words per row.  dTitleSave starts at y = 88, so a row band is a contiguous
* 22*102-byte slice of it: 2244 bytes instead of the old 11 220-byte restore.
TITLE_BAND_ROWS equ 22

* A = menu item index.  Copy that item's 22-row band from dTitleSave back onto
* SCREEN.  dSaveOff = (y-88)*102; X = y*160+60; Y walks the saved band.
titleRestoreBand anop
         rep #$20
         longa on
         inc dTrB
         asl a
         tax
         lda menuYTab,x
         sec
         sbc #4
         sta dRowY
         sta dReadRow
         sec
         sbc #88
         sta dTmpA              ; (y - 88)
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
         lda #TITLE_BAND_ROWS
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
         lda #nmHowto
         sta dPathPtr
         jsr loadScene
         jsr installHowtoPal
         jsr installScb
         jsr howtoDraw
         jsr shrOn
         rts

* Time Trial streams SCENE4.RAW; Endless streams SCENE4E.RAW, whose art has no
* "Time left" header or panel.
startGame anop
         lda dMode
         beq sgTimeTrial
         lda #nmSceneE
         bra sgLoad
sgTimeTrial
         lda #nmScene
sgLoad   sta dPathPtr
         jsr loadScene
         jsr installGamePal
         jsr installScb
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

* Menu: amber bar behind the selected item, white labels centred at scale 2
* (width 12*len-2, so x = 161-6*len). fillRect needs an even x0 and a width
* divisible by 4: 60..264 is 51 words.
titleDraw anop
         lda #2
         sta dTScale
         jsr titleBar
         lda #0
         sta dMenuIdx
tdLoop   jsr titleLabel
         inc dMenuIdx
         lda dMenuIdx
         cmp #MENU_ITEMS
         bne tdLoop
         lda dMenuSel
         sta dMenuPrev
         jsr drawHiLine
         rts

* Amber bar behind the selected item: rows menuYTab-4 .. menuYTab+18, x=60..264.
titleBar anop
         lda dMenuSel
         asl a
         tax
         lda menuYTab,x
         sec
         sbc #4
         sta dFillY0
         lda dMenuSel
         asl a
         tax
         lda menuYTab,x
         clc
         adc #18
         sta dFillY1
         lda #60
         sta dFillX
         lda #264
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

* Centred white label for the item in dMenuIdx, scale from dTScale (2).
titleLabel anop
         lda dMenuIdx
         asl a
         tax
         lda menuStrTab,x
         tax
         jsr strLen
         sta dNumTmp
         asl a
         sta dTmpW              ; 2*len
         asl a
         asl a                  ; 8*len
         sec
         sbc dTmpW              ; 6*len
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
         lda #185
         sta dTextX
         lda #6
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
         cmp #HOWTO_LINES
         bne hdLoop
         lda #1
         sta dTScale
         lda #8
         sta dTextX
         lda #188
         sta dTextY
         lda #1
         ldx #strHtBack
         jsr drawText
         rts

*-----------------------------------------------------------------------------
* State handlers. The title accepts W/S (wrap), Space/Return and ESC; the
* how-to-play screen returns to the menu on any key.
*-----------------------------------------------------------------------------
toTitle
         rep #$20
         longa on
         lda #0
         sta dState
         sta dMenuSel
         jsr showTitleScreen
         brl gameExit

stateTitle
         sep #$20
         longa off
         lda >KBD
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
         sta >KBDSTRB
         and #$7F
         cmp #$1B                ; ESC quits the program from the menu
         bne tkNotEsc
         brl quitGame
tkNotEsc cmp #$20
         beq tkChoose
         cmp #$0D                ; Return
         beq tkChoose
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
         lda #MENU_ITEMS
         dec a
         sta dMenuSel
         bra tkRedraw
tkUpDec  dec dMenuSel
         bra tkRedraw
tkDown   rep #$20
         longa on
         lda dMenuSel
         inc a
         cmp #MENU_ITEMS
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
         lda >KBD
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
         sta >KBDSTRB
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
* Options (original: Timetrial/Endless/How to play?/Options/Exit).
* Music and Fullscreen have no IIGS equivalent (the DOC block has no music
* player yet and SHR is always the full screen), so only the sound toggle is
* offered here; see iigs/AGENTS.md for the recorded omissions.
*-----------------------------------------------------------------------------
showOptions anop
         lda #nmTitle
         sta dPathPtr
         jsr loadScene
         jsr installTitlePal
         jsr installScb
         jsr optionsDraw
         jsr shrOn
         rts

* Three rows in the same slots the title menu uses: Music: On|Off,
* Sound: On|Off, Back.
optionsDraw anop
         lda #2
         sta dTScale
         lda dOptSel
         asl a
         tax
         lda optYTab,x
         sec
         sbc #4
         sta dFillY0
         lda dOptSel
         asl a
         tax
         lda optYTab,x
         clc
         adc #18
         sta dFillY1
         lda #60
         sta dFillX
         lda #264
         sta dFillX1
         lda #$2222
         sta dFillWord
         jsr fillRect
* row 0: Music: On / Off
         lda optYTab
         sta dTextY
         lda dMusOn
         beq odMusOff
         ldx #strMusOn
         bra odMusDraw
odMusOff ldx #strMusOff
odMusDraw jsr centerLabel
* row 1: Sound: On / Off
         lda optYTab+2
         sta dTextY
         lda dSoundOn
         beq odSndOff
         ldx #strSndOn
         bra odSndDraw
odSndOff ldx #strSndOff
odSndDraw jsr centerLabel
* row 2: Back
         lda optYTab+4
         sta dTextY
         ldx #strBack
         jsr centerLabel
         rts
* X = address of a NUL-terminated label, dTextY already set: centre it at
* x = 161 - 6*len like the title menu, at scale 2.
centerLabel anop
         stx dTmpW
         jsr strLen
         sta dNumTmp
         asl a
         sta dTmpA
         asl a
         asl a
         sec
         sbc dTmpA
         sta dOptX
         lda #161
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
         lda >KBD
         bmi soKeyDown
         rep #$20
         longa on
         lda dMouseClick
         beq soOut
         stz dMouseClick
         lda dMouseY
         cmp #110
         bcc soMouseMusic
         cmp #148
         bcc soMouseSound
         lda #2
         sta dOptSel
         jsr optionsDraw
         brl soBack
soMouseMusic
         stz dOptSel
         jsr optToggle
         brl gameExit
soMouseSound
         lda #1
         sta dOptSel
         jsr optToggle
         brl gameExit
soOut    brl gameExit
soKeyDown
         sep #$20
         longa off
         sta >KBDSTRB
         and #$7F
         cmp #$1B                ; ESC leaves Options back to the title
         beq soBack
         cmp #$20
         beq soChoose
         cmp #$0D
         beq soChoose
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
         lda #OPT_ITEMS
         dec a
         sta dOptSel
         bra soRedraw
soUpDec  dec dOptSel
         bra soRedraw
soDown   rep #$20
         longa on
         lda dOptSel
         inc a
         cmp #OPT_ITEMS
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
         cmp #2
         bcs soBack
         jsr optToggle
         brl gameExit
soBack   rep #$20
         longa on
         lda #0
         sta dState
         sta dOptSel
         jsr titleFullRedraw     ; Options art is on screen: restore whole band
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
         bcs otDone             ; Back: nothing to toggle
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
strHtTitle
         db $48,$6F,$77,$20,$74,$6F,$20,$70
         db $6C,$61,$79
         db $00
strHtBack
         db $50,$72,$65,$73,$73,$20,$61,$6E
         db $79,$20,$6B,$65,$79,$20,$74,$6F
         db $20,$67,$6F,$20,$62,$61,$63,$6B
         db $00
hs01
         db $54,$68,$65,$20,$6F,$62,$6A,$65
         db $63,$74,$69,$76,$65,$20,$6F,$66
         db $20,$74,$68,$65,$20,$67,$61,$6D
         db $65,$20,$69,$73,$20,$74,$6F
         db $00
hs02
         db $73,$77,$61,$70,$20,$6F,$6E,$65
         db $20,$67,$65,$6D,$20,$77,$69,$74
         db $68,$20,$61,$6E,$20,$61,$64,$6A
         db $61,$63,$65,$6E,$74
         db $00
hs03
         db $67,$65,$6D,$20,$74,$6F,$20,$66
         db $6F,$72,$6D,$20,$61,$20,$68,$6F
         db $72,$69,$7A,$6F,$6E,$74,$61,$6C
         db $20,$6F,$72
         db $00
hs04
         db $76,$65,$72,$74,$69,$63,$61,$6C
         db $20,$63,$68,$61,$69,$6E,$20,$6F
         db $66,$20,$74,$68,$72,$65,$65,$20
         db $6F,$72,$20,$6D,$6F,$72,$65
         db $00
hs05
         db $67,$65,$6D,$73,$2E
         db $00
hs06
         db $43,$6C,$69,$63,$6B,$20,$74,$68
         db $65,$20,$66,$69,$72,$73,$74,$20
         db $67,$65,$6D,$20,$61,$6E,$64,$20
         db $74,$68,$65,$6E
         db $00
hs07
         db $63,$6C,$69,$63,$6B,$20,$74,$68
         db $65,$20,$67,$65,$6D,$20,$79,$6F
         db $75,$20,$77,$61,$6E,$74,$20,$74
         db $6F,$20,$73,$77,$61,$70
         db $00
hs08
         db $69,$74,$20,$77,$69,$74,$68,$2E
         db $20,$49,$66,$20,$74,$68,$65,$20
         db $6D,$6F,$76,$65,$6D,$65,$6E,$74
         db $20,$69,$73
         db $00
hs09
         db $63,$6F,$72,$72,$65,$63,$74,$2C
         db $20,$74,$68,$65,$79,$20,$77,$69
         db $6C,$6C,$20,$73,$77,$61,$70,$20
         db $61,$6E,$64,$20,$74,$68,$65
         db $00
hs10
         db $63,$68,$61,$69,$6E,$65,$64,$20
         db $67,$65,$6D,$73,$20,$77,$69,$6C
         db $6C,$20,$64,$69,$73,$61,$70,$70
         db $65,$61,$72,$2E
         db $00
hs11
         db $42,$6F,$6E,$75,$73,$20,$70,$6F
         db $69,$6E,$74,$73,$20,$61,$72,$65
         db $20,$67,$69,$76,$65,$6E,$20,$77
         db $68,$65,$6E,$20,$6D,$6F,$72,$65
         db $00
hs12
         db $74,$68,$61,$6E,$20,$74,$68,$72
         db $65,$65,$20,$69,$64,$65,$6E,$74
         db $69,$63,$61,$6C,$20,$67,$65,$6D
         db $73,$20,$61,$72,$65
         db $00
hs13
         db $66,$6F,$72,$6D,$65,$64,$2E,$20
         db $53,$6F,$6D,$65,$74,$69,$6D,$65
         db $73,$20,$63,$68,$61,$69,$6E
         db $00
hs14
         db $72,$65,$61,$63,$74,$69,$6F,$6E
         db $73,$2C,$20,$63,$61,$6C,$6C,$65
         db $64,$20,$63,$61,$73,$63,$61,$64
         db $65,$73,$2C,$20,$61,$72,$65
         db $00
hs15
         db $74,$72,$69,$67,$67,$65,$72,$65
         db $64,$2C,$20,$77,$68,$65,$72,$65
         db $20,$63,$68,$61,$69,$6E,$73,$20
         db $61,$72,$65
         db $00
hs16
         db $66,$6F,$72,$6D,$65,$64,$20,$62
         db $79,$20,$74,$68,$65,$20,$66,$61
         db $6C,$6C,$69,$6E,$67,$20,$67,$65
         db $6D,$73,$2E
         db $00
hs17
         db $43,$61,$73,$63,$61,$64,$65,$73
         db $20,$61,$72,$65,$20,$61,$77,$61
         db $72,$64,$65,$64,$20,$77,$69,$74
         db $68,$20,$62,$6F,$6E,$75,$73
         db $00
hs18
         db $70,$6F,$69,$6E,$74,$73,$2E
         db $00

htStrTab
         dw hs01,hs02,hs03,hs04,hs05,hs06
         dw hs07,hs08,hs09,hs10,hs11,hs12
         dw hs13,hs14,hs15,hs16,hs17,hs18
htYTab
         dw 28,36,44,52,60
         dw 72,80,88,96,104,112
         dw 124,132,140,148,156,164,172

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
* then drops the survivors; this does the same in three pieces:
*   flashMarked  - white frames over every match, held for a few frames
*   animStep     - one frame of gravity (one row per gem) plus refill
*   animCollapse - runs animStep once per 60 Hz frame until the board settles
* Only the cells that change are repainted, so the animation stays cheap.
*-----------------------------------------------------------------------------
FLASH_FRAMES equ 6
ANIM_MAX     equ 24

* Block until the next vertical blank starts (one 60 Hz frame).
waitFrame anop
         sep #$20
         longa off
wfLow    lda >VERTFLAG
         bmi wfLow               ; wait out the blank that is in progress
wfHigh   lda >VERTFLAG
         bpl wfHigh              ; ...then wait for the next one
         rep #$20
         longa on
         jsr musStep             ; animations (flash/collapse, ~24 frames) own
                                 ; the main loop here; without this the music
                                 ; buffer ran dry and the DOC went silent right
                                 ; when a match sound played (M3 續 16)
         rts

flashMarked anop
         lda #0
         sta dRemIdx
fmLoop   lda dRemIdx
         asl a
         tax
         lda dMark,x
         beq fmNext
         lda dRemIdx
         jsr flashCell
fmNext   inc dRemIdx
         lda dRemIdx
         cmp #64
         bcc fmLoop
         lda dFlashFrames
         sta dAnimFrames
fmWait   jsr waitFrame
         dec dAnimFrames
         bne fmWait
         rts

* Fill one whole 26x22 cell with the frame colour ($FF) so the pop is a solid
* white flash rather than a one-pixel outline.  removeMarked repaints the cell
* right after, which erases it again.
flashCell anop
         asl a
         tax
         lda celloff,x
         sta dDst
         lda #22
         sta dRows
fcRow    sep #$20
         longa off
         ldx dDst
         ldy #13
         lda #$11                ; flash to the white slot (1), not slot 15:
                                 ; slot 15 is the per-zone HUD/button colour now
fcByte   sta >SCREEN,x
         inx
         dey
         bne fcByte
         rep #$20
         longa on
         lda dDst
         clc
         adc #160
         sta dDst
         dec dRows
         bne fcRow
         rts

* A = number of 60 Hz frames to wait (dAnimSpeed / harness slow-motion hook).
waitFramesN anop
         sta dWaitCnt
         beq wfnOut
wfnLoop  jsr waitFrame
         dec dWaitCnt
         bne wfnLoop
wfnOut   rts

animCollapse anop
         lda #ANIM_MAX
         sta dAnimFrames
acLoop   jsr animStep
         lda dMoved
         beq acDone
         lda dAnimSpeed
         jsr waitFramesN
         dec dAnimFrames
         bne acLoop
acDone   jsr animFill            ; new gems drop into the empty top cells
         rts

* One frame of gravity.  The decisions use a snapshot of the board so that no
* gem can fall twice in the same frame; animFill adds the new top gems once the
* column has settled.
animStep anop
         stz dMoved
         inc dAnimSteps
         ldx #0
asCopy   lda cellgem,x
         sta dBoardShadow,x
         inx
         inx
         cpx #128
         bcc asCopy
         lda #0
         sta dColBase
asCol    lda #7
         sta dReadRow
asRow    lda dReadRow
         asl a
         asl a
         asl a
         clc
         adc dColBase
         sta dIdx
         asl a
         tax
         lda dBoardShadow,x
         bne asNext
         lda dIdx
         sec
         sbc #8
         asl a
         tay
         lda dBoardShadow,y
         beq asNext
         sta cellgem,x
         lda #0
         sta cellgem,y
         lda dReadRow
         asl a
         asl a
         asl a
         clc
         adc dColBase
         jsr drawCellIndex
         lda dReadRow
         sec
         sbc #1
         asl a
         asl a
         asl a
         clc
         adc dColBase
         jsr drawCellIndex
         inc dMoved
asNext   dec dReadRow
         bne asRow
         inc dColBase
         lda dColBase
         cmp #8
         bcc asCol
         rts

* The survivors have settled: fill the empty top cells of every column with
* fresh gems.  Keeping the refill out of the frame loop means the columns really
* look empty while the match falls, and the new gems appear in one step.
animFill anop
         lda #0
         sta dColBase
afCol    lda #0
         sta dEmpty
         ldx #0
afScan   txa
         asl a
         asl a
         asl a
         clc
         adc dColBase
         asl a
         tay
         lda cellgem,y
         bne afScanNext
         inc dEmpty
afScanNext inx
         cpx #8
         bcc afScan
         lda dEmpty
         beq afNext
         lda #0
         sta dFillRow
afLoop   lda dFillRow
         asl a
         asl a
         asl a
         clc
         adc dColBase
         asl a
         tax
         jsr nextRandom
         sta cellgem,x
         lda dFillRow
         asl a
         asl a
         asl a
         clc
         adc dColBase
         jsr drawCellIndex
         inc dFillRow
         lda dFillRow
         cmp dEmpty
         bcc afLoop
afNext   inc dColBase
         lda dColBase
         cmp #8
         bcc afCol
         rts

*-----------------------------------------------------------------------------
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
         lda dMatchCnt
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
* Clear/score/drop/refill until a rescan finds nothing (cascade), then repaint.
*-----------------------------------------------------------------------------
resolveBoard anop
         lda #1
         sta dCasc
resLoop
         jsr matchSound           ; match1..3, rotating like the original
         jsr flashMarked          ; white pop over the matched gems
         jsr removeMarked
         jsr addScore
         jsr drawScore
         jsr fallSound            ; fall.wav while the survivors drop
         jsr animCollapse         ; one row per frame, fresh gems drop in
         jsr drawBoard
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
         jsr findHint
         lda dHintA
         cmp #$FFFF
         bne resDoneRts
         lda dMode
         bne resEndless
         jsr genBoard            ; no legal swap left: fresh board (original rule)
         jsr drawBoard
         bra resDoneRts
resEndless
         jsr gameOver            ; Endless: no legal swap left ends the game
resDoneRts
         rts

*-----------------------------------------------------------------------------
* Draw every gem (the scene already provides wood, grid and panels).
*-----------------------------------------------------------------------------
drawBoard anop
          lda #0
          sta dCellIdx
boardLoop
          lda dCellIdx
          jsr drawCellIndex       ; wood background first: gem tiles have
                                  ; transparent pixels, so old pixels would
                                  ; otherwise show through (reset / cascade)
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
         asl a
         tax
         lda cellgem,x
         sta dGem
         lda celloff,x
         clc
         adc #161
         sta dScr
         jsr drawGem
         rts

blankCell anop
         asl a
         tax
         lda celloff,x
         sta dDst
         lda dIdxTemp
         lsr a
         lsr a
         lsr a
         clc
         adc dIdxTemp
         and #$0001
         beq bcLight
         lda #$00AA
         bra bcWood
bcLight  lda #$0099
bcWood   sta dWood
         lda #22
         sta dRows
bcRow    sep #$20
         longa off
         ldx dDst
         lda dWood
         ldy #13
bcWord   sta >SCREEN,x
         inx
         dey
         bne bcWord
         rep #$20
         longa on
         lda dDst
         clc
         adc #160
         sta dDst
         dec dRows
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
* Draw the gem selected by dGem at byte offset dScr. Tile records are
* (span<<4 | pad) header bytes followed by span packed bytes; fully
* transparent rows have span 0. Dest always advances 160 bytes per row.
*-----------------------------------------------------------------------------
drawGem anop
         lda dGem
         bne dgDraw
         rts                     ; empty cell (mid-cascade): draw nothing
dgDraw   dec a
         asl a
         tax
         lda gemoff,x          ; offset relative to gemtiles
         tay
         lda dScr
         sta dDst
         lda #GEMROWS
         sta dRows
gemRow   sep #$20
         longa off
         lda gemtiles,y          ; header byte
         iny
         sta dHdr
         and #$0F
         sta dPad
         lda dHdr
         lsr a
         lsr a
         lsr a
         lsr a
         sta dSpan
         lda dSpan
         beq gemNext
         lda dPad
         rep #$20
         longa on
         and #$00FF
         clc
         adc dDst
         tax
gemCopy  sep #$20
         longa off
         lda gemtiles,y
         iny
         sta >SCREEN,x
         inx
         dec dSpan
         bne gemCopy
gemNext  rep #$20
         longa on
         lda dDst
         clc
         adc #160
         sta dDst
         dec dRows
         bne gemRow
dgRts    rts

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
         sta >SCREEN,x
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
         sta >SCREEN,x
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
         lda >SCREEN,x
         and #$0F                ; clear the left pixel, keep its right neighbour
         ora dFrameHi
         sta >SCREEN,x
         lda >SCREEN+12,x
         and #$F0
         ora dFrameLo
         sta >SCREEN+12,x
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
* HUD digits. Score: 6 slots, right edge x=79, y=42, 8px tall. Time: 5 slots,
* right edge x=76, y=78, 15px tall, minutes unpadded + ":SS". Both erase to
* the flat panel-mid slot with a $FF fill, then blit 1bpp masks with the cyan
* slot 14 nibble via read-modify-write (the panels live on score/time rows
* whose slot 14 is the original digit cyan).
*-----------------------------------------------------------------------------
eraseScore anop
         lda #SCORE_LEFT
         lsr a
         sta dEByte              ; first byte of the erase rectangle
         ldx #SCORE_Y
         stx dERow
         lda #SCORE_H
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
         ldy #SCORE_SLOTS * SCORE_PITCH / 2 + 1
esFill   lda #$FF
         sta >SCREEN,x
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
         lda dScore
         sta dVal
         lda #SCORE_RIGHT - SCORE_PITCH + 2
         sta dCharX
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
         lda #SCORE_Y
         sta dMY
dsLoop   jsr div10               ; dQuot = dVal/10, A = remainder
         jsr blitDigit
         lda dCharX
         sec
         sbc #SCORE_PITCH
         sta dCharX
         lda dQuot
         beq dsDone
         sta dVal
         bra dsLoop
dsDone   rts

eraseTime anop
         lda #TIME_LEFT
         lsr a
         sta dEByte
         ldx #TIME_Y
         stx dERow
         lda #TIME_H
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
         ldy #TIME_SLOTS * TIME_PITCH / 2 + 1
etFill   lda #$FF
         sta >SCREEN,x
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
         lda #TIME_RIGHT - TIME_PITCH + 2
         sta dCharX
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
         lda #TIME_Y
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
         sbc #TIME_PITCH
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
         lda >SCREEN,x
         and #$0F
         ora #$E0
         sta >SCREEN,x
         bra dmAdv
dmOdd    lda >SCREEN,x
         and #$F0
         ora #$0E
         sta >SCREEN,x
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
* patched absolute operands; $F0/$F2 direct-page slots are GS/OS scratch.

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
SCORE_TEXT_W equ SCORE_SLOTS * SCORE_PITCH
SCORE_LEFT   equ SCORE_RIGHT + 1 - SCORE_TEXT_W
TIME_TEXT_W  equ TIME_SLOTS * TIME_PITCH
TIME_LEFT    equ TIME_RIGHT + 1 - TIME_TEXT_W

pbOpen      dw 2
            dw 0
            adrl scenePath
pbRead      dw 4
            dw 0
            adrl $012000
            dw SCENE_LEN, 0
            dw 0, 0
pbClose     dw 1
            dw 0
scenePath   dw 10
            db $53,$43,$45,$4E,$45,$34,$2E,$52,$41,$57
nmScene     equ scenePath
nmSceneE    dw 11
            db $53,$43,$45,$4E,$45,$34,$45,$2E,$52,$41,$57
nmTitle     dw 9
            db $54,$49,$54,$4C,$45,$2E,$52,$41,$57
nmHowto     dw 9
            db $48,$4F,$57,$54,$4F,$2E,$52,$41,$57
* High score file and its pblocks. Same shape as pbOpen/pbRead above: pCount,
* refNum (filled in from the successful Open/Create), then the parameters.
hiPath      dw 11
            db $48,$49,$53,$43,$4F,$52,$45,$2E,$44,$41,$54   ; "HISCORE.DAT"
pbHiOpen    dw 2
            dw 0
            adrl hiPath
pbHiRead    dw 4
            dw 0
            adrl dHiBuf
            dw 4, 0
            dw 0, 0
pbHiWrite   dw 4
            dw 0
            adrl dHiBuf
            dw 4, 0
            dw 0, 0
pbHiClose   dw 1
            dw 0
* DOC wave files (M4). GS/OS name strings plus a shared Open/Read/Close pblock
* trio; only the pathname pointer is patched per file, exactly like loadScene.
AUD_ITEMS equ 5
sndSelName  dw 10
            db $53,$45,$4C,$45,$43,$54,$2E,$50,$43,$4D   ; SELECT.PCM
sndFallName dw 8
            db $46,$41,$4C,$4C,$2E,$50,$43,$4D           ; FALL.PCM
sndM1Name   dw 10
            db $4D,$41,$54,$43,$48,$31,$2E,$50,$43,$4D   ; MATCH1.PCM
sndM2Name   dw 10
            db $4D,$41,$54,$43,$48,$32,$2E,$50,$43,$4D   ; MATCH2.PCM
sndM3Name   dw 10
            db $4D,$41,$54,$43,$48,$33,$2E,$50,$43,$4D   ; MATCH3.PCM
pbSndOpen   dw 2
            dw 0
            adrl sndSelName
pbSndRead   dw 4
            dw 0
            adrl $012000
            dw 8192, 0
            dw 0, 0
pbSndClose  dw 1
            dw 0
* MUSIC.PCM is streamed (M5): 126 s of 8-bit PCM does not fit in wave RAM, so
* the music section above reads it in 4K slices through pbMusRead while the
* oscillators loop the two 4K wave buffers.
musNamePtr  dw 9
            db $4D,$55,$53,$49,$43,$2E,$50,$43,$4D      ; MUSIC.PCM
pbMusOpen   dw 2
            dw 0
            adrl musNamePtr
pbMusRead   dw 4
            dw 0
            adrl dMusStage
            dw 4096, 0
            dw 0, 0
pbMusClose  dw 1
            dw 0
* 16-byte wave entries: name (adrl), DOC base, upload length, $C0 value and
* frequency. $20 = table size 4 (4K) + resolution 0; $29 = size 5 (8K) + res 1;
* $30 = size 6 (16K) + res 0. See the DOC RAM map above for the bases.
audTab      adrl sndSelName
            dw $0000, 4096
            dw $20, 4
            dw 0, 0
            adrl sndFallName
            dw $1000, 4096
            dw $20, 4
            dw 0, 0
            adrl sndM1Name
            dw $2000, 16384
            dw $30, 1
            dw 0, 0
            adrl sndM2Name
            dw $6000, 16384
            dw $30, 1
            dw 0, 0
            adrl sndM3Name
            dw $A000, 16384
            dw $30, 1
            dw 0, 0
* GS/OS strings take a 2-byte length word (GS/OS Reference ch.3); Merlin's
* `str` emits a Pascal 1-byte length, which Open reads as a bogus 21315-char
* path and fails.

* Exit hands the machine to the Finder instead of a blank GS/OS text page.
* Quit's pblock is a 16-bit result word followed by a long pointer to the
* *next* application's GS/OS pathname; a NULL pointer is exactly the case
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
dRandSeed   dw $1234
dRandTmp    dw 0
dMark       ds 128      ; 64 word flags, one per cell
dBoardShadow ds 128     ; pre-pass copy: cascade animation moves one row/frame
dTitleSave  ds 11220        ; cached 110x102-byte title menu band (see saveTitleMenu)
dMoved      dw 0            ; animStep: cells that changed this frame
dAnimFrames dw 0            ; frames left in the current animation
dAnimSteps  dw 0            ; cascade animation frames since boot (evidence)
dFlashFrames dw 6           ; matched-gem pop length in frames
dAnimSpeed  dw 4            ; frames per gravity row (4 = 15 rows/s, like the original)
dWaitCnt    dw 0
dTimeLeft   dw 120      ; Time Trial: 2 minutes
dTick60     dw 0
* --- ADB mouse state (M3) ---------------------------------------------------
dMouseX     dw 160          ; absolute pointer position on the 320x200 screen
dMouseY     dw 100
dMouseBtn   dw 0            ; 1 while the left button is held
dMousePrev  dw 0
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
dMEvReady   dw 0
dMEvX       dw 0
dMEvY       dw 0
* DEBUG (M3 續 16): ring of what mousePoll actually saw at $C027/$C024 while
* the host pointer moved.  dMLogS = status at poll entry, dMLogB = first byte
* read, dMLogC = second byte read; index wraps at 32 polls (~0.5 s at 60 Hz).
dMLogIdx    dw 0
dMLogS      ds 32
dMLogB      ds 32
dMLogC      ds 32
* --- visible pointer overlay (M3) -------------------------------------------
dPtrX       dw 160
dPtrY       dw 100
dPtrOff     dw 0            ; SHR byte offset of the arrow box
dPrtT       dw 0
dPrtCnt     dw 0
dPtrOn      dw 0            ; 0 = nothing on screen to restore yet
dPtrSave    ds 28           ; bytes under the arrow
dPtrPaint   ds 28           ; bytes the arrow wrote (restore guard)
dSavePal    ds 384          ; GS/OS desktop palette, given back on Quit
dSaveScb    ds 200          ; GS/OS scanline table, likewise
* --- title / menu / mode state (M3) -----------------------------------------
MENU_ITEMS  equ 5
OPT_ITEMS   equ 3
HOWTO_LINES equ 18
menuStrTab  dw strMTrial,strMEndless,strMHowto,strMOptions,strMExit
menuYTab    dw 92,114,136,158,180
optYTab     dw 92,130,168
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
dSaveOff    dw 0
dOptSel     dw 0            ; Options selection (0 = music, 1 = sound, 2 = back)
dOptIdx     dw 0
dOptX       dw 0
dSoundOn    dw 1            ; Options: "Sound: On/Off", honoured by playSound
dMenuIdx    dw 0
dMenuX      dw 0
dPathPtr    dw 0
dLoadOfs    dw 0            ; byte offset of the next 4000-byte scene slice
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
dHiBuf      ds 4            ; file image while reading/writing
dBestPtr    dw 0
dBestLen    dw 0
dBestW      dw 0
* --- DOC audio (M4) ---------------------------------------------------------
dSndIdx     dw 0             ; wave being loaded / id of the last trigger
dSndTot     dw 0             ; total triggers (socket harness evidence)
dSndRot     dw 0
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
dMusEnd     dw 0             ; dMusTick16 value at which the playing buffer ends
dMusTick16  dw 0             ; VSYNC counter in 1/16 frame units (wraps at 68 s)
dMusTotal   dw 0             ; bytes of the standby buffer already queued
dMusChunk   dw 0
dMusRead    dw 0             ; bytes transferred by the last GS/OS Read
dMusRef     dw 0             ; MUSIC.PCM refNum + 1 (0 = not open)
dMusOk      dw 0             ; music buffers started (harness evidence)
dMusBad     dw 0             ; starvations / read failures (must stay 0)
dMusGuard   dw 0             ; musStep calls since the playing table started
dMusPump    dw 0             ; harness: musStep calls made from a scene load
dMusHalt    dw 0             ; harness: calls that saw the end-of-table flag
dMusStage   ds 4096          ; one buffer of PCM read ahead from disk

         put ../generated/gem_data.s

*-----------------------------------------------------------------------------
* Debug anchor table for the GSSquared socket harness. It lives after the
* generated assets and starts with a magic word so the harness can find it:
* dbgTab+4 is a list of 24-bit addresses (adrl) of the variables the test
* scripts read. Keep the order in sync with C:\tmp\p_verify2.ps1.
*-----------------------------------------------------------------------------
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
         adrl dMEvReady
         adrl dMEvX
         adrl dMEvY
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
         END
