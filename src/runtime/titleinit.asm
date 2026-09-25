#importonce
// ---------------------------------------------------------------------------
// titleinit.asm - title layout from the config: glyph size, line lengths,
// movement ranges, colours (see title.asm for the per frame part).
// ---------------------------------------------------------------------------

// ---- init (runtime_start) --------------------------------------------------
title_init:
        ldx #1                      // 1x1: the scroll font, no map
        stx rt_gw
        stx rt_gh
        dex
        stx rt_mc
        lda cfg_big_w
        beq !+
        sta rt_gw
        lda cfg_big_h
        sta rt_gh
        lda cfg_big_mc
        sta rt_mc
!:      // glyph count per line: last non-space within 40 / W glyphs
        ldx rt_gw
        lda ti_max_glyphs - 1,x
        sta rt_t0
        ldy rt_t0
!:      lda cfg_title - 1,y
        cmp #SC_SPACE
        bne !+
        dey
        bne !-
!:      sty rt_len
        ldy rt_t0
!:      lda cfg_title + TITLE_LINE_LEN - 1,y
        cmp #SC_SPACE
        bne !+
        dey
        bne !-
!:      sty rt_len + 1
        // lines, widest line
        ldx #1
        lda rt_len + 1
        beq !+
        inx
!:      stx rt_lines
        lda rt_len
        cmp rt_len + 1
        bcs !+
        lda rt_len + 1
!:      sta rt_maxlen
        // per line x offset: big fonts centred, (maxlen - len) * W / 2;
        // 1x1 titles stay as typed
        ldx #1
!:      lda #0
        ldy cfg_big_w
        beq !+
        lda rt_maxlen
        sec
        sbc rt_len,x
        jsr ti_times_w
        lsr
!:      sta rt_off,x
        dex
        bpl !--
        // rx = (40 - maxlen * W) * 8
        lda rt_maxlen
        jsr ti_times_w
        sta rt_wchars
        sta rt_t0
        lda #SCREEN_COLS
        sec
        sbc rt_t0
        bcs !+
        lda #0
!:      sta rt_rx
        lda #0
        sta rt_rx + 1
        ldx #3
!:      asl rt_rx
        rol rt_rx + 1
        dex
        bne !-
        // rows = lines * H, ry = 72 - rows * 8
        lda rt_gh
        ldx rt_lines
        cpx #2
        bne !+
        asl
!:      sta rt_rows
        asl
        asl
        asl
        sta rt_t0
        lda #BAND_LINES
        sec
        sbc rt_t0
        bcs !+
        lda #0
!:      sta rt_ry
        // colours: title colour in all band rows, MC colours
        lda cfg_titlecol
        jsr ti_colour
        ldx #0
!:      sta BAND_COLOR,x
        sta BAND_COLOR + BAND_ROWS * SCREEN_COLS - $100,x
        inx
        bne !-
        lda cfg_big_mc1
        sta VIC_BG1
        lda cfg_big_mc2
        sta VIC_BG2
        // colour cycle row: cyc table repeated, MC bit applied
        ldx #CYC_EXT_LEN - 1
!:      txa
        and #CYC_LEN - 1
        tay
        lda rt_cyc_tab,y
        jsr ti_colour
        sta rt_cyc_ext,x
        dex
        bpl !-
        // start: bumper in the middle, force a redraw
        lda rt_rx + 1
        lsr
        sta rt_bx + 1
        lda rt_rx
        ror
        sta rt_bx
        lda #0
        sta rt_bdir
        sta rt_mv_phase
        sta rt_pending
        jsr title_draw_img
        lda #$ff
        sta rt_cur_row
        jsr title_update
        jmp title_apply

// A * W (small numbers)
ti_times_w:
        ldy rt_gw
        sta rt_t1
        lda #0
!:      clc
        adc rt_t1
        dey
        bne !-
        rts

// A = colour -> colour RAM value (MC fonts: colours 0-7 + MC bit)
ti_colour:
        ldy rt_mc
        beq !+
        and #COLRAM_MC - 1
        ora #COLRAM_MC
!:      rts

ti_max_glyphs:  .byte 40, 20, 13, 10            // 40 / W
ti_line_ofs:    .byte 0, TITLE_LINE_LEN
.errorif BIG_SIZE_MAX != 4, "ti_max_glyphs has 4 entries"


// ---- title image (TITLE_IMG, stride 40) -----------------------------------
title_draw_img:
        // clear the image
        lda #SC_SPACE
        ldx #0
!:      sta TITLE_IMG,x
        sta TITLE_IMG + TITLE_IMG_SIZE - $100,x
        inx
        bne !-
        // lines
        lda #0
        sta rt_t3                   // line
tr_line:
        ldx rt_t3
        lda rt_len,x
        beq tr_next_line
        sta rt_t2                   // glyphs left
        lda ti_line_ofs,x
        sta rt_ptr2                 // title index
        lda rt_off,x
        sta rt_ptr2 + 1             // image column
        // first row of this line: line * H
        lda #0
        cpx #0
        beq !+
        lda rt_gh
!:      sta rt_t0
tr_glyph:
        ldx rt_ptr2
        lda cfg_title,x
        ldx cfg_big_w
        bne tr_big
        // 1x1: the screen code itself
        ldy rt_t0
        jsr tr_row_ptr
        ldy rt_ptr2 + 1
        sta (rt_ptr),y
        jmp tr_glyph_next
tr_big:
        tax
        lda cfg_big_map,x
        sta rt_t1                   // first tile or 0 (blank)
        lda rt_t0
        pha
        lda rt_gh
        sta rt_mv_tmp               // rows left
tr_tile_row:
        ldy rt_t0
        jsr tr_row_ptr
        ldx rt_gw
        ldy rt_ptr2 + 1
!:      lda rt_t1
        beq tr_blank
        sta (rt_ptr),y
        inc rt_t1                   // row-major tiles of this glyph
        jmp tr_tile_next
tr_blank:
        lda #SC_SPACE
        sta (rt_ptr),y
tr_tile_next:
        iny
        dex
        bne !-
        inc rt_t0
        dec rt_mv_tmp
        bne tr_tile_row
        pla
        sta rt_t0
        lda rt_ptr2 + 1             // next glyph column: + W - 1 (+1 below)
        clc
        adc rt_gw
        sec
        sbc #1
        sta rt_ptr2 + 1
tr_glyph_next:
        inc rt_ptr2
        inc rt_ptr2 + 1
        dec rt_t2
        bne tr_glyph
tr_next_line:
        inc rt_t3
        lda rt_t3
        cmp rt_lines
        beq !+
        jmp tr_line
!:      rts

// Y = image row -> rt_ptr (keeps A, X, Y)
tr_row_ptr:
        pha
        lda ti_img_lo,y
        sta rt_ptr
        lda ti_img_hi,y
        sta rt_ptr + 1
        pla
        rts

ti_img_lo:      .fill BAND_ROWS, <(TITLE_IMG + i * SCREEN_COLS)
ti_img_hi:      .fill BAND_ROWS, >(TITLE_IMG + i * SCREEN_COLS)
