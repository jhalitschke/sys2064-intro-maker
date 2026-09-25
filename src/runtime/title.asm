#importonce
// ---------------------------------------------------------------------------
// title.asm - title in the band rows 0-8: 1x1 (scroll font) or big font
// (W x H tiles per glyph), moved by XSCROLL/YSCROLL (fine) and by
// re-drawing at another screen position (coarse).
// Band pixel position: px 0..rx, py 0..ry (py 0 = raster line 48).
// ---------------------------------------------------------------------------

// ---- per frame (IRQ BOTTOM) ------------------------------------------------
// Budget: movement ~400 cycles, re-draw (coarse change only) up to ~4000.
title_update:
        lda rt_mv_phase
        clc
        adc cfg_move_speed
        sta rt_mv_phase
        // defaults: centred (1x1 static: as typed, x = 0), static height
        lda rt_rx + 1
        lsr
        sta rt_px + 1
        lda rt_rx
        ror
        sta rt_px
        lda cfg_big_w
        ora cfg_move
        bne !+
        sta rt_px
        sta rt_px + 1
!:
        lda #TITLE_STATIC_Y
        cmp rt_ry
        bcc !+
        lda rt_ry
!:      sta rt_py
        ldx cfg_move
        cpx #MOVE_SWING
        beq tu_swing
        cpx #MOVE_SINE
        beq tu_sine
        cpx #MOVE_EIGHT
        beq tu_eight
        cpx #MOVE_BUMPER
        beq tu_bumper
        jmp tu_place
tu_eight:
        lda rt_mv_phase
        asl
        jsr tu_y_sine
tu_swing:
        lda rt_mv_phase
        jsr tu_x_sine
        jmp tu_place
tu_sine:
        lda rt_mv_phase
        jsr tu_y_sine
        jmp tu_place
tu_bumper:
        // y: bounce, ry - |sin| * ry
        lda rt_mv_phase
        jsr tu_sin_abs
        ldx rt_ry
        jsr tu_mul
        sta rt_t0
        lda rt_ry
        sec
        sbc rt_t0
        sta rt_py
        // x: back and forth between the walls
        lda rt_bdir
        bne tu_left
        lda rt_bx
        clc
        adc cfg_move_speed
        sta rt_bx
        bcc !+
        inc rt_bx + 1
!:      lda rt_rx                   // bx >= rx: turn
        cmp rt_bx
        lda rt_rx + 1
        sbc rt_bx + 1
        bcs tu_bx_done
        lda rt_rx
        sta rt_bx
        lda rt_rx + 1
        sta rt_bx + 1
        inc rt_bdir
        bne tu_bx_done
tu_left:
        lda rt_bx
        sec
        sbc cfg_move_speed
        sta rt_bx
        bcs tu_bx_done
        dec rt_bx + 1
        bpl tu_bx_done
        lda #0                      // below 0: turn
        sta rt_bx
        sta rt_bx + 1
        sta rt_bdir
tu_bx_done:
        lda rt_bx
        sta rt_px
        lda rt_bx + 1
        sta rt_px + 1

tu_place:
        // next position, applied by the main loop (title_apply)
        lda rt_pending
        beq !+
        rts                         // last one not applied yet
!:      lda rt_px
        and #7
        ora #RT_D016
        ldx rt_mc
        beq !+
        ora #D016_MC
!:      sta rt_next_d016
        lda rt_py
        and #7
        ora #D011_BASE
        sta rt_next_d011
        // coarse position: px / 8, py / 8
        lda rt_px + 1
        lsr
        lda rt_px
        ror
        lsr
        lsr
        tax
        stx rt_next_col
        lda rt_py
        lsr
        lsr
        lsr
        sta rt_next_row
        inc rt_pending
        rts

// main loop: draw at the next position if it moved, then activate the
// fine scroll values (TOP uses them) together with the new drawing
title_apply:
        lda rt_pending
        beq ta_done
        ldx rt_next_col
        lda rt_next_row
        cmp rt_cur_row
        bne !+
        cpx rt_cur_col
        beq ta_fine
!:      jsr title_render
ta_fine:
        lda rt_next_d011
        sta rt_title_d011
        lda rt_next_d016
        sta rt_title_d016
        lda #0
        sta rt_pending
ta_done:
        rts

// A = sine phase: px = cx + sin * cx / 128 (px holds cx <= 156 on entry)
tu_x_sine:
        jsr tu_sin_abs
        ldx rt_px
        jsr tu_mul
        sta rt_t0
        lda rt_t3
        bmi !+
        lda rt_px
        clc
        adc rt_t0
        sta rt_px
        bcc tu_x_done
        inc rt_px + 1
        rts
!:      lda rt_px
        sec
        sbc rt_t0
        sta rt_px
        bcs tu_x_done
        dec rt_px + 1
tu_x_done:
        rts

// A = sine phase: py = cy + sin * cy / 128
tu_y_sine:
        jsr tu_sin_abs
        pha
        lda rt_ry
        lsr
        sta rt_py                   // cy
        tax
        pla
        jsr tu_mul
        sta rt_t0
        lda rt_t3
        bmi !+
        lda rt_py
        clc
        adc rt_t0
        sta rt_py
        rts
!:      lda rt_py
        sec
        sbc rt_t0
        sta rt_py
        rts

// A = phase -> A = |sin|, rt_t3 = sin (sign)
tu_sin_abs:
        and #SIN_LEN - 1
        tax
        and #SIN_LEN / 2            // second half wave: negative
        asl
        sta rt_t3
        txa
        and #SIN_LEN / 2 - 1
        tax
        lda mv_sin,x
        rts

// A (0..127) * X (0..255) / 128 -> A   (shift-add, ~150 cycles)
tu_mul:
        sta rt_t1
        stx rt_t2
        lda #0
        ldx #8
        lsr rt_t1
!:      bcc !+
        clc
        adc rt_t2
!:      ror
        ror rt_t1
        dex
        bne !--
        asl rt_t1                   // product / 128: hi * 2 + bit 7 of lo
        rol
        rts

// ---- move the drawn title to column X, row A (main loop) ------------------
// Rewrites the band rows between the old and the new position from the
// title image: ~550 cycles per row.
title_render:
        stx rt_t2                   // new column
        sta rt_t3                   // new row
        // rows min(old, new) .. max(old, new) + rows - 1
        tay
        ldx rt_cur_row
        bmi !+                      // nothing drawn yet
        cpx rt_t3
        bcs !+
        ldy rt_cur_row
!:      sty rt_t0                   // first row
        lda rt_t3
        ldx rt_cur_row
        bmi !+
        cpx rt_t3
        bcc !+
        txa
!:      clc
        adc rt_rows
        sta rt_t1                   // behind the last row
        lda rt_t2
        sta rt_cur_col
        lda rt_t3
        sta rt_cur_row
        clc                         // right edge of the image columns
        lda rt_t2
        adc rt_wchars
        sta rt_mv_tmp
tb_row:
        ldy rt_t0
        lda tr_row_lo,y
        sta rt_ptr
        lda tr_row_hi,y
        sta rt_ptr + 1
        tya                         // image row = band row - new row
        sec
        sbc rt_cur_row
        bcc tb_blank_row
        cmp rt_rows
        bcs tb_blank_row
        tay
        lda ti_img_lo,y             // source = image row - new column
        sec
        sbc rt_cur_col
        sta rt_ptr2
        lda ti_img_hi,y
        sbc #0
        sta rt_ptr2 + 1
        ldy #0
        lda #SC_SPACE
!:      cpy rt_cur_col              // left of the title
        bcs !+
        sta (rt_ptr),y
        iny
        bne !-
!:      cpy rt_mv_tmp               // the title
        bcs !+
        lda (rt_ptr2),y
        sta (rt_ptr),y
        iny
        bne !-
!:      lda #SC_SPACE
        bne tb_fill
tb_blank_row:
        ldy #0
        lda #SC_SPACE
tb_fill:
!:      cpy #SCREEN_COLS            // right of the title
        bcs !+
        sta (rt_ptr),y
        iny
        bne !-
!:      inc rt_t0
        lda rt_t0
        cmp rt_t1
        bne tb_row
        rts

tr_row_lo:      .fill BAND_ROWS, <(SCREEN + i * SCREEN_COLS)
tr_row_hi:      .fill BAND_ROWS, >(SCREEN + i * SCREEN_COLS)
