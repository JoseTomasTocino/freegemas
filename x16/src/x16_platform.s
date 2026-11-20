; Commander X16 KERNAL bridge and VSYNC counter.
;
; Every KERNAL call may clobber the 16-bit ABI registers r0-r15 ($02-$21).
; Those overlap the LLVM-MOS imaginary registers, so preserve them across each
; call.  $22-$7F is documented as user zero page and is left alone.

        .section .text

        .global x16_kload
x16_kload:
        jsr save_zp
        lda $00
        sta saved_bank
        lda x16_namelen
        ldx #<x16_name
        ldy #>x16_name
        jsr $FFBD
        lda #1
        ldx #8
        ldy x16_sa
        jsr $FFBA
        lda x16_mode
        beq load_ram
        ldx x16_addr
        ldy x16_addr+1
        jsr $FFD5
        jmp load_done
load_ram:
        lda x16_bank
        sta $00
        lda #0
        ldx x16_addr
        ldy x16_addr+1
        jsr $FFD5
load_done:
        sta x16_err
        stx x16_end
        sty x16_end+1
        lda saved_bank
        sta $00
        jsr restore_zp
        rts

; Headerless save: A = pointer to start address in ZP, X/Y = end address.
; Kept for the 12-byte high-score record.
        .global x16_ksave
x16_ksave:
        jsr save_zp
        lda x16_save_start
        sta $22
        lda x16_save_start+1
        sta $23
        lda x16_namelen
        ldx #<x16_name
        ldy #>x16_name
        jsr $FFBD
        lda #1
        ldx #8
        ldy #1
        jsr $FFBA
        lda #$22
        ldx x16_save_end
        ldy x16_save_end+1
        jsr $FEBA
        sta x16_err
        jsr restore_zp
        rts

        .global x16_kgetin
x16_kgetin:
        jsr save_zp
        lda #18                 ; extapi kbdbuf_get: keyboard read is not
        jsr $FEAB               ; R49 keyboard buffer extapi
        sta x16_key
        jsr restore_zp
        lda x16_key
        rts

        .global x16_kcint
x16_kcint:
        jsr save_zp
        jsr $FF81               ; CINT: restore the KERNAL text screen
        jsr restore_zp
        rts

        .global x16_kputc
x16_kputc:
        pha
        jsr save_zp
        pla
        jsr $FFD2
        jsr restore_zp
        rts

        .global x16_kjoystick
x16_kjoystick:
        jsr save_zp
        jsr $FF53
        lda #0
        jsr $FF56
        sta x16_joy0
        stx x16_joy1
        sty x16_joy2
        jsr restore_zp
        rts

        .global x16_enter_basic
x16_enter_basic:
        clc
        jmp $FF47

; Keep the KERNAL mouse sprite 0 off the 240-line playfield.  The ROM turns
; sprite 0 back on every mouse scan, and any write to its visibility bit is
; undone by the next scan.  A +240 Y offset makes mouse_update_position put it
; at y=240..479, while mouse_get still returns the real pointer position.
; extapi $FEAB (A=3, carry clear) reads r0/r1 as X/Y offsets.  r0 = $02,
; r1 = $04 in the LLVM-MOS zero page.
        .global x16_mouse_offset
x16_mouse_offset:
        stz $02
        stz $03
        lda #240
        sta $04
        stz $05
        lda #3
        clc
        jsr $FEAB
        rts

; PCM music stream: OPEN/CHKIN/MACPTR/CLOSE on logical file 3.  The music
; overlay reads 267..268 bytes per VSYNC from music.zcm (after its 8-byte
; header) and writes 16-bit samples to the FIFO.  MACPTR is the fast KERNAL
; block read; CHRIN is only a fallback for hosts that do not implement it.
        .global x16_pcm_open
x16_pcm_open:
        jsr save_zp
        lda $00
        sta pcm_saved_bank
        lda #0
        sta $00
        lda x16_namelen
        ldx #<x16_name
        ldy #>x16_name
        jsr $FFBD
        lda #3
        ldx #8
        ldy #2
        jsr $FFBA
        lda #1
        sta x16_pcm_stage
        jsr $FFC0
        sta x16_pcm_err
        bcs pcm_open_fail
        lda #2
        sta x16_pcm_stage
        ldx #3
        jsr $FFC6
        sta x16_pcm_err
        bcs pcm_open_fail
        lda #3
        sta x16_pcm_stage
        lda pcm_saved_bank
        sta $00
        jsr restore_zp
        lda #0
        rts
pcm_open_fail:
        lda #3
        jsr $FFC3
        lda pcm_saved_bank
        sta $00
        jsr restore_zp
        lda x16_pcm_err
        bne pcm_open_return
        lda #1
        sta x16_pcm_err
pcm_open_return:
        rts

        .global x16_pcm_read
x16_pcm_read:
        jsr save_zp
        lda $00
        sta pcm_saved_bank
        lda #0
        sta $00
        lda #0
        sta x16_pcm_got
        sta x16_pcm_got+1
        lda x16_pcm_count
        sta stream_left
        lda x16_pcm_count+1
        sta stream_left+1
        lda x16_pcm_dest
        sta stream_ptr
        lda x16_pcm_dest+1
        sta stream_ptr+1
pcm_read_loop:
        lda stream_left
        ora stream_left+1
        bne pcm_read_continue
        jmp pcm_read_done          ; local branch: pcm_read_done is >127 bytes away
pcm_read_continue:
        lda #$ff
        ldx stream_left+1
        bne pcm_read_chunk
        lda stream_left
pcm_read_chunk:
        sta pcm_req
        ldx stream_ptr
        ldy stream_ptr+1
        clc
        jsr $FF44                ; MACPTR: A=count, X/Y=destination
        bcs pcm_read_fallback
        ; MACPTR returns the number of bytes actually read in X (lo) and
        ; Y (hi).  A=0 asks for up to 512 bytes, so Y is not always zero:
        ; taking only X lost 256 bytes from every 267/510-byte run and
        ; shifted all following 16-bit samples.
        stx pcm_read_lo
        sty pcm_read_hi
        lda pcm_read_lo
        ora pcm_read_hi
        bne pcm_read_got_some
        jmp pcm_read_done          ; local branch: pcm_read_done is >127 bytes away
pcm_read_got_some:
        ; accumulate got += returned count
        lda x16_pcm_got
        clc
        adc pcm_read_lo
        sta x16_pcm_got
        lda x16_pcm_got+1
        adc pcm_read_hi
        sta x16_pcm_got+1
        ; advance destination
        lda stream_ptr
        clc
        adc pcm_read_lo
        sta stream_ptr
        lda stream_ptr+1
        adc pcm_read_hi
        sta stream_ptr+1
        ; consume from the requested count
        lda stream_left
        sec
        sbc pcm_read_lo
        sta stream_left
        lda stream_left+1
        sbc pcm_read_hi
        sta stream_left+1
        bcs pcm_read_loop
        lda #0
        sta stream_left
        sta stream_left+1
        jmp pcm_read_done

pcm_read_fallback:
        lda stream_ptr+1
        sta pcm_chr_store+2
pcm_read_chr_loop:
        lda stream_left
        ora stream_left+1
        beq pcm_read_done
        jsr $FFCF
        ldx stream_ptr
pcm_chr_store:
        sta $FF00,X
        inc stream_ptr
        bne pcm_read_chr_no_wrap
        inc stream_ptr+1
        lda stream_ptr+1
        sta pcm_chr_store+2
pcm_read_chr_no_wrap:
        lda x16_pcm_got
        clc
        adc #1
        sta x16_pcm_got
        lda x16_pcm_got+1
        adc #0
        sta x16_pcm_got+1
        lda stream_left
        sec
        sbc #1
        sta stream_left
        lda stream_left+1
        sbc #0
        sta stream_left+1
        jmp pcm_read_chr_loop

pcm_read_done:
        jsr $FFB7                ; READST
        sta x16_pcm_status
        lda pcm_saved_bank
        sta $00
        jsr restore_zp
        lda x16_pcm_got
        rts

        .global x16_pcm_close
x16_pcm_close:
        jsr save_zp
        lda $00
        sta pcm_saved_bank
        lda #0
        sta $00
        jsr $FFCC
        lda #3
        jsr $FFC3
        lda pcm_saved_bank
        sta $00
        jsr restore_zp
        rts

; Chain the KERNAL IRQ so the VSYNC counter keeps running.  The old vector
; lives in shared RAM because the resident loader's BSS is cleared on every
; return from a $3000 overlay.
        .global x16_irq_install
x16_irq_install:
        lda $9E15
        bne irq_done
        sei
        lda $0314
        sta $9E16
        lda $0315
        sta $9E17
        lda #<irq_handler
        sta $0314
        lda #>irq_handler
        sta $0315
        lda #1
        sta $9E15
        cli
irq_done:
        rts

        .global x16_irq_remove
x16_irq_remove:
        sei
        lda $9E15
        beq irq_remove_done
        lda $9E16
        sta $0314
        lda $9E17
        sta $0315
        lda #0
        sta $9E15
irq_remove_done:
        cli
        rts

irq_handler:
        pha
        inc $9E14
        pla
        jmp ($9E16)

        .global save_zp
save_zp:
        ldx #0
save_zp_loop:
        lda $02,x
        sta zp_save,x
        inx
        cpx #36
        bne save_zp_loop
        rts

        .global restore_zp
restore_zp:
        ldx #0
restore_zp_loop:
        lda zp_save,x
        sta $02,x
        inx
        cpx #36
        bne restore_zp_loop
        rts

        .section .bss
        .global x16_name
x16_name:       .space 40
        .global x16_namelen
x16_namelen:    .byte 0
        .global x16_sa
x16_sa:         .byte 0
        .global x16_mode
x16_mode:       .byte 0
        .global x16_bank
x16_bank:       .byte 0
        .global x16_addr
x16_addr:       .word 0
        .global x16_err
x16_err:        .byte 0
        .global x16_end
x16_end:        .word 0
        .global x16_key
x16_key:        .byte 0
        .global x16_joy0
x16_joy0:       .byte 0
        .global x16_joy1
x16_joy1:       .byte 0
        .global x16_joy2
x16_joy2:       .byte 0
        .global x16_save_start
x16_save_start: .word 0
        .global x16_save_end
x16_save_end:   .word 0
        .global x16_pcm_err
x16_pcm_err:    .byte 0
        .global x16_pcm_count
x16_pcm_count:  .word 0
        .global x16_pcm_got
x16_pcm_got:    .word 0
        .global x16_pcm_status
x16_pcm_status: .byte 0
        .global x16_pcm_stage
x16_pcm_stage:  .byte 0
        .global x16_pcm_dest
x16_pcm_dest:   .word 0
stream_left:    .word 0
stream_ptr:     .word 0
pcm_req:        .byte 0
pcm_read_lo:    .byte 0
pcm_read_hi:    .byte 0
pcm_saved_bank: .byte 0
saved_bank:     .byte 0
zp_save:        .space 36
