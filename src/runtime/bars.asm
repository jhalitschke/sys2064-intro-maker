#importonce
// ---------------------------------------------------------------------------
// bars.asm - fills the bar buffers for the FLD loop (called in IRQ TOP).
// Budget: clear 2 x 80 bytes ~1600 cycles + 3 bars x 15 lines ~700 cycles.
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
        lda cfg_flags
        and #FLAG_BARS
        beq bp_done
        lda cfg_preset
        and #PRESET_COUNT - 1
        tax
        lda rt_preset_offs,x
        sta rt_t0                   // preset offset
        ldy #0
bp_bar:
        sty rt_t1                   // bar index
        lda cfg_flags
        and #FLAG_BAR_SINE
        beq !+
        lda rt_bar_phase
        clc
        adc rt_bar_phase_offs,y
        and #SIN_LEN - 1
        tax
        lda bar_sin,x
        jmp bp_pos
!:      lda rt_bar_fixed,y
bp_pos:
        tax                         // first bar line
        ldy rt_t0
        lda #BAR_HEIGHT
        sta rt_t2
!:      lda rt_presets,y
        sta border_buf,x
        sta bg_buf,x
        inx
        iny
        dec rt_t2
        bne !-
        ldy rt_t1
        iny
        cpy #BAR_COUNT
        bne bp_bar
        inc rt_bar_phase
bp_done:
        rts
