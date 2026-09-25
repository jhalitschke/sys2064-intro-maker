#importonce
// ---------------------------------------------------------------------------
// ui.asm - print routines, write screen codes directly to screen/colour RAM.
// Strings are screen codes terminated by STR_END.
// ---------------------------------------------------------------------------

// Str("TEXT") - screen code string with terminator
.macro Str(text) {
        .encoding "screencode_upper"
        .text text
        .byte STR_END
}

// Print(col, row, colour, label)
.macro Print(col, row, color, label) {
        ldx #col
        ldy #row
        jsr ui_goto
        lda #color
        sta ed_color
        lda #<label
        ldy #>label
        jsr ui_puts
}

// Goto(col, row) + set colour
.macro Goto(col, row, color) {
        ldx #col
        ldy #row
        jsr ui_goto
        lda #color
        sta ed_color
}

// editor screen mode, colours, clear screen
ui_init:
        lda #ED_D011
        sta VIC_CTRL1
        lda #ED_D016
        sta VIC_CTRL2
        lda #ED_D018
        sta VIC_MEMPTR
        lda #UI_BORDER
        sta VIC_BORDER
        lda #UI_BG
        sta VIC_BG
        // fall through

ui_clear:
        ldx #0
!:      lda #SC_SPACE
        sta SCREEN,x
        sta SCREEN + $100,x
        sta SCREEN + $200,x
        sta SCREEN + SCREEN_SIZE - $100,x
        lda #UI_COL_TEXT
        sta COLRAM,x
        sta COLRAM + $100,x
        sta COLRAM + $200,x
        sta COLRAM + SCREEN_SIZE - $100,x
        inx
        bne !-
        rts

// X = column, Y = row -> ed_scr / ed_colp
ui_goto:
        txa
        clc
        adc ui_row_lo,y
        sta ed_scr
        sta ed_colp
        lda ui_row_hi,y
        adc #0
        sta ed_scr + 1
        clc
        adc #(>COLRAM) - (>SCREEN)
        sta ed_colp + 1
        rts

// A = screen code -> screen, colour ed_color, advance
ui_putc:
        ldy #0
        sta (ed_scr),y
        lda ed_color
        sta (ed_colp),y
        inc ed_scr
        inc ed_colp
        bne !+
        inc ed_scr + 1
        inc ed_colp + 1
!:      rts

// A/Y = string address (lo/hi)
ui_puts:
        sta ed_str
        sty ed_str + 1
!:      ldy #0
        lda (ed_str),y
        cmp #STR_END
        beq !+
        jsr ui_putc
        inc ed_str
        bne !-
        inc ed_str + 1
        bne !-
!:      rts

// print X bytes from (ed_str)
ui_putn:
        stx ed_n_count
        ldy #0
        sty ed_n_index
!:      ldy ed_n_index
        lda (ed_str),y
        jsr ui_putc
        inc ed_n_index
        dec ed_n_count
        bne !-
        rts

// print ed_num (16 bit) as decimal without leading zeros
ui_putdec:
        lda #0
        sta ed_lead
        ldx #0
ud_digit:
        lda #0
        sta ed_digit
!:      lda ed_num
        sec
        sbc ui_pow10_lo,x
        tay
        lda ed_num + 1
        sbc ui_pow10_hi,x
        bcc !+
        sta ed_num + 1
        sty ed_num
        inc ed_digit
        bne !-
!:      cpx #UI_POW10_COUNT - 1     // always print the last digit
        beq ud_print
        lda ed_digit
        ora ed_lead
        beq ud_skip                 // leading zero
ud_print:
        lda #1
        sta ed_lead
        lda ed_digit
        ora #SC_DIGIT_0
        stx ed_t1
        jsr ui_putc
        ldx ed_t1
ud_skip:
        inx
        cpx #UI_POW10_COUNT
        bne ud_digit
        rts

// A = number 0-99 -> print decimal
ui_putbyte:
        sta ed_num
        lda #0
        sta ed_num + 1
        jmp ui_putdec

// Y = row: fill with spaces
ui_clear_row:
        ldx #0
        jsr ui_goto
        ldy #SCREEN_COLS - 1
        lda #SC_SPACE
!:      sta (ed_scr),y
        dey
        bpl !-
        rts

// Y = row: toggle reverse for the whole row
ui_reverse_row:
        ldx #0
        jsr ui_goto
        ldy #SCREEN_COLS - 1
!:      lda (ed_scr),y
        eor #SC_REVERSE
        sta (ed_scr),y
        dey
        bpl !-
        rts

// A/Y = string: show as status message in the status row
ui_status:
        pha
        tya
        pha
        ldy #UI_STATUS_ROW
        jsr ui_clear_row
        lda #UI_COL_STATUS
        sta ed_color
        pla
        tay
        pla
        jmp ui_puts

// A/Y = string: show as hint in the hint row
ui_hint:
        pha
        tya
        pha
        ldy #UI_HINT_ROW
        jsr ui_clear_row
        lda #UI_COL_KEY
        sta ed_color
        pla
        tay
        pla
        jmp ui_puts

// wait for a key -> A (PETSCII)
ui_getkey:
!:      jsr GETIN
        beq !-
        rts

// A = PETSCII -> screen code; carry set if not accepted ($20-$5f only)
ui_pet2sc:
        cmp #PET_FIRST
        bcc up_bad
        cmp #PET_LAST + 1
        bcs up_bad
        cmp #PET_LETTERS
        bcc up_ok                   // $20-$3f: unchanged
        sbc #PET_LETTERS            // carry is set
up_ok:  clc
        rts
up_bad: sec
        rts

// flash the border briefly (input limit reached)
ui_flash:
        lda #UI_COL_FLASH
        sta VIC_BORDER
        lda KERNAL_JIFFY_LO
        clc
        adc #UI_FLASH_JIFFIES
!:      cmp KERNAL_JIFFY_LO
        bne !-
        lda #UI_BORDER
        sta VIC_BORDER
        rts

ui_pow10_lo:    .byte <1000, <100, <10, <1
ui_pow10_hi:    .byte >1000, >100, >10, >1
ui_row_lo:      .fill SCREEN_ROWS, <(SCREEN + i * SCREEN_COLS)
ui_row_hi:      .fill SCREEN_ROWS, >(SCREEN + i * SCREEN_COLS)
