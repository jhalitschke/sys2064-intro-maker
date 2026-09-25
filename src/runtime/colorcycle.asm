#importonce
// ---------------------------------------------------------------------------
// colorcycle.asm - title colour cycle in colour RAM rows 1-2.
// ---------------------------------------------------------------------------

cyc_init:
        lda #0
        sta rt_cyc_phase
        sta rt_cyc_div
        rts

// called in IRQ TOP; ~40 x 24 = 960 cycles every CYC_DIVIDER frames
cyc_update:
        lda cfg_flags
        and #FLAG_TITLE_CYCLE
        beq cu_done
        inc rt_cyc_div
        lda rt_cyc_div
        cmp #CYC_DIVIDER
        bcc cu_done
        lda #0
        sta rt_cyc_div
        inc rt_cyc_phase
        ldx #SCREEN_COLS - 1
!:      txa
        clc
        adc rt_cyc_phase
        and #CYC_LEN - 1
        tay
        lda rt_cyc_tab,y
        sta TITLE_COLOR,x
        sta TITLE_COLOR + SCREEN_COLS,x
        dex
        bpl !-
cu_done:
        rts
