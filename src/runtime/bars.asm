#importonce
// ---------------------------------------------------------------------------
// bars.asm - fills the bar buffers for the FLD loop (called in IRQ TOP).
// ---------------------------------------------------------------------------

bars_prepare:
        lda cfg_border
        ldx #FLD_LINES - 1
!:      sta border_buf,x
        dex
        bpl !-
        lda cfg_bg
        ldx #FLD_LINES - 1
!:      sta bg_buf,x
        dex
        bpl !-
        rts
