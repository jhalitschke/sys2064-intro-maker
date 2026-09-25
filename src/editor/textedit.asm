#importonce
// ---------------------------------------------------------------------------
// textedit.asm - title editor (overwrite) and scroll text editor (insert).
// ---------------------------------------------------------------------------

// ==== title ===================================================================
ed_title:
        lda #0
        sta ed_title_cur
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_title)
        lda #<str_hint_title
        ldy #>str_hint_title
        jsr ui_hint
et_loop:
        jsr et_draw
        jsr ui_getkey
        cmp #KEY_STOP
        bne !+
        rts
!:      ldx ed_title_cur
        cmp #KEY_CRSR_LEFT
        bne !+
        cpx #0
        beq et_loop
        dec ed_title_cur
        jmp et_loop
!:      cmp #KEY_CRSR_RIGHT
        bne !+
        cpx #TITLE_LEN - 1
        beq et_loop
        inc ed_title_cur
        jmp et_loop
!:      cmp #KEY_CRSR_UP
        bne !+
        cpx #SCREEN_COLS
        bcc et_loop
        txa
        sbc #SCREEN_COLS            // carry set
        sta ed_title_cur
        jmp et_loop
!:      cmp #KEY_CRSR_DOWN
        bne !+
        cpx #SCREEN_COLS
        bcs et_loop
        txa
        adc #SCREEN_COLS            // carry clear
        sta ed_title_cur
        jmp et_loop
!:      cmp #KEY_HOME
        bne !+
        lda #0
        sta ed_title_cur
        jmp et_loop
!:      cmp #KEY_DEL
        bne !+
        cpx #0                      // overwrite mode: back + blank
        beq et_loop
        dex
        stx ed_title_cur
        lda #SC_SPACE
        sta cfg_title,x
        jmp et_loop
!:      jsr ui_pet2sc
        bcs et_loop
        ldx ed_title_cur
        sta cfg_title,x
        cpx #TITLE_LEN - 1
        beq !+
        inc ed_title_cur
!:      jmp et_loop

// title rows with the cursor reversed
et_draw:
        ldx #TITLE_LEN - 1
!:      lda cfg_title,x
        sta SCREEN + UI_TITLE_ROW * SCREEN_COLS,x
        lda #UI_COL_TEXT
        sta COLRAM + UI_TITLE_ROW * SCREEN_COLS,x
        dex
        bpl !-
        ldx ed_title_cur
        lda cfg_title,x
        eor #SC_REVERSE
        sta SCREEN + UI_TITLE_ROW * SCREEN_COLS,x
        lda #UI_COL_CURSOR
        sta COLRAM + UI_TITLE_ROW * SCREEN_COLS,x
        rts

// ==== scroll text =============================================================
// ed_text_len: length, ed_cur: cursor 0..len, ed_win: first shown offset
// (multiple of 40). TEXT + len always holds TEXT_END_MARK.

ed_scrolltext:
        lda #0
        sta ed_cur
        sta ed_cur + 1
        sta ed_win
        sta ed_win + 1
        jsr ui_clear
        Print(0, UI_HEAD_ROW, UI_COL_HEAD, str_scrolltext)
        lda #<str_hint_text
        ldy #>str_hint_text
        jsr ui_hint
es_loop:
        jsr es_window
        jsr es_draw
        jsr ui_getkey
        ldx #ES_KEY_COUNT - 1
!:      cmp es_keys,x
        beq es_key
        dex
        bpl !-
        jsr ui_pet2sc
        bcs es_loop
        jsr es_insert
        jmp es_loop
es_key:
        txa
        asl
        tax
        lda es_key_jump + 1,x
        pha
        lda es_key_jump,x
        pha
        rts                         // -> handler (jumps back to es_loop)

es_keys:
        .byte KEY_STOP, KEY_CRSR_LEFT, KEY_CRSR_RIGHT, KEY_CRSR_UP
        .byte KEY_CRSR_DOWN, KEY_HOME, KEY_DEL, KEY_F1, KEY_F3, KEY_F5, KEY_F7
.errorif * - es_keys != ES_KEY_COUNT, "key table size"
es_key_jump:
        .word es_stop - 1, es_left - 1, es_right - 1, es_up - 1
        .word es_down - 1, es_home - 1, es_del - 1, es_f1 - 1, es_f3 - 1
        .word es_f5 - 1, es_f7 - 1
.errorif (* - es_key_jump) / 2 != ES_KEY_COUNT, "key table mismatch"

es_stop:
        rts                         // handlers are entered via rts: this
                                    // returns to the caller of ed_scrolltext

es_left:
        lda ed_cur
        ora ed_cur + 1
        beq !+
        jsr es_cur_dec
!:      jmp es_loop

es_right:
        jsr es_cur_at_end
        beq !+
        inc ed_cur
        bne !+
        inc ed_cur + 1
!:      jmp es_loop

es_up:
        lda ed_cur
        sec
        sbc #SCREEN_COLS
        tax
        lda ed_cur + 1
        sbc #0
        bcs !+
        lda #0                      // clamp to 0
        tax
!:      stx ed_cur
        sta ed_cur + 1
        jmp es_loop

es_down:
        lda ed_cur
        clc
        adc #SCREEN_COLS
        sta ed_cur
        bcc !+
        inc ed_cur + 1
!:      lda ed_text_len             // clamp to len
        cmp ed_cur
        lda ed_text_len + 1
        sbc ed_cur + 1
        bcs !+
        lda ed_text_len
        sta ed_cur
        lda ed_text_len + 1
        sta ed_cur + 1
!:      jmp es_loop

es_home:
        lda #0
        sta ed_cur
        sta ed_cur + 1
        jmp es_loop

es_f1:  lda #CTRL_SPEED1
        jmp es_ins_code
es_f3:  lda #CTRL_SPEED2
        jmp es_ins_code
es_f5:  lda #CTRL_SPEED4
        jmp es_ins_code
es_f7:  lda #CTRL_PAUSE
es_ins_code:
        jsr es_insert
        jmp es_loop

// delete the char left of the cursor
es_del:
        lda ed_cur
        ora ed_cur + 1
        beq es_del_done
        // move TEXT + cur .. TEXT + len (incl. end mark) down by one
        jsr es_count_tail           // ed_t0/1 = len - cur + 1
        jsr es_ptr_cur              // ed_ptr = TEXT + cur
        lda ed_ptr
        sec
        sbc #1
        sta ed_ptr2
        lda ed_ptr + 1
        sbc #0
        sta ed_ptr2 + 1
        jsr mem_copy_down
        jsr es_cur_dec
        lda ed_text_len
        bne !+
        dec ed_text_len + 1
!:      dec ed_text_len
es_del_done:
        jmp es_loop

// A = byte to insert at the cursor
es_insert:
        pha
        lda ed_text_len
        cmp #<TEXT_MAX
        bne !+
        lda ed_text_len + 1
        cmp #>TEXT_MAX
        bne !+
        pla                         // text full
        jmp ui_flash
!:      jsr es_count_tail           // len - cur + 1 bytes incl. end mark
        jsr es_ptr_cur
        lda ed_ptr
        clc
        adc #1
        sta ed_ptr2
        lda ed_ptr + 1
        adc #0
        sta ed_ptr2 + 1
        jsr mem_copy_up
        pla
        ldy #0
        sta (ed_ptr),y
        inc ed_cur
        bne !+
        inc ed_cur + 1
!:      inc ed_text_len
        bne !+
        inc ed_text_len + 1
!:      rts

// Z set if the cursor is at the end of the text
es_cur_at_end:
        lda ed_cur
        cmp ed_text_len
        bne !+
        lda ed_cur + 1
        cmp ed_text_len + 1
!:      rts

es_cur_dec:
        lda ed_cur
        bne !+
        dec ed_cur + 1
!:      dec ed_cur
        rts

// ed_t0/ed_t1 = len - cur + 1
es_count_tail:
        lda ed_text_len
        sec
        sbc ed_cur
        sta ed_t0
        lda ed_text_len + 1
        sbc ed_cur + 1
        sta ed_t1
        inc ed_t0
        bne !+
        inc ed_t1
!:      rts

// ed_ptr = TEXT + cur
es_ptr_cur:
        lda #<TEXT
        clc
        adc ed_cur
        sta ed_ptr
        lda #>TEXT
        adc ed_cur + 1
        sta ed_ptr + 1
        rts

// keep the cursor inside the window: win <= cur < win + 720
es_window:
!:      lda ed_cur                  // while cur < win: win -= 40
        cmp ed_win
        lda ed_cur + 1
        sbc ed_win + 1
        bcs !+
        lda ed_win
        sec
        sbc #SCREEN_COLS
        sta ed_win
        bcs !-
        dec ed_win + 1
        jmp !-
!:      lda ed_win                  // while cur >= win + 720: win += 40
        clc
        adc #<UI_TEXT_CELLS
        sta ed_t0
        lda ed_win + 1
        adc #>UI_TEXT_CELLS
        sta ed_t1
        lda ed_cur
        cmp ed_t0
        lda ed_cur + 1
        sbc ed_t1
        bcc !+
        lda ed_win
        clc
        adc #SCREEN_COLS
        sta ed_win
        bcc !-
        inc ed_win + 1
        jmp !-
!:      rts

// draw rows UI_TEXT_ROW.. with the text from ed_win, cursor reversed
es_draw:
        lda #<TEXT
        clc
        adc ed_win
        sta ed_ptr
        lda #>TEXT
        adc ed_win + 1
        sta ed_ptr + 1
        lda #<ES_SCREEN
        sta ed_scr
        lda #>ES_SCREEN
        sta ed_scr + 1
        lda #<ES_COLOR
        sta ed_colp
        lda #>ES_COLOR
        sta ed_colp + 1
        // ed_t0/1 = chars left in the text (len - win)
        lda ed_text_len
        sec
        sbc ed_win
        sta ed_t0
        lda ed_text_len + 1
        sbc ed_win + 1
        sta ed_t1
        // ed_t2/3 = cursor offset in the window (cur - win)
        lda ed_cur
        sec
        sbc ed_win
        sta ed_t2
        lda ed_cur + 1
        sbc ed_win + 1
        sta ed_t3
        lda #<UI_TEXT_CELLS
        sta ed_num
        lda #>UI_TEXT_CELLS
        sta ed_num + 1
        ldy #0
es_cell:
        lda ed_t0
        ora ed_t1
        beq es_blank
        lda (ed_ptr),y
        jsr es_display_code
        tax
        lda ed_t0
        bne !+
        dec ed_t1
!:      dec ed_t0
        txa
        jmp es_put
es_blank:
        lda #SC_SPACE
es_put:
        ldx #UI_COL_TEXT
        pha
        lda ed_t2
        ora ed_t3
        bne !+
        pla                         // cursor cell
        eor #SC_REVERSE
        pha
        ldx #UI_COL_CURSOR
!:      pla
        sta (ed_scr),y
        txa
        sta (ed_colp),y
        // cursor offset counts down (stops below 0 via wrap to $ffff: ok,
        // it never reaches 0 again within 720 cells)
        lda ed_t2
        bne !+
        dec ed_t3
!:      dec ed_t2
        inc ed_ptr
        bne !+
        inc ed_ptr + 1
!:      inc ed_scr
        inc ed_colp
        bne !+
        inc ed_scr + 1
        inc ed_colp + 1
!:      lda ed_num
        bne !+
        dec ed_num + 1
!:      dec ed_num
        lda ed_num
        ora ed_num + 1
        bne es_cell
        // status: CHARS n/5118
        Goto(0, UI_STATUS_ROW, UI_COL_STATUS)
        lda #<str_chars
        ldy #>str_chars
        jsr ui_puts
        lda ed_text_len
        sta ed_num
        lda ed_text_len + 1
        sta ed_num + 1
        jsr ui_putdec
        lda #<str_max_len_sp
        ldy #>str_max_len_sp
        jmp ui_puts

// A = text byte -> screen code for display
es_display_code:
        cmp #SC_MAX + 1
        bcc !+
        ldx #ES_CODE_COUNT - 1
es_dc:  cmp es_codes,x
        beq es_dc_found
        dex
        bpl es_dc
        lda #SC_UNKNOWN
!:      rts
es_dc_found:
        lda es_code_sc,x
        rts

es_codes:
        .byte CTRL_SPEED1, CTRL_SPEED2, CTRL_SPEED4, CTRL_PAUSE
.errorif * - es_codes != ES_CODE_COUNT, "code table size"
es_code_sc:
        .byte SC_CTRL_SPEED1, SC_CTRL_SPEED2, SC_CTRL_SPEED4, SC_CTRL_PAUSE

.label ES_SCREEN = SCREEN + UI_TEXT_ROW * SCREEN_COLS
.label ES_COLOR = COLRAM + UI_TEXT_ROW * SCREEN_COLS

// ==== memory moves ============================================================
// copy ed_t0/1 bytes from (ed_ptr) to (ed_ptr2), backwards (dst > src)
// 18 cycles per byte
mem_copy_up:
        lda ed_ptr + 1
        clc
        adc ed_t1
        sta ed_ptr + 1
        lda ed_ptr2 + 1
        clc
        adc ed_t1
        sta ed_ptr2 + 1
        ldx ed_t1                   // full pages
        ldy ed_t0                   // partial page first (top)
        beq mcu_pages
!:      dey
        lda (ed_ptr),y
        sta (ed_ptr2),y
        cpy #0
        bne !-
mcu_pages:
        dex
        bmi mcu_done
        dec ed_ptr + 1
        dec ed_ptr2 + 1
        ldy #0
!:      dey
        lda (ed_ptr),y
        sta (ed_ptr2),y
        cpy #0
        bne !-
        jmp mcu_pages
mcu_done:
        rts                         // ed_ptr is back at the block base

// copy ed_t0/1 bytes from (ed_ptr) to (ed_ptr2), forwards (dst < src)
mem_copy_down:
        ldy #0
        ldx ed_t1
        beq mcd_part
!:      lda (ed_ptr),y
        sta (ed_ptr2),y
        iny
        bne !-
        inc ed_ptr + 1
        inc ed_ptr2 + 1
        dex
        bne !-
mcd_part:
        ldx ed_t0
        beq mcd_done
!:      lda (ed_ptr),y
        sta (ed_ptr2),y
        iny
        dex
        bne !-
mcd_done:
        rts

str_title:        Str("TITLE")
str_hint_title:   Str("CRSR MOVE  DEL  HOME  STOP BACK")
str_scrolltext:   Str("SCROLLTEXT")
str_hint_text:    Str("F1 F3 F5 SPEED  F7 PAUSE  STOP BACK")
str_chars:        Str("CHARS ")
str_max_len_sp:   Str("/5118  ")
