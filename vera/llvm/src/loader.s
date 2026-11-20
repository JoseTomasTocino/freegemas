        .section .text
        .global clear_text
clear_text:
        LDA #$A0
        LDX #0
clear_text_loop:
        STA $0400,X
        STA $0500,X
        STA $0600,X
        STA $0700,X
        INX
        BNE clear_text_loop
        RTS

        .section .rodata
        .global trampoline_src, trampoline_src_end
trampoline_src:
; $3C0 READ param: refnum, dest, request count, transfer count
; $3D0 CLOSE param: refnum; $3C8 is the number of 512-byte chunks.
        LDA #4
        STA $3C0
        LDX #0
load_loop:
        STX $3C9
        JSR $BF00
        .byte $CA               ; READ opened ProDOS file
        .word $3C0
        BCS fail
        LDX $3C9
        ; Each READ fills 512 bytes; advance the destination by two pages.
        ; Without this, every iteration overwrites $3000 and the image never
        ; reaches its actual entry code.
        CLC
        LDA $3C3
        ADC #2
        STA $3C3
        INX
        CPX $03C8
        BCC load_loop
        LDA #1
        STA $3D0
        JSR $BF00
        .byte $CC               ; CLOSE
        .word $3D0
        ; Segment calls never return. Discard their accumulated hardware
        ; return addresses as well as reinitializing the C soft stack.
        LDX #$FF
        TXS
        JMP $3000
fail:   LDA #$C6                ; visible MLI failure marker: "F"
        STA $0400
        JMP fail
trampoline_src_end:

        .section .text
        .global launch_image
launch_image:
        JMP $0300

        .section .bss
        .global scene_src, scene_count, scene_data_port
scene_src: .word 0
scene_count: .word 0
scene_data_port: .word 0

        .section .text
        .global scene_copy
; Raw scene blocks: 13 cycles/pixel for full 256-byte pages. No ZP scratch.
scene_copy:
        LDA scene_src
        STA scene_read+1
        LDA scene_src+1
        STA scene_read+2
        LDA scene_data_port
        STA scene_write+1
        LDA scene_data_port+1
        STA scene_write+2
        LDA scene_count+1
        BEQ scene_tail
scene_page:
        LDX #0
scene_page_loop:
scene_read:
        LDA $0C00,X
scene_write:
        STA $C203
        INX
        BNE scene_page_loop
        INC scene_read+2
        DEC scene_count+1
        BNE scene_page
scene_tail:
        LDA scene_count
        BEQ scene_done
        LDA scene_read+1
        STA scene_tail_read+1
        LDA scene_read+2
        STA scene_tail_read+2
        LDA scene_data_port
        STA scene_tail_write+1
        LDA scene_data_port+1
        STA scene_tail_write+2
        LDX #0
scene_tail_loop:
scene_tail_read:
        LDA $0C00,X
scene_tail_write:
        STA $C203
        INX
        CPX scene_count
        BNE scene_tail_loop
scene_done:
        RTS
