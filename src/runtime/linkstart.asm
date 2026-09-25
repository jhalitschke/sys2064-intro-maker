#importonce
// ---------------------------------------------------------------------------
// linkstart.asm - start a linked program (saved intro, SPACE): the mover
// saved in front of the program data goes to the tape buffer and moves the
// program to its load address (see editor/link.asm).
// ---------------------------------------------------------------------------

rt_link_start:
        lda cfg_link_len
        ora cfg_link_len + 1
        bne !+
        rts
!:      lda cfg_link_src
        sec
        sbc #MOVER_SIZE
        sta rt_ptr
        lda cfg_link_src + 1
        sbc #0
        sta rt_ptr + 1
        ldy #0
!:      lda (rt_ptr),y
        sta MOVER_ADDR,y
        iny
        cpy #MOVER_SIZE
        bne !-
        ldx #MV_SRC + 2 - MV_LEN    // 8 bytes
!:      lda cfg_link_len - 1,x      // len, dest, start, src -> zero page
        sta MV_LEN - 1,x
        dex
        bne !-
        jmp MOVER_ADDR
