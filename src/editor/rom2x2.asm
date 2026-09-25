#importonce
// ---------------------------------------------------------------------------
// rom2x2.asm - built-in big title font generated from the ROM font.
// ---------------------------------------------------------------------------

// ---- ROM 2X2 ---------------------------------------------------------------
// Big title font from the ROM font: every glyph of BIG_GLYPH_ORDER scaled
// to 16x16 with Scale2x (smooth diagonals), 4 tiles each. ~0.3 s.
font_rom2x2:
        // ROM chars $00-$3f -> FILE_BUF
        sei
        lda #CPU_CHARROM
        sta CPU_PORT
        ldx #0
!:      lda CHAR_ROM,x
        sta FILE_BUF,x
        lda CHAR_ROM + $100,x
        sta FILE_BUF + $100,x
        inx
        bne !-
        lda #CPU_DEFAULT
        sta CPU_PORT
        cli
        jsr spread_init
        lda #0
        ldx #BIG_GLYPHS - 1
!:      sta cfg_big_map,x
        dex
        bpl !-
        lda #<BIG_TILES
        sta ed_ptr2
        lda #>BIG_TILES
        sta ed_ptr2 + 1
        lda #0
        sta s2_glyph
r2_glyph:
        ldx s2_glyph
        ldy ed_big_order,x          // screen code
        txa
        asl
        asl
        clc
        adc #BIG_TILE_FIRST
        sta cfg_big_map,y
        tya                         // source = FILE_BUF + sc * 8
        sta ed_ptr
        lda #0
        sta ed_ptr + 1
        ldx #3
!:      asl ed_ptr
        rol ed_ptr + 1
        dex
        bne !-
        lda ed_ptr
        clc
        adc #<FILE_BUF
        sta ed_ptr
        lda ed_ptr + 1
        adc #>FILE_BUF
        sta ed_ptr + 1
        lda #0
        sta s2_row
r2_row:
        ldy s2_row
        lda (ed_ptr),y
        sta s2_p
        lsr
        sta s2_l                    // left neighbour
        lda s2_p
        asl
        sta s2_r                    // right neighbour
        lda #0
        cpy #0
        beq !+
        dey
        lda (ed_ptr),y
        iny
!:      sta s2_u                    // up
        lda #0
        cpy #7
        beq !+
        iny
        lda (ed_ptr),y
!:      sta s2_d                    // down
        lda s2_l
        eor s2_u
        sta s2_lu
        lda s2_u
        eor s2_r
        sta s2_ur
        lda s2_l
        eor s2_d
        sta s2_ld
        lda s2_d
        eor s2_r
        sta s2_dr
        // E0 = P ^ (c0 & (L ^ P)), c0 = ~lu & ur & ld
        lda s2_lu
        eor #$ff
        and s2_ur
        and s2_ld
        jsr r2_left
        sta s2_e0
        // E2: c2 = ~ld & lu & dr
        lda s2_ld
        eor #$ff
        and s2_lu
        and s2_dr
        jsr r2_left
        sta s2_e2
        // E1 = P ^ (c1 & (R ^ P)), c1 = ~ur & lu & dr
        lda s2_ur
        eor #$ff
        and s2_lu
        and s2_dr
        jsr r2_right
        sta s2_e1
        // E3: c3 = ~dr & ld & ur
        lda s2_dr
        eor #$ff
        and s2_ld
        and s2_ur
        jsr r2_right
        sta s2_e3
        // output rows 2r (E0 E1) and 2r+1 (E2 E3); rows 8-15 in the
        // lower tiles: offset k (+8 for k >= 8), right tile +8
        lda s2_row
        asl
        cmp #8
        bcc !+
        adc #7                      // carry set: +8
!:      tay
        ldx s2_e0
        lda spread_hi_s,x
        ldx s2_e1
        ora spread_hi,x
        sta (ed_ptr2),y
        ldx s2_e0
        lda spread_lo_s,x
        ldx s2_e1
        ora spread_lo,x
        pha
        tya
        clc
        adc #8
        tay
        pla
        sta (ed_ptr2),y
        tya
        sec
        sbc #7                      // next output row, left tile
        tay
        ldx s2_e2
        lda spread_hi_s,x
        ldx s2_e3
        ora spread_hi,x
        sta (ed_ptr2),y
        ldx s2_e2
        lda spread_lo_s,x
        ldx s2_e3
        ora spread_lo,x
        pha
        tya
        clc
        adc #8
        tay
        pla
        sta (ed_ptr2),y
        inc s2_row
        lda s2_row
        cmp #8
        beq !+
        jmp r2_row
!:      lda ed_ptr2                 // next glyph: 4 tiles
        clc
        adc #4 * 8
        sta ed_ptr2
        bcc !+
        inc ed_ptr2 + 1
!:      inc s2_glyph
        lda s2_glyph
        cmp #BIG_GLYPH_COUNT_2X2
        beq !+
        jmp r2_glyph
!:      lda #2
        sta cfg_big_w
        sta cfg_big_h
        lda #0
        sta cfg_big_mc
        rts

// A = c: P ^ (c & (L ^ P))
r2_left:
        sta s2_c
        lda s2_l
        eor s2_p
        and s2_c
        eor s2_p
        rts

// A = c: P ^ (c & (R ^ P))
r2_right:
        sta s2_c
        lda s2_r
        eor s2_p
        and s2_c
        eor s2_p
        rts

// spread tables: bit i of x -> bit 2i (and the same shifted left by one)
spread_init:
        ldx #0
!:      stx s2_c
        lda #0
        sta s2_l
        sta s2_r
        ldy #8
si_bit:
        asl s2_l
        rol s2_r
        asl s2_l
        rol s2_r
        asl s2_c
        bcc !+
        inc s2_l
!:      dey
        bne si_bit
        lda s2_l
        sta spread_lo,x
        lda s2_r
        sta spread_hi,x
        asl s2_l                    // bit 7 of lo is 0: no carry
        rol s2_r
        lda s2_l
        sta spread_lo_s,x
        lda s2_r
        sta spread_hi_s,x
        inx
        bne !--
        rts

ed_big_order:
        .fill BIG_GLYPH_COUNT_2X2, BIG_GLYPH_ORDER.get(i)
.errorif BIG_GLYPH_ORDER.size() != BIG_GLYPH_COUNT_2X2, "glyph order size"
