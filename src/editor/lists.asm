#importonce
// ---------------------------------------------------------------------------
// lists.asm - scrolling selection lists (music, fonts, disk directory).
// ---------------------------------------------------------------------------

// ==== music ===================================================================
// entries: NO MUSIC, catalog tunes, FROM DISK...
// The list stays open: RETURN loads a tune and plays it for auditioning,
// RUN/STOP leaves with the last loaded tune selected. The editor is silent
// everywhere else (the preview plays the tune itself).
ed_music:
        lda #0
        sta ed_music_sel
        sta ed_music_top
        jsr ed_status_clear
        jsr ed_music_start          // audition the selected tune
lm_list:
        lda #LIST_MUSIC
        sta ed_list_kind
        ldx CATALOG + CAT_N_SIDS
        inx                         // + NO MUSIC
        inx                         // + FROM DISK
        stx ed_list_n
        lda ed_music_sel
        sta ed_list_sel
        lda ed_music_top
        sta ed_list_top
        jsr ed_list_resume
        ldx ed_list_sel             // keep the position for the next round
        stx ed_music_sel
        ldx ed_list_top
        stx ed_music_top
        bcc !+
        jmp ed_music_stop           // RUN/STOP: silent, tune stays selected
!:      pha
        jsr ed_status_clear
        pla
        cmp #0
        beq lm_none
        jsr le_last
        beq lm_disk
        sec
        sbc #1                      // catalog record
        sta ed_list_sel
        jsr ed_music_stop
        lda ed_list_sel
        jsr cat_rec_addr
        jsr disk_load_rec
        bcs lm_none                 // load error: no music
        lda ed_list_sel
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
        ldx #0
        jsr ed_copy_rec_name
lm_on:
        lda cfg_flags
        ora #FLAG_MUSIC
        sta cfg_flags
lm_play:
        jsr ed_music_start
        jmp lm_list
lm_none:
        jsr ed_music_stop
        lda cfg_flags
        and #FLAG_ALL ^ FLAG_MUSIC
        sta cfg_flags
        lda #<str_no_music
        ldy #>str_no_music
        jsr ed_set_name_music
        jmp lm_list
lm_disk:
        jsr ed_music_stop           // silent while browsing
        jsr ed_pick_file
        bcs lm_play                 // cancelled: the selected tune again
        jsr disk_read_file
        bcs lm_play                 // old tune untouched
        jsr sid_from_buffer         // copies to $1000
        bcs lm_play                 // invalid file: old tune
        jmp lm_on

// ==== fonts ===================================================================
// entries: ROM, ROM BOLD, catalog fonts, FROM DISK...
ed_font:
        lda #LIST_FONT
        sta ed_list_kind
        ldx CATALOG + CAT_N_FONTS
        inx
        inx                         // + ROM, ROM BOLD
        inx                         // + FROM DISK
        stx ed_list_n
        jsr ed_list_run
        bcs lf_done
        cmp #FONT_BUILTIN_BOLD
        beq lf_bold
        bcs lf_more
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
lf_more:
        ldx ed_list_n
        dex
        stx ed_t0
        cmp ed_t0
        beq lf_disk
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
lf_disk:
        jsr ed_pick_file
        bcs lf_done
        jsr disk_read_file
        bcs lf_done
        jsr font_from_buffer
        bcs lf_done
        jmp ed_file_name_font
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

// picked file name (ed_file_name/len) -> music / font / big font name
ed_file_name_music:
        ldx #0
        beq ed_file_name
ed_file_name_font:
        ldx #CAT_NAME_LEN
        bne ed_file_name
ed_file_name_bigfont:
        ldx #CAT_NAME_LEN * 2
ed_file_name:
        ldy #0
!:      lda #SC_SPACE
        cpy ed_file_len
        bcs !+
        lda ed_file_name_buf,y
        jsr ui_pet2sc
        bcc !+
        lda #SC_UNKNOWN & SC_MAX
!:      sta ed_music_name,x
        inx
        iny
        cpy #CAT_NAME_LEN
        bne !--
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

// ==== disk directory ==========================================================
// read the directory and let the user pick a PRG file.
// Carry clear: ed_file_name_buf / ed_file_len hold the name.
ed_pick_file:
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_list_disk)
        lda #<str_reading_dir
        ldy #>str_reading_dir
        jsr ui_status
        jsr disk_read_dir
        bcs pf_cancel
        lda ed_dir_n
        bne !+
        lda #<str_no_files
        ldy #>str_no_files
        jsr ed_status_set
        sec
        rts
!:      sta ed_list_n
        lda #LIST_FILES
        sta ed_list_kind
        jsr ed_list_run
        bcs pf_cancel
        jsr dir_entry_addr          // ed_ptr = name, A = length
        sta ed_file_len
        tay
        dey
!:      lda (ed_ptr),y
        sta ed_file_name_buf,y
        dey
        bpl !-
        clc
pf_cancel:
        rts

// A = directory index -> ed_ptr = name, A = name length
dir_entry_addr:
        pha
        jsr dir_name_ptr
        pla
        tax
        lda DIR_LENS,x
        rts

// ==== generic scrolling list ==================================================
// ed_list_kind / ed_list_n set; returns carry clear + A = selection
// (RETURN) or carry set (RUN/STOP)
ed_list_run:
        lda #0
        sta ed_list_sel
        sta ed_list_top
// (same with ed_list_sel / ed_list_top kept)
ed_list_resume:
        jsr ui_clear
        ldx ed_list_kind
        lda el_head_lo,x
        ldy el_head_hi,x
        pha
        tya
        pha
        Goto(0, UI_HEAD_ROW, UI_COL_HEAD)
        pla
        tay
        pla
        jsr ui_puts
        lda #<str_hint_list
        ldy #>str_hint_list
        jsr ui_hint
        Goto(0, UI_STATUS_ROW, UI_COL_STATUS)   // last message (load errors)
        lda #<ed_status_buf
        sta ed_str
        lda #>ed_status_buf
        sta ed_str + 1
        ldx #SCREEN_COLS
        jsr ui_putn
el_redraw:
        jsr el_draw
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
        stx ed_list_sel
        txa
        sec
        sbc ed_list_top
        cmp #UI_LIST_ROWS
        bcc el_redraw
        inc ed_list_top
        jmp el_redraw
!:      cmp #KEY_CRSR_UP
        bne el_loop
        lda ed_list_sel
        beq el_loop
        dec ed_list_sel
        lda ed_list_sel
        cmp ed_list_top
        bcs el_redraw
        sta ed_list_top
        jmp el_redraw

// draw the visible window, selected row reversed
el_draw:
        lda #0
        sta ed_t2                   // window row
!:      lda ed_t2
        clc
        adc #UI_LIST_ROW
        tay
        jsr ui_clear_row
        lda ed_t2
        clc
        adc ed_list_top
        cmp ed_list_n
        bcs el_next
        sta ed_t3                   // entry index
        lda ed_t2
        clc
        adc #UI_LIST_ROW
        tay
        ldx #UI_LIST_COL
        jsr ui_goto
        lda #UI_COL_TEXT
        sta ed_color
        lda ed_t3
        jsr ed_list_entry
        lda ed_t3
        cmp ed_list_sel
        bne el_next
        lda ed_t2
        clc
        adc #UI_LIST_ROW
        tay
        jsr ui_reverse_row
el_next:
        inc ed_t2
        lda ed_t2
        cmp #UI_LIST_ROWS
        bne !-
        rts

// A = entry index: print its name at the cursor
ed_list_entry:
        ldx ed_list_kind
        cpx #LIST_FILES
        beq le_file
        cpx #LIST_FONT
        beq le_font
        cpx #LIST_BIGFONT
        beq le_big
        // music: NO MUSIC, catalog, FROM DISK
        cmp #0
        bne !+
        lda #<str_no_music
        ldy #>str_no_music
        jmp ui_puts
!:      jsr le_last
        beq le_disk
        sec
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
!:      jsr le_last
        beq le_disk
        clc
        adc CATALOG + CAT_N_SIDS
        sec
        sbc #FONT_BUILTINS
        jmp le_record
le_big:
        cmp #BIG_BUILTIN_ROM2X2
        bcc !+
        bne !++
        lda #<str_big_rom
        ldy #>str_big_rom
        jmp ui_puts
!:      lda #<str_big_none
        ldy #>str_big_none
        jmp ui_puts
!:      jsr le_last
        beq le_disk
        clc
        adc CATALOG + CAT_N_SIDS
        adc CATALOG + CAT_N_FONTS
        sec
        sbc #BIG_BUILTINS
le_record:
        jsr cat_rec_addr            // keeps ed_scr/ed_colp
        lda ed_ptr
        sta ed_str
        lda ed_ptr + 1
        sta ed_str + 1
        ldx #CAT_NAME_LEN
        jmp ui_putn
le_disk:
        lda #<str_from_disk
        ldy #>str_from_disk
        jmp ui_puts
le_file:
        jsr dir_entry_addr
        sta ed_t0                   // name length
        ldy #0
!:      cpy ed_t0
        beq !++
        sty ed_t1
        lda (ed_ptr),y
        jsr ui_pet2sc
        bcc !+
        lda #SC_UNKNOWN & SC_MAX
!:      jsr ui_putc                 // keeps ed_ptr
        ldy ed_t1
        iny
        bne !--
!:      rts

// Z set if A is the last entry (FROM DISK); keeps A
le_last:
        ldx ed_list_n
        dex
        stx ed_t0
        cmp ed_t0
        rts

el_head_lo:     .byte <str_list_music, <str_list_font, <str_list_disk, <str_list_big
el_head_hi:     .byte >str_list_music, >str_list_font, >str_list_disk, >str_list_big

str_list_music: Str("MUSIC")
str_list_font:  Str("FONT")
str_list_disk:  Str("DISK")
str_hint_list:  Str("CRSR SELECT  RETURN OK  STOP BACK")
str_from_disk:  Str("FROM DISK...")
str_reading_dir: Str("READING DIRECTORY...")
str_no_files:   Str("NO PRG FILES ON DISK")
