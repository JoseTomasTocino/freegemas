; ProDOS MLI bridges for file-level loading and legacy block operations.
        .section .bss
        .global mli_unit, mli_buf_lo, mli_buf_hi, mli_blk_lo, mli_blk_hi, mli_status
mli_unit:   .byte 0
mli_buf_lo: .byte 0
mli_buf_hi: .byte 0
mli_blk_lo: .byte 0
mli_blk_hi: .byte 0
mli_status: .byte 0
mli_params: .byte 0,0,0,0,0,0,0,0
        .global mli_saved_zp
mli_saved_zp: .space 192

        .section .data
        .global mli_open_params, mli_close_params, mli_read_params, mli_eof_params
        .global mli_write_params, mli_mark_params, mli_prefix_params
mli_open_params:  .byte 3,0,0,0,0,0
mli_close_params: .byte 1,0
mli_read_params:  .byte 4,0,0,0,0,0,0,0
mli_write_params: .byte 4,0,0,0,0,0,0,0
mli_mark_params:  .byte 2,0,0,0,0
mli_prefix_params:.byte 1,0,0
mli_eof_params:   .byte 2,0,0,0,0

        .section .bss

        .section .text
        .global mli_read_block
        .global mli_write_block
        .global mli_open, mli_close, mli_read, mli_write
        .global mli_set_mark, mli_get_prefix
        .global mli_get_eof
mli_write_block:
        LDA #$81
        BNE mli_setup
mli_read_block:
        LDA #$80
mli_setup:
        STA mli_command
        ; ProDOS and LLVM-MOS share zero page. Preserve compiler registers
        ; and ZP-allocated state across BOTH reads and writes.
        LDX #0
mli_save_zp:
        LDA $00,X
        STA mli_saved_zp,X
        INX
        CPX #$C0
        BNE mli_save_zp
        LDA #3
        STA mli_params
        LDA mli_unit
        STA mli_params+1
        LDA mli_buf_lo
        STA mli_params+2
        LDA mli_buf_hi
        STA mli_params+3
        LDA mli_blk_lo
        STA mli_params+4
        LDA mli_blk_hi
        STA mli_params+5
        JSR $BF00
mli_command:
        .byte $80
        .word mli_params
        STA mli_status
        LDX #0
mli_restore_zp:
        LDA mli_saved_zp,X
        STA $00,X
        INX
        CPX #$C0
        BNE mli_restore_zp
        LDA mli_status
        RTS

        .macro CALL_MLI name, opcode, params
\name:
        LDX #0
.save\@:
        LDA $00,X
        STA mli_saved_zp,X
        INX
        CPX #$C0
        BNE .save\@
        JSR $BF00
        .byte \opcode
        .word \params
        STA mli_status
        LDX #0
.restore\@:
        LDA mli_saved_zp,X
        STA $00,X
        INX
        CPX #$C0
        BNE .restore\@
        LDA mli_status
        RTS
        .endmacro

        CALL_MLI mli_open,      $C8, mli_open_params
        CALL_MLI mli_close,     $CC, mli_close_params
        CALL_MLI mli_read,      $CA, mli_read_params
        CALL_MLI mli_write,     $CB, mli_write_params
        CALL_MLI mli_set_mark,  $CE, mli_mark_params
        CALL_MLI mli_get_prefix,$C7, mli_prefix_params
        CALL_MLI mli_get_eof,   $D1, mli_eof_params

        ; Return control to the installed ProDOS quit handler (Bitsy Bye).
        ; No C state is needed after this non-returning operation.
        .global mli_quit
mli_quit:
        CLD
        LDX #$FF
        TXS
        LDA #0
        STA $C00C              ; 40-column text
        STA $C00E              ; primary character set
        STA $C051              ; text on
        STA $C054              ; page 1
        JSR $FB39              ; ROM SETTXT
        JSR $FC58              ; ROM HOME
        CLI
        JSR $BF00
        .byte $65
        .word quit_params
quit_returned:
        JMP quit_returned      ; QUIT does not return on success
        .section .rodata
quit_params:
        .byte 4,0
        .word 0
        .byte 0
        .word 0
