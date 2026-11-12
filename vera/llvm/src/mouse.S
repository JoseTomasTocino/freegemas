/* Apple Mouse Card firmware support, based on Apple II DeskTop's standard
 * slot ROM interface. VERA in slot 4 takes precedence in that build. */
        .section .bss
        .global mouse_x, mouse_y, mouse_buttons, mouse_slot
mouse_x:       .space 2
mouse_y:       .byte 0
mouse_buttons: .byte 0
mouse_slot:    .byte 0
mouse_base_hi: .byte 0
mouse_operand: .byte 0
mouse_arg:     .byte 0
mouse_vector:  .byte 0
mouse_target:  .byte 0,0
mouse_lc_ram: .byte 0
mouse_lc_bank2: .byte 0

        .section .text
        .global mouse_init, mouse_poll

/* Each vector is ONE byte: the entry's low address; its high byte is Cn.
 * Firmware requires X=Cn, Y=slot*16 and may use the compiler's zero page. */
mouse_call:
        STA mouse_arg
        /* Same protection buffer as MLI; firmware polling and disk calls
         * are synchronous and do not nest, so no additional RAM is needed. */
        LDX #0
mouse_save_zp:
        LDA $00,X
        STA mli_saved_zp,X
        INX
        CPX #192
        BNE mouse_save_zp
        LDA mouse_base_hi
        STA mouse_vector_read+2
        STA mouse_target+1
        LDY mouse_vector
mouse_vector_read:
        LDA $C000,Y
        STA mouse_target
        LDA mouse_arg
        LDX mouse_base_hi
        LDY mouse_operand
        JSR mouse_dispatch
        LDX #0
mouse_restore_zp:
        LDA mli_saved_zp,X
        STA $00,X
        INX
        CPX #192
        BNE mouse_restore_zp
        RTS
mouse_dispatch:
        JMP (mouse_target)

/* Input A=slot; returns zero when the standard ROM signature is present. */
mouse_check_slot:
        ORA #$C0
        STA mouse_base_hi
        STA mouse_signature_a+2
        STA mouse_signature_b+2
mouse_signature_a:
        LDA $C00C
        CMP #$20
        BNE mouse_not_found
mouse_signature_b:
        LDA $C0FB
        CMP #$D6
        BNE mouse_not_found
        LDA mouse_base_hi
        AND #$0F
        STA mouse_slot
        ASL A
        ASL A
        ASL A
        ASL A
        STA mouse_operand
        LDA #0
        RTS
mouse_not_found:
        LDA #$FF
        RTS

mouse_init:
        LDA #0
        STA mouse_slot
#if VERA_BASE != 0xC400
        LDA #4
        JSR mouse_check_slot
        BEQ mouse_found
#endif
        LDA #5
        JSR mouse_check_slot
        BEQ mouse_found
        JMP mouse_init_none   /* Initialization exceeds a short branch. */
mouse_found:
        /* INITMOUSE checks ROM VERSION. Preserve both LC RAM/ROM selection
         * and bank: DeskTop assumes its own bank 1; ProDOS need not do so. */
        LDA $C011             /* RDBNK2 */
        STA mouse_lc_bank2
        LDA $C012             /* RDLCRAM */
        STA mouse_lc_ram
        BIT $C082             /* ROMIN2 */
        LDA #$19             /* INITMOUSE */
        STA mouse_vector
        LDA #0
        JSR mouse_call
        LDA mouse_lc_bank2
        BMI mouse_restore_bank2
        LDA mouse_lc_ram
        BMI mouse_restore_bank1_ram
        BIT $C08A             /* ROM, bank 1 */
        JMP mouse_rom_restored
mouse_restore_bank1_ram:
        BIT $C08B             /* LCBANK1: RAM read/write, bank 1 */
        BIT $C08B
        JMP mouse_rom_restored
mouse_restore_bank2:
        LDA mouse_lc_ram
        BPL mouse_rom_restored
        BIT $C083             /* LCBANK2: RAM read/write, bank 2 */
        BIT $C083
mouse_rom_restored:

        /* Clamp firmware coordinates to the VERA 320x240 viewport. */
        STZ $0478             /* Clamp parameters are NOT slot indexed. */
        STZ $0578
        LDA #$3F
        STA $04F8             /* x maximum = 319 */
        LDA #$01
        STA $05F8
        LDA #0                /* CLAMPMOUSE X */
        LDX #$17
        STX mouse_vector
        JSR mouse_call

        STZ $0478
        STZ $0578
        LDA #$EF              /* y maximum = 239 */
        STA $04F8
        STZ $05F8
        LDA #1                /* CLAMPMOUSE Y */
        JSR mouse_call

        LDA #1                /* SETMOUSE enabled */
        LDX #$12
        STX mouse_vector
        JSR mouse_call
        LDA #$18              /* HOMEMOUSE */
        STA mouse_vector
        LDA #0
        JSR mouse_call
        LDA #1
        RTS
mouse_init_none:
        STZ mouse_slot
        LDA #0
        RTS

mouse_poll:
        LDA mouse_slot
        BEQ mouse_poll_done
        LDA #$14              /* READMOUSE */
        STA mouse_vector
        LDA #0
        JSR mouse_call
        LDX mouse_slot
        LDA $0478,X
        STA mouse_x
        LDA $0578,X
        STA mouse_x+1
        LDA $04F8,X           /* READMOUSE's Y coordinate */
        STA mouse_y
        LDA $0778,X
        STA mouse_buttons
mouse_poll_done:
        RTS
