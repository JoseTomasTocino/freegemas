/* Preprocessed so VERA_BASE follows the selected slot.
 *
 * pcm_copy    copy pcm_count bytes from pcm_pointer into the PCM FIFO.  The
 *             count is 16-bit because one 16-bit music run can be 510 bytes.
 *
 * The runs may straddle a 256-byte page: X/Y carry the low byte and the patched
 * high byte is incremented when the index wraps.  The FIFO is probed before
 * every byte so a near-full FIFO cannot overrun; pcm_count keeps what was not
 * sent and the caller retries it.
 */
        .section .text
        .global pcm_copy
pcm_copy:
        ; A 16-bit FIFO accepts complete two-byte samples.  Check for room only
        ; before each pair and never split a pair across calls: splitting a
        ; sample shifted every later word and produced the loud noise bursts.
        LDA pcm_pointer
        STA pcm_src_lo
        LDA pcm_pointer+1
        STA pcm_src_hi
        LDA pcm_count
        STA pcm_left
        LDA pcm_count+1
        STA pcm_left+1

copy_loop:
        LDA pcm_left+1
        BNE copy_have_word
        LDA pcm_left
        CMP #2
        BCC copy_done
copy_have_word:
        LDA VERA_BASE+27
        BMI copy_done
        JSR pcm_byte
        JSR pcm_byte
        LDA pcm_left
        SEC
        SBC #2
        STA pcm_left
        LDA pcm_left+1
        SBC #0
        STA pcm_left+1
        JMP copy_loop

copy_done:
        LDA pcm_left
        STA pcm_count
        LDA pcm_left+1
        STA pcm_count+1
        RTS

pcm_byte:
        LDA pcm_src_hi
        STA pcm_byte_load+2
        LDY pcm_src_lo
pcm_byte_load:
        LDA $FF00,Y
        STA VERA_BASE+29
        INC pcm_src_lo
        BNE pcm_byte_done
        INC pcm_src_hi
pcm_byte_done:
        RTS

        .section .bss
pcm_left: .space 2
pcm_src_lo: .byte 0
pcm_src_hi: .byte 0
