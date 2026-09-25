#importonce
// ---------------------------------------------------------------------------
// editor.asm - start, main menu, colours, effects, preview.
// ---------------------------------------------------------------------------

editor_start:
        lda KERNAL_DEV
        cmp #MIN_DRIVE
        bcs !+
        lda #MIN_DRIVE
!:      sta ed_dev
        lda #0
        sta ed_music_on
        jsr SETMSG                  // A = 0: no KERNAL messages
        lda #1
        sta KERNAL_BLNSW            // no KERNAL cursor
        jsr font_copy_rom
        jsr ed_config_defaults
        lda #TEXT_END_MARK
        sta TEXT
        lda #0
        sta ed_text_len
        sta ed_text_len + 1
        sta VIC_IDLE_BYTE
        sta CATALOG + CAT_N_SIDS
        sta CATALOG + CAT_N_FONTS
        sta CATALOG + CAT_N_BIGFONTS
        jsr ed_status_clear
        jsr ed_names_default
        jsr ed_irq_install
        jsr ui_init
        jsr disk_load_catalog

ed_main:
        jsr ed_draw_menu
!:      jsr ui_getkey
        cmp #KEY_0                  // "0" is the 10th entry
        bne !+
        lda #KEY_1 + ED_MENU_ITEMS - 1
!:      sec
        sbc #KEY_1
        cmp #ED_MENU_ITEMS
        bcs !--
        jsr ed_dispatch
        jmp ed_main

// A = menu index -> handler (returns with rts)
ed_dispatch:
        asl
        tax
        lda ed_menu_table + 1,x
        pha
        lda ed_menu_table,x
        pha
        rts

ed_menu_table:
        .word ed_music - 1
        .word ed_font - 1
        .word ed_colors - 1
        .word ed_effects - 1
        .word ed_title - 1
        .word ed_title_style - 1
        .word ed_scrolltext - 1
        .word ed_link - 1
        .word ed_preview - 1
        .word ed_save - 1
.errorif (* - ed_menu_table) / 2 != ED_MENU_ITEMS, "menu table size"

// ---- defaults ------------------------------------------------------------
ed_config_defaults:
        ldx #CFG_SIZE               // > 128 bytes: count down to 1
!:      lda ed_default_cfg - 1,x
        sta CONFIG - 1,x
        dex
        bne !-
        rts

ed_default_cfg:
        .encoding "petscii_upper"
        .text "IM"
        .byte CFG_VERSION_2, DEF_FLAGS, DEF_BORDER, DEF_BG, DEF_SCROLLCOL
        .byte DEF_TITLECOL, DEF_PRESET, DEF_SPEED
        .word DEF_INIT, DEF_PLAY
        .byte DEF_SUBTUNE, 0
        .fill TITLE_LEN, SC_SPACE
        .byte 0, 0, 0                   // 1x1 title, hires
        .byte DEF_BIG_MC1, DEF_BIG_MC2, DEF_MOVE, DEF_MOVE_SPEED, 0
        .word 0, 0, 0                   // no linked program
        .fill CFG_BIG_MAP - CFG_LINK_START - 2, 0
        .fill BIG_GLYPHS, 0
.errorif * - ed_default_cfg != CFG_SIZE, "default config size"

ed_names_default:
        lda #<str_no_music
        ldy #>str_no_music
        jsr ed_set_name_music
        lda #<str_big_none
        ldy #>str_big_none
        jsr ed_set_name_bigfont
        lda #<str_font_rom
        ldy #>str_font_rom
        jmp ed_set_name_font

// A/Y = STR_END string -> ed_music_name / ed_font_name /
// ed_bigfont_name (padded)
ed_set_name_music:
        ldx #0
        beq ed_set_name
ed_set_name_font:
        ldx #CAT_NAME_LEN
        bne ed_set_name
ed_set_name_bigfont:
        ldx #CAT_NAME_LEN * 2
ed_set_name:
        sta ed_str
        sty ed_str + 1
        ldy #0
!:      lda (ed_str),y
        cmp #STR_END
        beq !+
        sta ed_music_name,x
        inx
        iny
        cpy #CAT_NAME_LEN
        bne !-
        rts
!:      lda #SC_SPACE
!:      sta ed_music_name,x
        inx
        iny
        cpy #CAT_NAME_LEN
        bne !-
        rts

ed_status_clear:
        lda #SC_SPACE
        ldx #SCREEN_COLS - 1
!:      sta ed_status_buf,x
        dex
        bpl !-
        rts

// ---- main menu -------------------------------------------------------------
ed_draw_menu:
        jsr ui_clear
        Print(12, UI_HEAD_ROW, UI_COL_HEAD, str_head)
        Print(0, UI_MENU_ROW + 0, UI_COL_TEXT, str_m_music)
        Print(0, UI_MENU_ROW + 1, UI_COL_TEXT, str_m_font)
        Print(0, UI_MENU_ROW + 2, UI_COL_TEXT, str_m_colors)
        Print(0, UI_MENU_ROW + 3, UI_COL_TEXT, str_m_effects)
        Print(0, UI_MENU_ROW + 4, UI_COL_TEXT, str_m_title)
        Print(0, UI_MENU_ROW + 5, UI_COL_TEXT, str_m_style)
        Print(0, UI_MENU_ROW + 6, UI_COL_TEXT, str_m_text)
        Print(0, UI_MENU_ROW + 7, UI_COL_TEXT, str_m_link)
        Print(0, UI_MENU_ROW + 8, UI_COL_TEXT, str_m_preview)
        Print(0, UI_MENU_ROW + 9, UI_COL_TEXT, str_m_save)
        // values
        Goto(UI_VALUE_COL, UI_MENU_ROW + 0, UI_COL_KEY)
        lda #<ed_music_name
        sta ed_str
        lda #>ed_music_name
        sta ed_str + 1
        ldx #CAT_NAME_LEN
        jsr ui_putn
        Goto(UI_VALUE_COL, UI_MENU_ROW + 1, UI_COL_KEY)
        lda #<ed_font_name
        sta ed_str
        lda #>ed_font_name
        sta ed_str + 1
        ldx #CAT_NAME_LEN
        jsr ui_putn
        Goto(UI_VALUE_COL + 5, UI_MENU_ROW + 5, UI_COL_KEY)
        lda #<ed_bigfont_name
        sta ed_str
        lda #>ed_bigfont_name
        sta ed_str + 1
        ldx #CAT_NAME_LEN
        jsr ui_putn
        jsr ed_draw_link_value
        Goto(UI_TEXTLEN_COL, UI_MENU_ROW + 6, UI_COL_TEXT)
        lda #SC_PAREN_OPEN
        jsr ui_putc
        lda ed_text_len
        sta ed_num
        lda ed_text_len + 1
        sta ed_num + 1
        jsr ui_putdec
        lda #<str_max_len
        ldy #>str_max_len
        jsr ui_puts
        // number keys highlighted
        ldx #0
!:      txa
        clc
        adc #UI_MENU_ROW
        tay
        txa
        pha
        ldx #0
        jsr ui_goto
        ldy #0
        lda #UI_COL_KEY
        sta (ed_colp),y
        pla
        tax
        inx
        cpx #ED_MENU_ITEMS
        bne !-
        // status line
        Goto(0, UI_STATUS_ROW, UI_COL_STATUS)
        lda #<ed_status_buf
        sta ed_str
        lda #>ed_status_buf
        sta ed_str + 1
        ldx #SCREEN_COLS
        jmp ui_putn

// ---- colours -----------------------------------------------------------------
ed_colors:
        jsr ed_draw_colors
!:      jsr ui_getkey
        cmp #KEY_STOP
        beq !++
        sec
        sbc #KEY_1
        cmp #ED_COLOR_ITEMS
        bcs !-
        tax
        lda cfg_border,x            // border, bg, scroller, title in a row
        clc
        adc #1
        and #COLOR_COUNT - 1
        sta cfg_border,x
        jmp ed_colors
!:      rts

.errorif CFG_TITLECOL - CFG_BORDER != ED_COLOR_ITEMS - 1, "colour entries must be consecutive"

ed_draw_colors:
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_colors)
        Print(0, UI_MENU_ROW + 0, UI_COL_TEXT, str_c_border)
        Print(0, UI_MENU_ROW + 1, UI_COL_TEXT, str_c_bg)
        Print(0, UI_MENU_ROW + 2, UI_COL_TEXT, str_c_scroll)
        Print(0, UI_MENU_ROW + 3, UI_COL_TEXT, str_c_title)
        lda #<str_hint_colors
        ldy #>str_hint_colors
        jsr ui_hint
        ldx #0
!:      stx ed_t0
        txa
        clc
        adc #UI_MENU_ROW
        tay
        ldx #UI_BLOCK_COL
        jsr ui_goto
        ldx ed_t0
        lda cfg_border,x
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
        lda cfg_border,x
        jsr ui_putbyte
        ldx ed_t0
        inx
        cpx #ED_COLOR_ITEMS
        bne !-
        rts

// ---- effects -----------------------------------------------------------------
ed_effects:
        jsr ed_draw_effects
!:      jsr ui_getkey
        cmp #KEY_STOP
        bne !+
        rts
!:      sec
        sbc #KEY_1
        cmp #ED_EFFECT_ITEMS
        bcs !--
        tax
        lda ed_effect_flag,x
        beq !+
        eor cfg_flags               // on/off entries
        sta cfg_flags
        jmp ed_effects
!:      cpx #ED_EFFECT_PRESET
        bne !+
        lda cfg_preset
        clc
        adc #1
        and #PRESET_COUNT - 1
        sta cfg_preset
        jmp ed_effects
!:      lda cfg_speed               // speed 1 -> 2 -> 4 -> 1
        asl
        cmp #MAX_SPEED + 1
        bcc !+
        lda #1
!:      sta cfg_speed
        jmp ed_effects

// flag per entry, 0 = special entry
ed_effect_flag:
        .byte FLAG_BARS, FLAG_BAR_SINE, 0, FLAG_SPRITES, FLAG_TITLE_CYCLE, 0
.errorif * - ed_effect_flag != ED_EFFECT_ITEMS, "effect table size"

ed_draw_effects:
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_effects)
        Print(0, UI_MENU_ROW + 0, UI_COL_TEXT, str_e_bars)
        Print(0, UI_MENU_ROW + 1, UI_COL_TEXT, str_e_sine)
        Print(0, UI_MENU_ROW + 2, UI_COL_TEXT, str_e_preset)
        Print(0, UI_MENU_ROW + 3, UI_COL_TEXT, str_e_sprites)
        Print(0, UI_MENU_ROW + 4, UI_COL_TEXT, str_e_cycle)
        Print(0, UI_MENU_ROW + 5, UI_COL_TEXT, str_e_speed)
        lda #<str_hint_effects
        ldy #>str_hint_effects
        jsr ui_hint
        ldx #0
ede_loop:
        stx ed_t0
        txa
        clc
        adc #UI_MENU_ROW
        tay
        ldx #UI_BLOCK_COL
        jsr ui_goto
        lda #UI_COL_KEY
        sta ed_color
        ldx ed_t0
        lda ed_effect_flag,x
        beq ede_value
        and cfg_flags
        beq !+
        lda #<str_on
        ldy #>str_on
        jmp ede_str
!:      lda #<str_off
        ldy #>str_off
ede_str:
        jsr ui_puts
        jmp ede_next
ede_value:
        cpx #ED_EFFECT_PRESET
        bne !+
        lda cfg_preset
        clc
        adc #1                      // presets shown as 1-8
        jsr ui_putbyte
        jmp ede_next
!:      lda cfg_speed
        jsr ui_putbyte
ede_next:
        ldx ed_t0
        inx
        cpx #ED_EFFECT_ITEMS
        bne ede_loop
        rts

// ---- preview -----------------------------------------------------------------
ed_preview:
        jsr ed_prepare_intro
        jsr ed_music_stop
        lda #1
        sta rt_preview
        jsr runtime_start
        jsr ed_irq_install
        jmp ui_init                 // editor stays silent

// $3fff = 0 and terminated text (preview and save)
ed_prepare_intro:
        lda #0
        sta VIC_IDLE_BYTE
        jsr ed_text_ptr_end
        lda #TEXT_END_MARK
        ldy #0
        sta (ed_ptr),y
        rts

// ed_ptr = TEXT + ed_text_len
ed_text_ptr_end:
        lda #<TEXT
        clc
        adc ed_text_len
        sta ed_ptr
        lda #>TEXT
        adc ed_text_len + 1
        sta ed_ptr + 1
        rts

// ---- strings -----------------------------------------------------------------
str_head:       Str("C64 INTRO MAKER")
str_m_music:    Str("1 MUSIC:")
str_m_font:     Str("2 FONT:")
str_m_colors:   Str("3 COLORS")
str_m_effects:  Str("4 EFFECTS")
str_m_title:    Str("5 TITLE")
str_m_style:    Str("6 TITLE STYLE")
str_m_text:     Str("7 SCROLLTEXT")
str_m_link:     Str("8 LINK PROGRAM")
str_m_preview:  Str("9 PREVIEW")
str_m_save:     Str("0 SAVE")
str_max_len:    Str("/5118)")
str_colors:     Str("COLORS")
str_c_border:   Str("1 BORDER")
str_c_bg:       Str("2 BACKGROUND")
str_c_scroll:   Str("3 SCROLLER")
str_c_title:    Str("4 TITLE")
str_hint_colors: Str("1-4 CHANGE  STOP BACK")
str_effects:    Str("EFFECTS")
str_e_bars:     Str("1 RASTER BARS")
str_e_sine:     Str("2 BAR SINE")
str_e_preset:   Str("3 BAR COLORS")
str_e_sprites:  Str("4 SPRITES")
str_e_cycle:    Str("5 TITLE CYCLE")
str_e_speed:    Str("6 SCROLL SPEED")
str_hint_effects: Str("1-6 CHANGE  STOP BACK")
str_on:         Str("ON ")
str_off:        Str("OFF")
str_no_music:   Str("NO MUSIC")
str_font_rom:   Str("ROM")
str_font_bold:  Str("ROM BOLD")
.errorif TEXT_MAX != 5118, "str_max_len must match TEXT_MAX"

