#importonce
// ---------------------------------------------------------------------------
// lists.asm - selection lists for music and fonts (rows 4-19).
// ---------------------------------------------------------------------------

// ==== music ===================================================================
ed_music:
        lda #LIST_MUSIC
        sta ed_list_kind
        ldx CATALOG + CAT_N_SIDS
        inx                         // + NO MUSIC
        stx ed_list_n
        jsr ed_list_run
        bcs lm_done
        cmp #0
        bne lm_catalog
        jsr ed_music_stop
        lda cfg_flags
        and #FLAG_ALL ^ FLAG_MUSIC
        sta cfg_flags
        lda #<str_no_music
        ldy #>str_no_music
        jmp ed_set_name_music
lm_catalog:
        sec
        sbc #1                      // catalog record
        sta ed_list_sel
        jsr ed_music_stop
        lda ed_list_sel
        jsr cat_rec_addr
        jsr disk_load_rec
        bcc !+
        lda cfg_flags               // load error: no music
        and #FLAG_ALL ^ FLAG_MUSIC
        sta cfg_flags
        lda #<str_no_music
        ldy #>str_no_music
        jmp ed_set_name_music
!:      lda ed_list_sel
        jsr cat_rec_addr
        ldy #CAT_INIT
        lda (ed_ptr),y
        sta cfg_init
        iny
        lda (ed_ptr),y
        sta cfg_init + 1
        iny
        lda (ed_ptr),y
        sta cfg_play
        iny
        lda (ed_ptr),y
        sta cfg_play + 1
        iny
        lda (ed_ptr),y
        sta cfg_subtune
        lda cfg_flags
        ora #FLAG_MUSIC
        sta cfg_flags
        ldx #0
        jsr ed_copy_rec_name
        jmp ed_music_start
lm_done:
        rts

// ==== fonts ===================================================================
ed_font:
        lda #LIST_FONT
        sta ed_list_kind
        ldx CATALOG + CAT_N_FONTS
        inx
        inx                         // + ROM, ROM BOLD
        stx ed_list_n
        jsr ed_list_run
        bcs lf_done
        cmp #FONT_BUILTIN_BOLD
        beq lf_bold
        bcs lf_catalog
        jsr font_copy_rom
lf_rom_name:
        lda #<str_font_rom
        ldy #>str_font_rom
        jmp ed_set_name_font
lf_bold:
        jsr font_bold_rom
        lda #<str_font_bold
        ldy #>str_font_bold
        jmp ed_set_name_font
lf_catalog:
        clc
        adc CATALOG + CAT_N_SIDS
        sec
        sbc #FONT_BUILTINS          // catalog record
        sta ed_list_sel
        jsr cat_rec_addr
        jsr disk_load_rec
        bcc !+
        jsr font_copy_rom           // load error: back to the ROM font
        jmp lf_rom_name
!:      lda ed_list_sel
        jsr cat_rec_addr
        ldx #CAT_NAME_LEN
        jmp ed_copy_rec_name
lf_done:
        rts

// X = 0 (music) or CAT_NAME_LEN (font): copy record name at ed_ptr
ed_copy_rec_name:
        ldy #CAT_NAME
!:      lda (ed_ptr),y
        sta ed_music_name,x
        inx
        iny
        cpy #CAT_NAME + CAT_NAME_LEN
        bne !-
        rts

// A = catalog record index -> ed_ptr
cat_rec_addr:
        sta ed_t0
        lda #0
        sta ed_t1
        ldx #4
!:      asl ed_t0                   // * 16
        rol ed_t1
        dex
        bne !-
        lda ed_t0
        sta ed_ptr
        lda ed_t1
        sta ed_ptr + 1
        asl ed_t0                   // * 32
        rol ed_t1
        lda ed_ptr                  // * 48 + catalog base
        clc
        adc ed_t0
        tax
        lda ed_ptr + 1
        adc ed_t1
        tay
        txa
        clc
        adc #<(CATALOG + CAT_RECORDS)
        sta ed_ptr
        tya
        adc #>(CATALOG + CAT_RECORDS)
        sta ed_ptr + 1
        rts
.errorif CAT_REC_SIZE != 48, "cat_rec_addr assumes 48 byte records"

// ==== generic list ============================================================
// ed_list_kind / ed_list_n set; returns carry clear + A = selection
// (RETURN) or carry set (RUN/STOP)
ed_list_run:
        lda #0
        sta ed_list_sel
        jsr ui_clear
        lda ed_list_kind
        bne !+
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_list_music)
        jmp !++
!:      Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_list_font)
!:      lda #<str_hint_list
        ldy #>str_hint_list
        jsr ui_hint
        ldx #0
!:      stx ed_t2
        txa
        clc
        adc #UI_LIST_ROW
        tay
        ldx #UI_LIST_COL
        jsr ui_goto
        lda #UI_COL_TEXT
        sta ed_color
        lda ed_t2
        jsr ed_list_entry
        ldx ed_t2
        inx
        cpx ed_list_n
        bne !-
        jsr el_mark
el_loop:
        jsr ui_getkey
        cmp #KEY_STOP
        bne !+
        sec
        rts
!:      cmp #KEY_RETURN
        bne !+
        lda ed_list_sel
        clc
        rts
!:      cmp #KEY_CRSR_DOWN
        bne !+
        ldx ed_list_sel
        inx
        cpx ed_list_n
        beq el_loop
        jsr el_mark
        inc ed_list_sel
        jsr el_mark
        jmp el_loop
!:      cmp #KEY_CRSR_UP
        bne el_loop
        lda ed_list_sel
        beq el_loop
        jsr el_mark
        dec ed_list_sel
        jsr el_mark
        jmp el_loop

// toggle the reverse bar on the selected row
el_mark:
        lda ed_list_sel
        clc
        adc #UI_LIST_ROW
        tay
        jmp ui_reverse_row

// A = entry index: print its name at the cursor
ed_list_entry:
        ldx ed_list_kind
        bne le_font
        cmp #0
        bne !+
        lda #<str_no_music
        ldy #>str_no_music
        jmp ui_puts
!:      sec
        sbc #1
        jmp le_record
le_font:
        cmp #FONT_BUILTIN_BOLD
        bcc !+
        bne !++
        lda #<str_font_bold
        ldy #>str_font_bold
        jmp ui_puts
!:      lda #<str_font_rom
        ldy #>str_font_rom
        jmp ui_puts
!:      clc
        adc CATALOG + CAT_N_SIDS
        sec
        sbc #FONT_BUILTINS
le_record:
        jsr cat_rec_addr            // keeps ed_scr/ed_colp
        lda ed_ptr
        sta ed_str
        lda ed_ptr + 1
        sta ed_str + 1
        ldx #CAT_NAME_LEN
        jmp ui_putn

str_list_music: Str("MUSIC")
str_list_font:  Str("FONT")
str_hint_list:  Str("CRSR SELECT  RETURN OK  STOP BACK")
