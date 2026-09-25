#importonce
// ---------------------------------------------------------------------------
// ramtables.asm - build the RAM tables under the KERNAL from mv_sin
// (called by runtime_start with $01 = $35). ~60k cycles.
// ---------------------------------------------------------------------------

rt_tables_init:
        // $d011 per FLD line L = FLD_FIRST_LINE + i: YSCROLL (L + 2) & 7
        // never matches L or L + 1, so no badline occurs. The last line
        // restores YSCROLL 3, which makes the next line a badline again.
        ldx #FLD_LINES - 2
!:      txa
        clc
        adc #FLD_FIRST_LINE + 2
        and #7
        ora #D011_BASE
        sta fld_tab,x
        dex
        bpl !-
        lda #RT_D011
        sta fld_tab + FLD_LINES - 1
        // presets: colour j of 15 = half[j < 8 ? j : 14 - j]
        ldx #PRESET_COUNT * BAR_HEIGHT - 1
        ldy #BAR_HEIGHT - 1         // j
        lda #(PRESET_COUNT - 1) * PRESET_HALF
        sta rt_t1                   // half table base of this preset
!:      tya
        cmp #PRESET_HALF
        bcc !+
        eor #$ff                    // 14 - j (carry set)
        adc #BAR_HEIGHT - 1
!:      clc
        adc rt_t1
        sty rt_t0
        tay
        lda rt_preset_halves,y
        sta rt_presets,x
        ldy rt_t0
        dey
        bpl !+
        ldy #BAR_HEIGHT - 1
        lda rt_t1
        sec
        sbc #PRESET_HALF
        sta rt_t1
!:      dex
        bpl !---
        // sine tables
        ldx #SIN_LEN - 1
rti_loop:
        stx rt_mv_tmp
        txa
        ldx #BAR_SIN_AMP
        jsr rt_sin_scaled
        clc
        adc #BAR_SIN_MID
        ldx rt_mv_tmp
        sta bar_sin,x
        txa
        ldx #SPR_X2_AMP
        jsr rt_sin_scaled
        clc
        adc #SPR_X2_MID
        ldx rt_mv_tmp
        sta spr_x2,x
        txa
        clc
        adc #SIN_QUARTER            // cosine
        ldx #SPR_Y_AMP
        jsr rt_sin_scaled
        clc
        adc #SPR_Y_MID
        ldx rt_mv_tmp
        sta spr_y,x
        dex
        bpl rti_loop
        rts

// A = phase, X = amplitude -> A = sin * amplitude / 128 (signed)
rt_sin_scaled:
        stx rt_t0
        jsr tu_sin_abs              // A = |sin|, rt_t3 = sign
        ldx rt_t0
        jsr tu_mul
        ldx rt_t3
        bpl !+
        eor #$ff
        clc
        adc #1
!:      rts
