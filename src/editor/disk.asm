#importonce
// ---------------------------------------------------------------------------
// disk.asm - LOAD, SAVE and drive status via KERNAL.
// ---------------------------------------------------------------------------

// A = name length, X/Y = name -> load to the file's address.
// Carry set on error.
disk_load:
        jsr SETNAM
        lda #LFN_DATA
        ldx ed_dev
        ldy #SA_LOAD_FILE_ADDR
        jsr SETLFS
        lda #0                      // 0 = load, not verify
        jmp LOAD

disk_load_catalog:
        lda #CATALOG_FNAME_LEN
        ldx #<str_catalog_file
        ldy #>str_catalog_file
        jsr disk_load
        bcs !+
        lda CATALOG + CAT_N_SIDS
        cmp #CAT_MAX_SIDS + 1
        bcs !+
        lda CATALOG + CAT_N_FONTS
        cmp #CAT_MAX_FONTS + 1
        bcs !+
        lda CATALOG + CAT_N_BIGFONTS
        cmp #CAT_MAX_BIGFONTS + 1
        bcc dlc_done
!:      lda #0                      // no (valid) catalog: 0 entries
        sta CATALOG + CAT_N_SIDS
        sta CATALOG + CAT_N_FONTS
        sta CATALOG + CAT_N_BIGFONTS
        lda #<str_catalog_missing
        ldy #>str_catalog_missing
        jsr ed_status_set
dlc_done:
        rts

// ed_ptr = catalog record: load its file. Carry set on error (the status
// line then shows LOAD ERROR and the drive status).
disk_load_rec:
        lda ed_ptr
        clc
        adc #CAT_FNAME
        sta ed_t0
        lda ed_ptr + 1
        adc #0
        sta ed_t1
        ldy #CAT_FNLEN
        lda (ed_ptr),y
        ldx ed_t0
        ldy ed_t1
        jsr disk_load
        bcc !+
        lda #<str_load_error
        ldy #>str_load_error
        jsr ed_status_set
        jsr disk_read_status
        sec
!:      rts

// ---- save ------------------------------------------------------------------
ed_save:
        lda #0
        sta ed_fname_len
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_save)
        Print(0, UI_FNAME_ROW, UI_COL_TEXT, str_name)
        lda #<str_hint_save
        ldy #>str_hint_save
        jsr ui_hint
sv_loop:
        jsr sv_draw
        jsr ui_getkey
        cmp #KEY_STOP
        bne !+
        rts                         // cancel
!:      cmp #KEY_RETURN
        bne !+
        lda ed_fname_len
        beq sv_loop
        jmp sv_save
!:      cmp #KEY_DEL
        bne !+
        lda ed_fname_len
        beq sv_loop
        dec ed_fname_len
        jmp sv_loop
!:      ldx ed_fname_len
        cpx #FNAME_MAX
        beq sv_loop
        pha
        jsr ui_pet2sc               // only checks the range here
        pla
        bcs sv_loop
        sta ed_fname,x              // file name stays PETSCII
        inc ed_fname_len
        jmp sv_loop

// file name + cursor
sv_draw:
        Goto(UI_FNAME_COL, UI_FNAME_ROW, UI_COL_KEY)
        ldx #0
!:      cpx ed_fname_len
        beq !+
        lda ed_fname,x
        jsr ui_pet2sc
        stx ed_t0
        jsr ui_putc
        ldx ed_t0
        inx
        bne !-
!:      lda #SC_REV_SPACE           // cursor
        jsr ui_putc
        lda #SC_SPACE
        jsr ui_putc
        rts

sv_save:
        jsr ed_prepare_intro
        lda #0
        sta rt_preview
        lda #<runtime_start
        sta ENTRY_OPERAND
        lda #>runtime_start
        sta ENTRY_OPERAND + 1
        Print(0, UI_STATUS_ROW, UI_COL_STATUS, str_saving)
        lda cfg_link_len
        ora cfg_link_len + 1
        beq !+
        jsr link_save               // leaves the drive status
        jmp sv_patch_back
!:      lda ed_fname_len
        ldx #<ed_fname
        ldy #>ed_fname
        jsr SETNAM
        lda #LFN_DATA
        ldx ed_dev
        ldy #SA_SAVE
        jsr SETLFS
        lda #<BASIC_START
        sta SAVE_PTR
        lda #>BASIC_START
        sta SAVE_PTR + 1
        jsr ed_text_ptr_end         // ed_ptr = end mark
        ldx ed_ptr
        ldy ed_ptr + 1
        inx                         // end address is exclusive
        bne !+
        iny
!:      lda #SAVE_PTR
        jsr SAVE
        jsr sv_patch_back
        jsr ed_status_clear
        ldx #0
        jmp disk_read_status
sv_patch_back:
        lda #<editor_start          // patch back, or the editor would
        sta ENTRY_OPERAND           // start the runtime next time
        lda #>editor_start
        sta ENTRY_OPERAND + 1
        rts

// ---- drive status ----------------------------------------------------------
// read the error channel into ed_status_buf from position X on
disk_read_status:
        stx ed_t3
        lda #0
        jsr SETNAM
        lda #LFN_CMD
        ldx ed_dev
        ldy #SA_CMD
        jsr SETLFS
        jsr OPEN
        bcs drs_close
        ldx ed_t3
        jsr drs_read_open
drs_close:
        jsr CLRCHN
        lda #LFN_CMD
        jmp CLOSE

// read the open command channel into ed_status_buf from position X on
drs_read_open:
        stx ed_t3
        ldx #LFN_CMD
        jsr CHKIN
        bcs drs_done
drs_loop:
        jsr READST
        bne drs_done                // EOF, timeout or device not present
        jsr CHRIN
        cmp #PET_CR
        beq drs_done
        jsr ui_pet2sc
        bcc !+
        lda #SC_UNKNOWN & SC_MAX
!:      ldx ed_t3
        cpx #SCREEN_COLS
        bcs drs_loop
        sta ed_status_buf,x
        inc ed_t3
        jmp drs_loop
drs_done:
        jmp CLRCHN

// A/Y = string -> ed_status_buf (padded), X = length
ed_status_set:
        sta ed_str
        sty ed_str + 1
        jsr ed_status_clear
        ldy #0
!:      lda (ed_str),y
        cmp #STR_END
        beq !+
        sta ed_status_buf,y
        iny
        bne !-
!:      tya
        tax
        rts

str_catalog_file:
        .encoding "petscii_upper"
        .text "CATALOG"
.errorif * - str_catalog_file != CATALOG_FNAME_LEN, "catalog file name length"
str_catalog_missing: Str("CATALOG MISSING")
str_load_error: Str("LOAD ERROR ")
str_save:       Str("SAVE")
str_name:       Str("NAME:")
str_hint_save:  Str("RETURN SAVE  STOP CANCEL")
str_saving:     Str("SAVING...")
