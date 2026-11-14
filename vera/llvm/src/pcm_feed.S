/* Preprocessed so VERA_BASE follows the selected slot.
 *
 * pcm_copy  copy pcm_count bytes from pcm_pointer into the PCM FIFO
 * pcm_mix   add pcm_count effect bytes at pcm_effect to the music bytes at
 *           pcm_pointer and write the signed 8-bit sum into the FIFO
 *
 * Both runs may straddle a 256-byte page: X/Y carry the low byte and the
 * patched high byte is incremented when the index wraps.  The music/effect
 * peaks are limited at build time so the sum cannot wrap.  The FIFO is only
 * probed once per run: the player never queues more than one VSYNC worth of
 * samples on top of its safety margin, so a run cannot overflow mid-way.
 * pcm_count keeps what was not sent (0..255).
 */
        .section .text
        .global pcm_copy
        .global pcm_mix
        .global pcm_stage
/* Copy 1..256 bytes from VERA data port 0 to pcm_pointer. A zero low
 * count represents 256; the C caller never invokes this with a zero count. */
pcm_stage:
        LDA pcm_pointer+1
        STA stage_store+2
        LDY pcm_pointer
        LDX pcm_count
stage_next:
        LDA VERA_BASE+3
stage_store:
        STA $FF00,Y
        INY
        BNE stage_no_wrap
        INC stage_store+2
stage_no_wrap:
        DEX
        BNE stage_next
        RTS
pcm_copy:
        LDA pcm_pointer+1
        STA pcm_load+2
        LDY pcm_pointer
        LDA pcm_count
        STA pcm_left
        BEQ pcm_done
        LDA VERA_BASE+27
        BMI pcm_done
pcm_next:
pcm_load:
        LDA $FF00,Y
        STA VERA_BASE+29
        INY
        BNE pcm_no_wrap
        INC pcm_load+2
pcm_no_wrap:
        DEC pcm_left
        BNE pcm_next
pcm_done:
        LDA pcm_left
        STA pcm_count
        RTS
pcm_mix:
        LDA pcm_pointer+1
        STA mix_load+2
        LDA pcm_effect+1
        STA mix_eff+2
        LDY pcm_pointer
        LDX pcm_effect
        LDA pcm_count
        STA pcm_left
        BEQ mix_done
        LDA VERA_BASE+27
        BMI mix_done
mix_next:
mix_load:
        LDA $FF00,Y
        CLC
mix_eff:
        ADC $FF00,X
        STA VERA_BASE+29
        INY
        BNE mix_no_y_wrap
        INC mix_load+2
mix_no_y_wrap:
        INX
        BNE mix_no_x_wrap
        INC mix_eff+2
mix_no_x_wrap:
        DEC pcm_left
        BNE mix_next
mix_done:
        LDA pcm_left
        STA pcm_count
        RTS
        .section .bss
pcm_left: .byte 0
