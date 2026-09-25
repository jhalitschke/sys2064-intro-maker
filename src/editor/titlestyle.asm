#importonce
// ---------------------------------------------------------------------------
// titlestyle.asm - title style screen: big font, movement, speed, MC colours.
// ---------------------------------------------------------------------------

ed_title_style:
        jsr ed_draw_style
!:      jsr ui_getkey
        cmp #KEY_STOP
        bne !+
        rts
!:      sec
        sbc #KEY_1
        cmp #ED_STYLE_ITEMS
        bcs !--
        tax
        bne !+
        jsr ed_bigfont              // 1: big font list
        jmp ed_title_style
!:      dex
        bne !+
        ldx cfg_move                // 2: movement
        inx
        cpx #MOVE_COUNT
        bcc st_move
        ldx #MOVE_STATIC
st_move:
        stx cfg_move
        jmp ed_title_style
!:      dex
        bne !+
        ldx cfg_move_speed          // 3: speed 1-4
        cpx #MOVE_SPEED_MAX
        bcc st_speed
        ldx #0
st_speed:
        inx
        stx cfg_move_speed
        jmp ed_title_style
!:      dex                         // 4/5: MC colours
        lda cfg_big_mc1,x
        clc
        adc #1
        and #COLOR_COUNT - 1
        sta cfg_big_mc1,x
        jmp ed_title_style
.errorif CFG_BIG_MC2 != CFG_BIG_MC1 + 1, "MC colours must be adjacent"

ed_draw_style:
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_style)
        Print(0, UI_MENU_ROW + 0, UI_COL_TEXT, str_s_font)
        Print(0, UI_MENU_ROW + 1, UI_COL_TEXT, str_s_move)
        Print(0, UI_MENU_ROW + 2, UI_COL_TEXT, str_s_speed)
        Print(0, UI_MENU_ROW + 3, UI_COL_TEXT, str_s_mc1)
        Print(0, UI_MENU_ROW + 4, UI_COL_TEXT, str_s_mc2)
        lda #<str_hint_style
        ldy #>str_hint_style
        jsr ui_hint
        Goto(UI_BLOCK_COL, UI_MENU_ROW + 0, UI_COL_KEY)
        lda #<ed_bigfont_name
        sta ed_str
        lda #>ed_bigfont_name
        sta ed_str + 1
        ldx #CAT_NAME_LEN
        jsr ui_putn
        Goto(UI_BLOCK_COL, UI_MENU_ROW + 1, UI_COL_KEY)
        ldx cfg_move
        lda st_move_lo,x
        ldy st_move_hi,x
        jsr ui_puts
        Goto(UI_BLOCK_COL, UI_MENU_ROW + 2, UI_COL_KEY)
        lda cfg_move_speed
        jsr ui_putbyte
        ldx #0
!:      stx ed_t0
        txa
        clc
        adc #UI_MENU_ROW + 3
        tay
        ldx #UI_BLOCK_COL
        jsr ui_goto
        ldx ed_t0
        lda cfg_big_mc1,x
        sta ed_color
        lda #SC_REV_SPACE
        jsr ui_putc
        lda #SC_REV_SPACE
        jsr ui_putc
        lda #SC_SPACE
        jsr ui_putc
        lda #UI_COL_TEXT
        sta ed_color
        ldx ed_t0
        lda cfg_big_mc1,x
        jsr ui_putbyte
        ldx ed_t0
        inx
        cpx #2
        bne !-
        // characters per title line with this font
        lda cfg_big_w
        beq !+
        Print(0, UI_MENU_ROW + 6, UI_COL_TEXT, str_s_chars)
        ldx cfg_big_w
        lda ti_max_glyphs - 1,x
        jsr ui_putbyte
        lda cfg_big_mc
        beq !+
        Print(0, UI_MENU_ROW + 7, UI_COL_TEXT, str_s_mc_font)
!:      rts

// ==== big font list =============================================================
// entries: NONE (1X1), ROM 2X2, catalog big fonts, FROM DISK...
ed_bigfont:
        lda #LIST_BIGFONT
        sta ed_list_kind
        ldx CATALOG + CAT_N_BIGFONTS
        inx
        inx                         // + NONE, ROM 2X2
        inx                         // + FROM DISK
        stx ed_list_n
        jsr ed_list_run
        bcs bf_done
        cmp #BIG_BUILTIN_ROM2X2
        beq bf_rom
        bcs bf_more
        lda #0                      // none: 1x1 with the scroll font
        sta cfg_big_w
        sta cfg_big_h
        sta cfg_big_mc
        lda #<str_big_none
        ldy #>str_big_none
        jmp ed_set_name_bigfont
bf_rom:
        jsr font_rom2x2
        lda #<str_big_rom
        ldy #>str_big_rom
        jmp ed_set_name_bigfont
bf_more:
        jsr le_last
        beq bf_disk
        clc                         // catalog record
        adc CATALOG + CAT_N_SIDS
        adc CATALOG + CAT_N_FONTS
        sec
        sbc #BIG_BUILTINS
        sta ed_list_sel
        jsr cat_rec_addr
        ldy #CAT_FNLEN
        lda (ed_ptr),y
        sta ed_file_len
        ldy #CAT_FNAME
        ldx #0
!:      lda (ed_ptr),y
        sta ed_file_name_buf,x
        iny
        inx
        cpx #FNAME_MAX
        bne !-
        jsr disk_read_file
        bcs bf_done
        jsr bigfont_from_buffer
        bcs bf_done
        lda ed_list_sel
        jsr cat_rec_addr
        ldx #CAT_NAME_LEN * 2
        jmp ed_copy_rec_name
bf_disk:
        jsr ed_pick_file
        bcs bf_done
        jsr disk_read_file
        bcs bf_done
        jsr bigfont_from_buffer
        bcs bf_done
        jmp ed_file_name_bigfont
bf_done:
        rts

bfb_bad:
        lda #<str_err_bigfont
        ldy #>str_err_bigfont
        jsr ed_status_set
        sec
        rts

// FILE_BUF holds a big font file (see docs): copy tiles, map, size and
// colours. Carry set on error.
bigfont_from_buffer:
        lda FILE_BUF + 2
        cmp #BIG_MAGIC_0
        bne bfb_bad
        lda FILE_BUF + 3
        cmp #BIG_MAGIC_1
        bne bfb_bad
        lda FILE_BUF + BIG_OFS_W    // 1 <= W, H <= 4
        beq bfb_bad
        cmp #BIG_SIZE_MAX + 1
        bcs bfb_bad
        lda FILE_BUF + BIG_OFS_H
        beq bfb_bad
        cmp #BIG_SIZE_MAX + 1
        bcs bfb_bad
        lda FILE_BUF + BIG_OFS_N    // tiles
        cmp #BIG_TILE_MAX + 1
        bcs bfb_bad
        // needed length: BIG_FILE_TILES + n * 8
        sta ed_t0
        lda #0
        sta ed_t1
        ldx #3
!:      asl ed_t0
        rol ed_t1
        dex
        bne !-
        lda ed_t0
        clc
        adc #BIG_FILE_TILES
        sta ed_t2
        lda ed_t1
        adc #0
        sta ed_t3
        lda ed_buf_len              // buf_len >= needed
        cmp ed_t2
        lda ed_buf_len + 1
        sbc ed_t3
        bcc bfb_bad
        // copy tiles (n * 8 bytes)
        lda #<(FILE_BUF + BIG_FILE_TILES)
        sta ed_ptr
        lda #>(FILE_BUF + BIG_FILE_TILES)
        sta ed_ptr + 1
        lda #<BIG_TILES
        sta ed_ptr2
        lda #>BIG_TILES
        sta ed_ptr2 + 1
        jsr mem_copy_down           // ed_t0/1 bytes
        ldx #BIG_GLYPHS - 1
!:      lda FILE_BUF + BIG_OFS_MAP,x
        sta cfg_big_map,x
        dex
        bpl !-
        lda FILE_BUF + BIG_OFS_W
        sta cfg_big_w
        lda FILE_BUF + BIG_OFS_H
        sta cfg_big_h
        lda FILE_BUF + BIG_OFS_FLAGS
        and #BIG_FLAG_MC
        sta cfg_big_mc
        beq !+
        lda FILE_BUF + BIG_OFS_MC1
        sta cfg_big_mc1
        lda FILE_BUF + BIG_OFS_MC2
        sta cfg_big_mc2
!:      clc
        rts

st_move_lo:     .byte <str_mv_static, <str_mv_swing, <str_mv_sine, <str_mv_eight, <str_mv_bumper
st_move_hi:     .byte >str_mv_static, >str_mv_swing, >str_mv_sine, >str_mv_eight, >str_mv_bumper
.errorif * - st_move_hi != MOVE_COUNT, "movement names"

str_style:      Str("TITLE STYLE")
str_s_font:     Str("1 BIG FONT")
str_s_move:     Str("2 MOVEMENT")
str_s_speed:    Str("3 MOVE SPEED")
str_s_mc1:      Str("4 MC COLOR 1")
str_s_mc2:      Str("5 MC COLOR 2")
str_s_chars:    Str("TITLE CHARS PER LINE: ")
str_s_mc_font:  Str("MULTICOLOR FONT: TITLE COLOR 0-7")
str_hint_style: Str("1-5 CHANGE  STOP BACK")
str_mv_static:  Str("STATIC")
str_mv_swing:   Str("SWING ")
str_mv_sine:    Str("SINE  ")
str_mv_eight:   Str("EIGHT ")
str_mv_bumper:  Str("BUMPER")
str_big_none:   Str("NONE (1X1)")
str_big_rom:    Str("ROM 2X2")
str_list_big:   Str("BIG FONT")
str_err_bigfont: Str("NOT A BIG FONT FILE")
